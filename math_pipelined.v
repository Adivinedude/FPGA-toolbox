////////////////////////////////////////////////////////////////////////////////
// Filename:	math_pipelined.v
//
// Project:	math_pipelined 
//
// Purpose:	a fast pipelined ripple carry adder with configurable
//          width and latency.
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

module math_pipelined
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4
    )
    (
        input   wire                clk,
        input   wire                ce,
        input   wire    [WIDTH-1:0] I1,
        input   wire    [WIDTH-1:0] I2,
        output  wire    [WIDTH-1:0] sum,
        output  wire    [WIDTH-1:0] sub,
        output  wire                gate_and,
        output  wire                gate_or,
        output  wire                gate_xor
    );
    `ifndef FORMAL
        `include "./toolbox/recursion_iterators.v"
    `else
        `include "recursion_iterators.v"
    `endif
    // determine the chunk width. knowing that each chunk will take 1 tick, 'width' / 'latency' will provide
    // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    localparam ALU_WIDTH  = WIDTH / LATENCY * LATENCY == WIDTH ? WIDTH / LATENCY : WIDTH / LATENCY + 1; 
    // find the minimum amount of chunks needed to contain the counter
    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1; 
    // find the size of the last chunk needed to contain the counter.
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH;

    reg  [WIDTH-1:0] r_input = 0;
    always @( posedge clk ) begin
        if( ce ) begin
            r_input <= I2;
        end else begin
            r_input <= 0;
        end
    end

    genvar idx;
    genvar unit_index;
    genvar input_index;

//addition
    wire [CHUNK_COUNT-1:0] w_sum_cout_chain;
    assign w_sum_cout_chain[CHUNK_COUNT-1] = 1'b0;  // removes warning about bit being unset. will be optimized away
    reg  [CHUNK_COUNT-1:0] r_sum_cout_chain = 0;
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : sum_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign { w_sum_cout_chain[idx], sum[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, I1[idx*ALU_WIDTH+:ALU_WIDTH] } + { 1'b0, r_input[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? 1'b0 : r_sum_cout_chain[idx-1]);
        end else begin    // == LAST_CHUNK
            assign sum[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] = I1[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] + { 1'b0, r_input[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + (idx == 0 ? 1'b0 : r_sum_cout_chain[idx-1]);
        end
    end 
    always @( posedge clk ) begin
        if( ce ) begin
            r_sum_cout_chain <= 0;
        end else begin
            r_sum_cout_chain <= w_sum_cout_chain;
        end
    end

//subtraction
    wire [CHUNK_COUNT-1:0] w_sub_cout_chain;
    assign w_sub_cout_chain[CHUNK_COUNT-1] = 1'b0;  // removes warning about bit being unset. will be optimized away
    reg  [CHUNK_COUNT-1:0] r_sub_cout_chain = 0;
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : sub_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign { w_sub_cout_chain[idx], sub[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, I1[idx*ALU_WIDTH+:ALU_WIDTH] } - { 1'b0, r_input[idx*ALU_WIDTH+:ALU_WIDTH] } - (idx == 0 ? 1'b0 : r_sub_cout_chain[idx-1]);
        end else begin    // == LAST_CHUNK
            assign sub[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] = I1[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] - { 1'b0, r_input[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } - (idx == 0 ? 1'b0 : r_sub_cout_chain[idx-1]);
        end
    end 
    always @( posedge clk ) begin
        if( ce ) begin
            r_sub_cout_chain <= 0;
        end else begin
            r_sub_cout_chain <= w_sub_cout_chain;
        end
    end

//gate_and
    localparam CMP_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam CMP_VECTOR_SIZE      = f_NaryRecursionGetVectorSize( CHUNK_COUNT, CMP_LUT_WIDTH );   // use the operator input width to find how many units are needed
    reg [CHUNK_COUNT+CMP_VECTOR_SIZE-1:0] r_cmp = 0;
    `define OPERATION &
    // take sections of 'I1' & 'I2' then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : CMP_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            always @( posedge clk ) r_cmp[idx] <= `OPERATION{ I1[idx*ALU_WIDTH+:ALU_WIDTH], I2[idx*ALU_WIDTH+:ALU_WIDTH] };// edit operation here
        end else begin    // == LAST_CHUNK
            always @( posedge clk ) r_cmp[idx] <= `OPERATION{ I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE], I2[idx*ALU_WIDTH+:LAST_CHUNK_SIZE] };// edit operation here
        end
    end
        // loop through each unit and assign the in and outs
        for( unit_index = 0; unit_index < CMP_VECTOR_SIZE; unit_index = unit_index + 1) begin : CMP_unit_loop
            // make the input wires for this unit   
            wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index)-1:0] unit_inputs;
            // assign the inputs to their proper place
            for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : CMP_input_loop
                    assign unit_inputs[input_index] = r_cmp[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index)];
            end
            // perform the function and store the output
            always @( posedge clk ) r_cmp[CHUNK_COUNT+unit_index] <= `OPERATION unit_inputs;  // edit operation here
        end
        `undef OPERATION

endmodule
