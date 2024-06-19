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
            parameter WIDTH     = 32,
            parameter LATENCY   = 1
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
    // the 'reg [WIDTH-1:0] counter;' will be broken into chunks, the number of which will be based on the LATENCY 
    // each chunk's arithmetic COUT will be stored in the reg carrie_chain[] for the next chunks CIN.
    // the first chunk will not have a CIN, but the enable signal
    // the last chunk will not have a COUT
    // the counter may contain only one chunk.

    integer idx;    // for loop iterator
    `ifndef FORMAL
        `include "toolbox/recursion_iterators.v"
    `else
        `include "recursion_iterators.v"
    `endif
    // 'trigger' comparator construction diagram
    // By using a overlapping slope structure (name not known), the comparators latency can be controlled
    // in order to produce a valid output, 1 clock after the alu's carry chain has completely propagated 
    //  LUT width 2                                 LUT width 3                                 LUT width 4
    //  base #  0___1   2   3   4   5   6   7   8   9   0___1___2   3   4   5   6   7   8   9   0___1___2___3   4   5   6   7   8   9
    //              0___|   |   |   |   |   |   |   |           0___|___|   |   |   |   |   |               0___|___|___|   |   |   |
    //                  1___|   |   |   |   |   |   |                   1___|___|   |   |   |                           1___|___|___|
    //                      2___|   |   |   |   |   |                           2___|___|   |                                       trigger
    //                          3___|   |   |   |   |                                   3___|
    //                              4___|   |   |   |                                       trigger
    //                                  5___|   |   |
    //                                      6___|   |
    //                                          7___|
    //                                              trigger

    // determine the chunk width. knowing that each chunk will take 1 tick, 'width' / 'latency' will provide
    localparam ALU_WIDTH  = WIDTH / LATENCY * LATENCY == WIDTH ? WIDTH / LATENCY : WIDTH / LATENCY + 1; // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1; // find the minimum amount of chunks needed to contain the counter
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH; // find the size of the last chunk needed to contain the counter.
    localparam CMP_LUT_WIDTH =      f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_REG_WIDTH =      f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed
    localparam CMP_LAST_LUT_WIDTH = f_TailRecursionGetLastUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH); // find the width of the last unit.
    // initial $display("WIDTH %d\nLATENCY %d\nALU_WIDTH %d\nCHUNK_COUNT %d\nLAST_CHUNK_SIZE %d\nCMP_LUT_WIDTH %d\nCMP_REG_WIDTH %d \nCMP_LAST_LUT_WIDTH:%d"
        // ,WIDTH, LATENCY, ALU_WIDTH, CHUNK_COUNT, LAST_CHUNK_SIZE, CMP_LUT_WIDTH, CMP_REG_WIDTH, CMP_LAST_LUT_WIDTH);
    // 'Used for formal verification, can be optimized away.
    // 'ready' used to indicate when enable can be 'HIGH'
    // 'valid' used to indicate when strobe may be 'HIGH'
    reg [CHUNK_COUNT+1:0] ready_tracker   = 0;
    assign              ready           = ready_tracker[CHUNK_COUNT+1];
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
                ready_tracker <= { ready_tracker[CHUNK_COUNT:0], 1'b1 };
                strobe_valid  <= 0;
            end
        end
    end

    wire trigger;
    reg [WIDTH-1:0] counter_ff = 'd1;
    generate
        // counter_ff
        if( LATENCY <= 1 ) begin
            assign trigger = counter_ff == reset_value;
            always @( posedge clk ) begin
                if( rst )
                    counter_ff <= 'd1;
                else begin
                    if( enable ) begin
                        counter_ff <= counter_ff + 1'b1;
                        if( trigger )
                            counter_ff <= 'd1;
                    end
                end
            end
        end else begin
            // counter_ff and carry chain
            reg     [CHUNK_COUNT-1:0]   carry_chain = 0;
            always @( posedge clk ) begin
                if( rst ) begin
                    counter_ff <= 'd1;
                    carry_chain <= 0;
                end else begin
                    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin
                        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
                            { carry_chain[idx], counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] } <= { 1'b0, counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? enable : carry_chain[idx-1]);
                        end else begin    // == LAST_CHUNK
                            counter_ff[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] <= counter_ff[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] + (idx == 0 ? enable : carry_chain[idx-1]);
                        end
                    end 
                    if( enable ) begin
                        if( trigger ) begin
                            counter_ff <= 'd1;
                            carry_chain <= 0;
                        end
                    end
                end // !rst
            end 

            reg [CHUNK_COUNT+CMP_REG_WIDTH-1:0] comparator = 0;
            assign trigger = comparator[CHUNK_COUNT+CMP_REG_WIDTH-1];

            // take sections of the counter_ff and perform the operation on them.
            // then store the result in a register for each section.
            always @( posedge clk ) begin
                if( rst ) begin
                    comparator[0+:CHUNK_COUNT] <= 0;
                end else begin
                    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin
                        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
                            comparator[idx] <= counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] == reset_value[idx*ALU_WIDTH+:ALU_WIDTH];
                        end else begin    // == LAST_CHUNK
                            comparator[idx] <= counter_ff[idx*ALU_WIDTH+:LAST_CHUNK_SIZE] == reset_value[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];
                        end
                    end
                end
            end
            genvar unit_index, input_index;
            // the last unit may be a different size than the others. account for this here
            `define input_size  unit_index != (CMP_REG_WIDTH-1)?CMP_LUT_WIDTH-1:CMP_LAST_LUT_WIDTH-1
            // loop through each unit and assign the in and outs
            for( unit_index = 0; unit_index < CMP_REG_WIDTH; unit_index = unit_index + 1) begin
                // initial $display("input_size: %d", `input_size);
                // make the input wires for this unit   
                wire [`input_size:0] unit_inputs;
                // assign the inputs to their proper place
                for( input_index = `input_size; input_index != ~0; input_index = input_index-1 ) begin
                    // initial $display("unit_index: %d input_index:%d func:%d", unit_index, input_index, f_TailRecursionGetStructureInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index));
                    assign unit_inputs[input_index] = 
                    comparator[f_TailRecursionGetUnitInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index)];
                end
                // perform the function and store the output
                always @( posedge clk ) begin
                    if( rst )
                        comparator[CHUNK_COUNT+unit_index] <= 0;
                    else
                        comparator[CHUNK_COUNT+unit_index] <= &unit_inputs;
                end
            end
        end
    endgenerate

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