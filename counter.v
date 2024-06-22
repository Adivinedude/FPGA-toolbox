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
        `ifdef FORMAL
            parameter WIDTH     = 4,
            parameter LATENCY   = 4
        `else
            parameter WIDTH     = 16,
            parameter LATENCY   = 16
        `endif
    )
    (
        input   wire                rst,
        input   wire                clk,
        input   wire                enable,
        input   wire [WIDTH-1:0]    reset_value,
        output  wire                strobe,
        output  wire                ready,
        output  wire                valid
    );

    // 'Used for formal verification, can be optimized away.
    // 'ready' used to indicate when enable can be 'HIGH'
    // 'valid' used to indicate when strobe may be 'HIGH'
    reg [LATENCY:0]     ready_tracker   = 0;
    assign              ready           = ready_tracker[LATENCY];
    reg                 strobe_valid    = 0;
    assign              valid           = strobe_valid;

    always @( posedge clk ) begin
        if( rst ) begin
            ready_tracker <= 'd1;
            strobe_valid  <= 0;
        end else begin
            if( enable ) begin
                ready_tracker <= 'd1;
                if( ready )
                    strobe_valid <= 1'b1;
            end else begin
                ready_tracker <= { ready_tracker[LATENCY-1:0], 1'b1 };
                strobe_valid  <= 0;
            end
        end
    end

    reg     [WIDTH-1:0] counter_ff = 'd1;
    wire    [WIDTH-1:0] w_counter_ff;
    math_pipelined #(.WIDTH(WIDTH), .LATENCY(LATENCY)) counter_plus_plus 
    (
        .clk(   clk ),
        .ce(    enable ),
        .I1(    counter_ff ),
        .I2(    'd1 ),
        .sum(   w_counter_ff )
    );

    wire                trigger;
    assign trigger = counter_ff == reset_value;
    
    always @( posedge clk ) begin
        if( rst )
            counter_ff <= 'd1;
        else begin
            counter_ff <= w_counter_ff;
            if( enable ) begin
                if( trigger )
                    counter_ff <= 'd0;
            end
        end
    end

    reg     strobe_ff = 0;
    assign  strobe  = strobe_ff;
    always @( posedge clk ) begin
        strobe_ff <= 0;   // turn strobe_ff off.
        if( enable ) begin
            if( trigger ) begin
                strobe_ff <= 1;
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
    reg             past_valid          = 0;
    reg             past_valid_1        = 0;

    reg [WIDTH-1:0] tick_counter        = 0;
    reg [WIDTH-1:0] enable_off_counter  = 0;
    always @( posedge clk ) begin
        // verify $past is valid
        past_valid   <= 1;
        past_valid_1 <= past_valid;                    

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
`endif 

`ifdef FORMAL
// Assume inputs
    // // // //
    // rst   //
    // // // //
        // force the test to start in a reset state
        // always @( posedge clk ) if( !past_valid_1 ) assume(rst);
        // force reset not toggle
        // always @( posedge clk ) if( past_valid_1 ) assume( !rst );
    // // // // //
    // enable   //
    // // // // //
            //force 'enable' to be LOW when '!valid' and no more than 2 ticks when 'valid'
            always @( posedge clk ) begin
                if( !past_valid_1 || rst )
                    assume(!enable);
                else begin
                    if( !ready )
                        assume( !enable );
                    else begin
                        if( enable_off_counter >= 2 )
                            assume( enable );
                    end
                end

            end
    // // // // // //
    // reset_value //
    // // // // // //
        // force the 'reset_value' to be greater than 1 but less than sby test 'DEPTH' / 3 b/c of the alternating enable bit
        always @( posedge clk ) assume( reset_value >= 2 && reset_value <= 15 );

        // force the 'reset_value to only change when strobe is HIGH and enable is LOW
        always @( posedge clk )
            if( past_valid && !(strobe && !enable) )
                assume( $stable(reset_value));
    // // // // // // // // // // //
    // counter_ff & tick_counter  //
    // // // // // // // // // // //
    always @( posedge clk )
        if( ready )
            assume( counter_ff == tick_counter + 1 );

// induction testing
// using a 8 bit counter, need a test depth > 255 with enable forced high, 510 with enable toggling
///////////////////////////////////
// Start testing expected behaviors
    // The strobe can only go high when  ticks == 'reset_value'
    always @( posedge clk ) assert( |{  !past_valid_1,
                                        rst,
                                        strobe == &{tick_counter == $past(reset_value), valid }
                                    } );
    // The strobe bit will only stays HIGH for 1 clock cycle
    always @( posedge clk ) assert( !past_valid ||                  // past is invalid
                                    !strobe     ||                  // strobe is off
                                    $changed(strobe)                // strobe has changed to HIGH
                            );

    always @( posedge clk ) cover( strobe );

`endif
endmodule