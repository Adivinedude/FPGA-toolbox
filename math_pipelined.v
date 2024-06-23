////////////////////////////////////////////////////////////////////////////////
// Filename:	math_pipelined.v
//
// Project:	math_pipelined 
//
// Purpose:	a fast pipelined ripple carry ALU with configurable
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
        input   wire    [WIDTH-1:0] I3,
        output  wire    [WIDTH-1:0] sum,
        output  wire    [WIDTH-1:0] sub,
        output  wire                gate_and,
        output  wire                gate_or,
        output  wire                gate_xor,
        output  wire                cmp_eq,
        output  wire                cmp_neq
    );
    //  sum         = I1 + I2
    //  sub         = I1 + I2
    //  gate_and    = &I1
    //  gate_or     = |I1
    //  gate_xor    = ^I1
    //  cmp_eq      = I1 == I3
    //  cmp_neq     = I1 != I3

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
    localparam GATE_AND_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_AND_VECTOR_SIZE      = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_AND_LUT_WIDTH );   // use the operator input width to find how many units are needed
    reg [CHUNK_COUNT+GATE_AND_VECTOR_SIZE-1:0] r_GATE_AND = 0;
    assign gate_and = r_GATE_AND[CHUNK_COUNT+GATE_AND_VECTOR_SIZE-1];
    `define OPERATION &
    // take sections of 'I1' & 'I2' then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_AND_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            always @( posedge clk ) r_GATE_AND[idx] <= `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH];// edit operation here
        end else begin    // == LAST_CHUNK
            always @( posedge clk ) r_GATE_AND[idx] <= `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_AND_VECTOR_SIZE; unit_index = unit_index + 1) begin : GATE_AND_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_AND_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_AND_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_AND_input_loop
                assign unit_inputs[input_index] = r_GATE_AND[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_AND_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        always @( posedge clk ) r_GATE_AND[CHUNK_COUNT+unit_index] <= `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//gate_or
    localparam GATE_OR_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_OR_VECTOR_SIZE      = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_OR_LUT_WIDTH );   // use the operator input width to find how many units are needed
    reg [CHUNK_COUNT+GATE_OR_VECTOR_SIZE-1:0] r_GATE_OR = 0;
    assign gate_or = r_GATE_OR[CHUNK_COUNT+GATE_OR_VECTOR_SIZE-1];

    `define OPERATION |
    // take sections of 'I1' & 'I2' then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_OR_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            always @( posedge clk ) r_GATE_OR[idx] <= `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH];// edit operation here
        end else begin    // == LAST_CHUNK
            always @( posedge clk ) r_GATE_OR[idx] <= `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_OR_VECTOR_SIZE; unit_index = unit_index + 1) begin : GATE_OR_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_OR_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_OR_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_OR_input_loop
                assign unit_inputs[input_index] = r_GATE_OR[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_OR_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        always @( posedge clk ) r_GATE_OR[CHUNK_COUNT+unit_index] <= `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//gate_xor
    localparam GATE_XOR_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_XOR_VECTOR_SIZE      = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_XOR_LUT_WIDTH );   // use the operator input width to find how many units are needed
    reg [CHUNK_COUNT+GATE_XOR_VECTOR_SIZE-1:0] r_GATE_XOR = 0;
    assign gate_xor = r_GATE_XOR[CHUNK_COUNT+GATE_XOR_VECTOR_SIZE-1];

    `define OPERATION ^
    // take sections of 'I1' & 'I2' then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_XOR_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            always @( posedge clk ) r_GATE_XOR[idx] <= `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH] ;// edit operation here
        end else begin    // == LAST_CHUNK
            always @( posedge clk ) r_GATE_XOR[idx] <= `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_XOR_VECTOR_SIZE; unit_index = unit_index + 1) begin : GATE_XOR_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_XOR_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_XOR_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_XOR_input_loop
                assign unit_inputs[input_index] = r_GATE_XOR[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_XOR_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        always @( posedge clk ) r_GATE_XOR[CHUNK_COUNT+unit_index] <= `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//cmp_eq
    localparam CMP_LUT_WIDTH =      f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_REG_WIDTH =      f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed
    localparam CMP_LAST_LUT_WIDTH = f_TailRecursionGetLastUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH); // find the width of the last unit.
 
    reg [CHUNK_COUNT+CMP_REG_WIDTH-1:0] comparator = 0;
    assign cmp_eq = comparator[CHUNK_COUNT+CMP_REG_WIDTH-1];

    // take sections of the I1 and I3 then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : CMP_EQ_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            always @( posedge clk ) comparator[idx] <= I1[idx*ALU_WIDTH+:ALU_WIDTH] == I3[idx*ALU_WIDTH+:ALU_WIDTH];
        end else begin    // == LAST_CHUNK
            always @( posedge clk ) comparator[idx] <= I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE] == I3[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];
        end
    end
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
        always @( posedge clk ) comparator[CHUNK_COUNT+unit_index] <= &unit_inputs;
    end
endmodule
