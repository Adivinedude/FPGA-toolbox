////////////////////////////////////////////////////////////////////////////////
//
// Filename:	counter.v
//
// Project:	counter_with_strobe 
//
// Purpose:	a fast, variable width counter strobe output.
//
// Creator:	Ronald Rainwater
// Data: 2024-6-18
////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2024, Ronald Rainwater
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <http://www.gnu.org/licenses/> for a copy.
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
////////////////////////////////////////////////////////////////////////////////
`default_nettype none

module counter_with_strobe
    #( 
        parameter WIDTH     = 25,
        parameter LATENCY   = 0
    )
    (
        input   wire                rst,
        input   wire                clk,
        input   wire                enable,
        input   wire [WIDTH-1:0]    reset_value,
        output  wire                strobe
    );

    reg                 strobe_ff   = 0;
    reg     [WIDTH-1:0] counter_ff  = 'd1;
    wire    [WIDTH-1:0] w_counter_ff;
    wire                trigger;
    math_lfmr #(.WIDTH(WIDTH), .LATENCY(LATENCY > 0 ? LATENCY - 1 : 0) ) counter_plus_plus  
    (
        .clk(   clk ),
        .rst(   (trigger && enable) || rst ),
        .I1(    counter_ff ),
        .I2(    { {WIDTH-1{1'b0}}, enable } ),
        .I3(    reset_value ),
        .sum(   w_counter_ff ),
        .sub(), .gate_and(), .gate_or(), .gate_xor(),
        .cmp_eq( trigger ), .cmp_neq()
    );   
    always @( posedge clk ) begin
        if( rst )
            counter_ff <= 'd1;
        else begin
            counter_ff <= w_counter_ff;
            if( enable ) begin
                if( trigger )
                    counter_ff <= 'd1;
            end
        end
    end

    assign  strobe  = strobe_ff;
    always @( posedge clk ) begin
        if( rst ) begin
            strobe_ff <= 0;   // turn strobe_ff off.
        end else begin
            strobe_ff <= 0;
            if( enable ) begin
                if( trigger ) begin
                    strobe_ff <= 1'b1;
                end
            end
        end
    end 
/////////////////////////////////////////////
// Test the counter as a blackbox circuit. //
/////////////////////////////////////////////
`ifdef FORMAL
    `define TEST_BENCH_RUNNING
`endif 

`ifdef TEST_BENCH_RUNNING
    // formal verification comparisons values
    integer past_valid_counter = 0;
    wire    past_valid = past_valid_counter > 0;
    always @( posedge clk ) past_valid_counter <= past_valid ? past_valid_counter : past_valid_counter + 1;

    // 'ready' used to indicate when enable can be 'HIGH'
    // 'valid' used to indicate when strobe may be 'HIGH'
    wire    ready;
    wire    valid;

    reg [7:0]   ready_tracker   = 0;
    assign      ready           = LATENCY == 0 ? 1'b1 : ready_tracker >= LATENCY;
    reg         strobe_valid    = 0;
    assign      valid           = strobe_valid;

    always @( posedge clk ) begin
        if( rst ) begin
            ready_tracker <= 'd0;
            strobe_valid  <= 0;
        end else begin
            if( enable ) begin
                ready_tracker <= 'd0;
                if( ready )
                    strobe_valid <= 1'b1;
            end else begin
                ready_tracker <= ready ? ready_tracker : ready_tracker + 1;
                strobe_valid  <= 0;
            end
        end
    end

    reg [WIDTH-1:0] tick_counter        = 0;
    reg [WIDTH-1:0] enable_off_counter  = 0;
    always @( posedge clk ) begin
        // store the current reset_value anytime it is loaded and reset the counter    
        if( rst || strobe ) begin    
            tick_counter = 0;   
        end 
        if( rst || enable ) begin
            enable_off_counter = 0;
        end else begin
            enable_off_counter = enable_off_counter + ready;
        end
        if(!rst && enable ) begin
            // increment the tick counter when 'rst' is HIGH and 'enable' is HIGH
            tick_counter <= tick_counter + 1'b1;
        end
    end

    // 'Used for formal verification, can be optimized away.
`endif 

`ifdef FORMAL
    `define ASSERT assert
    `ifdef FORMAL_COUNTER_WITH_STROBE
        `define ASSUME assume
    `else
        `define ASSUME assert
    `endif
// Assume inputs

// // // // //
// enable   //
// // // // //
    //force 'enable' to be LOW when '!ready' and no more than 2 ticks when 'ready'
    always @( posedge clk ) begin : invalid_enable
        if( !past_valid )
            `ASSUME(!enable);
        else begin
            if( !ready )
                `ASSUME( !enable );
            `ifdef FORMAL_COUNTER_WITH_STROBE
                else begin
                    if( enable_off_counter >= 3 )
                        `ASSUME( enable );
                end
            `endif
        end
    end
// // // // // //
// reset_value //
// // // // // //
    // force the 'reset_value' to be greater than 1 and to stay stable when strobe is 1 tick from going 'HIGH'
    reg lock_reset_value = 0;
    always @( posedge clk ) begin //invalid_reset_value_change: 
        if( strobe ) begin
            lock_reset_value <= 0;
        end else begin
            if( tick_counter + 1 == reset_value )
                lock_reset_value = 1;
        end
        `ASSUME( rst || ( (reset_value > 1) && (lock_reset_value ? $stable(reset_value) : 1) ) );
    end

// // // // // // // // // // //
// counter_ff & tick_counter  //
// // // // // // // // // // //
    always @( posedge clk )
        assume(strobe || counter_ff == tick_counter + 1 );        
// induction testing
// using a 8 bit counter, need a test depth > 255 with enable forced high, 510 with enable toggling
///////////////////////////////////
// Start testing expected behaviors
// The strobe can only go high when  ticks == 'reset_value'
    always @( posedge clk ) strobe_correct:    
        `ASSERT( 
            |{  
                !past_valid,
                strobe == &{tick_counter == $past(reset_value), valid , !$past(rst)}
            } 
        );
// The strobe bit will only stays HIGH for 1 clock cycle
    always @( posedge clk ) strobe_once:    
        `ASSERT( 
            !past_valid ||      // past is invalid
            !strobe     ||      // strobe is off
            $changed(strobe)    // strobe has changed to HIGH
        );
// ensure I didn't break the design with assumptions.
    `ifdef FORMAL_COUNTER_WITH_STROBE
        always @( posedge clk ) cover( strobe );
        always @( posedge clk ) cover( ready );
        always @( posedge clk ) cover( valid );
    `endif
`endif
endmodule