////////////////////////////////////////////////////////////////////////////////
// Filename:	math.v
//
// Project:	math 
//
// Purpose:	Building blocks for a fast pipelined ripple carry ALU with configurable
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

module math_lfmr // linear feedback math register, 1 input, get answer LATENCY clocks later.
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4
    )
    (
        input   wire                clk,
        input   wire                rst,
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
    //  sub         = I1 - I2
    //  gate_and    = &I1
    //  gate_or     = |I1
    //  gate_xor    = ^I1
    //  cmp_eq      = I1 == I3
    //  cmp_neq     = I1 != I3
    //ToDo:
    //  cmp_greater = I1 > I3
    //  cmp_lesser  = I1 < I3

    `ifndef FORMAL
        `include "./toolbox/recursion_iterators.h"
    `else
        `include "recursion_iterators.h"
    `endif
    // determine the chunk width. knowing that each chunk will take 1 tick, 'width' / 'latency' will provide
    // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    // BugFix, prevent divide by zero condition.
    localparam DENOMINATOR = (LATENCY==0) ? 1 : LATENCY;
    localparam ALU_WIDTH  = (WIDTH / DENOMINATOR * DENOMINATOR) == WIDTH 
            ? WIDTH / DENOMINATOR 
            : WIDTH / DENOMINATOR + 1;
    // find the minimum amount of chunks needed to contain the counter
    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1; 
    // find the size of the last chunk needed to contain the counter.
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH;
    // find values for gates
    localparam GATE_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_CARRYCHAIN_WIDTH = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_LUT_WIDTH );// use the operator input width to find how many units are needed
    // find values for cmp
    localparam CMP_LUT_WIDTH        = f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY > 1 ? LATENCY : 1); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_CARRYCHAIN_WIDTH = f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed

//addition 
    reg  [CHUNK_COUNT-1:0]  r_sum_chain = 0;
    wire [CHUNK_COUNT-1:0]  w_sum_chain;
    always @( posedge clk ) begin
        if( rst ) begin
            r_sum_chain <= 0;
        end else begin
            r_sum_chain <= w_sum_chain;
        end
    end

//subtraction
    reg  [CHUNK_COUNT-1:0] r_sub_chain = 0;
    wire [CHUNK_COUNT-1:0] w_sub_chain;
    always @( posedge clk ) begin
        if( rst ) begin
            r_sub_chain <= 0;
        end else begin
            r_sub_chain <= w_sub_chain;
        end
    end

//gate_and
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  r_GATE_AND_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  w_GATE_AND_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_AND_CHAIN <= 0;
        end else begin
            r_GATE_AND_CHAIN <= w_GATE_AND_CHAIN;
        end
    end

//gate_or
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   r_GATE_OR_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   w_GATE_OR_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_OR_CHAIN <= 0;
        end else begin
            r_GATE_OR_CHAIN <= w_GATE_OR_CHAIN;
        end
    end

//gate_xor
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  r_GATE_XOR_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  w_GATE_XOR_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_XOR_CHAIN <= 0;
        end else begin
            r_GATE_XOR_CHAIN <= w_GATE_XOR_CHAIN;
        end
    end

//cmp_eq
    // initial $display("lut_width:%d\treg_width:%d\tl_lut:%d",CMP_LUT_WIDTH,CMP_CARRYCHAIN_WIDTH,CMP_LAST_LUT_WIDTH);
    reg     [CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH:0]  r_CMP_EQ_CHAIN = 0; // add one bit for the neq result
    wire    [CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH:0]  w_CMP_EQ_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_CMP_EQ_CHAIN <= 0;
        end else begin
            r_CMP_EQ_CHAIN <= w_CMP_EQ_CHAIN;
        end
    end

    math_combinational #(.WIDTH(WIDTH), .LATENCY(LATENCY) ) ALU_LOGIC
    (
        .clk(clk),
        .I1(I1),
        .I2(I2), 
        .I3(I3),
        .sum(sum), 
        .sum_carry_in(r_sum_chain), 
        .sum_carry_out(w_sum_chain),
        .sub(sub), 
        .sub_carry_in(r_sub_chain), 
        .sub_carry_out(w_sub_chain),
        .gate_and(gate_and), 
        .gate_and_carry_in(r_GATE_AND_CHAIN), 
        .gate_and_carry_out(w_GATE_AND_CHAIN),
        .gate_or(gate_or),  
        .gate_or_carry_in(r_GATE_OR_CHAIN),  
        .gate_or_carry_out(w_GATE_OR_CHAIN),
        .gate_xor(gate_xor), 
        .gate_xor_carry_in(r_GATE_XOR_CHAIN), 
        .gate_xor_carry_out(w_GATE_XOR_CHAIN),
        .cmp_eq(cmp_eq),   
        .cmp_eq_carry_in(r_CMP_EQ_CHAIN),   
        .cmp_eq_carry_out(w_CMP_EQ_CHAIN),
        .cmp_neq(cmp_neq)
    );    

endmodule

module math_combinational
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4
    )
    (   clk, I1, I2, I3,
        sum, sum_carry_in, sum_carry_out,
        sub, sub_carry_in, sub_carry_out,
        gate_and, gate_and_carry_in, gate_and_carry_out,
        gate_or,  gate_or_carry_in,  gate_or_carry_out,
        gate_xor, gate_xor_carry_in, gate_xor_carry_out,
        cmp_eq,   cmp_eq_carry_in,   cmp_eq_carry_out,
        cmp_neq
    );
        input   wire                clk;
        input   wire    [WIDTH-1:0] I1;
        input   wire    [WIDTH-1:0] I2;
        input   wire    [WIDTH-1:0] I3;

    //  sum         = I1 + I2
    //  sub         = I1 - I2
    //  gate_and    = &I1
    //  gate_or     = |I1
    //  gate_xor    = ^I1
    //  cmp_eq      = I1 == I3
    //  cmp_neq     = I1 != I3
    //ToDo:
    //  cmp_greater = I1 > I3
    //  cmp_lesser  = I1 < I3

    `ifndef FORMAL
        `include "./toolbox/recursion_iterators.h"
    `else
        `include "recursion_iterators.h"
    `endif
    // determine the chunk width. knowing that each chunk will take 1 tick, 'width' / 'latency' will provide
    // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    // BugFix, prevent divide by zero condition.
    localparam DENOMINATOR = (LATENCY==0) ? 1 : LATENCY;
    localparam ALU_WIDTH  = (WIDTH / DENOMINATOR * DENOMINATOR) == WIDTH 
            ? WIDTH / DENOMINATOR 
            : WIDTH / DENOMINATOR + 1;
    // find the minimum amount of chunks needed to contain the counter
    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1; 
    // find the size of the last chunk needed to contain the counter.
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH;
    // initial $display("WIDTH:%d\tLATENCY:%d\tALU_WIDTH:%d\tCHUNK_COUNT:%d\tLAST_CHUNK_SIZE:%d", WIDTH, LATENCY, ALU_WIDTH, CHUNK_COUNT, LAST_CHUNK_SIZE);
    // find values for gates
    localparam GATE_LUT_WIDTH   = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_CARRYCHAIN_WIDTH = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_LUT_WIDTH );// use the operator input width to find how many units are needed
    // initial $display("GATE_LUT_WIDTH:%d\tGATE_CARRYCHAIN_WIDTH:%d", GATE_LUT_WIDTH, GATE_CARRYCHAIN_WIDTH);

    // find values for cmp
    localparam CMP_LUT_WIDTH        = f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY > 1 ? LATENCY - 1 : 1); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_CARRYCHAIN_WIDTH     = f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed
    localparam CMP_LAST_LUT_WIDTH   = f_TailRecursionGetLastUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH); // find the width of the last unit.
    // initial $display("CMP_LUT_WIDTH:%d\tCMP_CARRYCHAIN_WIDTH:%d\tCMP_LAST_LUT_WIDTH:%d", CMP_LUT_WIDTH, CMP_CARRYCHAIN_WIDTH, CMP_LAST_LUT_WIDTH);


    genvar idx;
    genvar unit_index;
    genvar input_index;
//addition
    output  wire    [WIDTH-1:0]         sum;
    input   wire    [CHUNK_COUNT-1:0]   sum_carry_in;
    output  wire    [CHUNK_COUNT-1:0]   sum_carry_out;
    // assign w_sum_cout_chain[CHUNK_COUNT-1] = 1'b0;  // removes warning about bit being unset. will be optimized away
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : sum_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign { sum_carry_out[idx], sum[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, I1[idx*ALU_WIDTH+:ALU_WIDTH] } + { 1'b0, I2[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? 1'b0 : sum_carry_in[idx-1]);
        end else begin    // == LAST_CHUNK
            assign { sum_carry_out[idx], sum[WIDTH-1:WIDTH-LAST_CHUNK_SIZE]} = { 1'b0, I1[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + { 1'b0, I2[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + (idx == 0 ? 1'b0 : sum_carry_in[idx-1]);
        end
    end 

//subtraction
    output  wire    [WIDTH-1:0]         sub;
    input   wire    [CHUNK_COUNT-1:0]   sub_carry_in;
    output  wire    [CHUNK_COUNT-1:0]   sub_carry_out;
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : sub_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign { sub_carry_out[idx], sub[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, I1[idx*ALU_WIDTH+:ALU_WIDTH] } - { 1'b0, I2[idx*ALU_WIDTH+:ALU_WIDTH] } - (idx == 0 ? 1'b0 : sub_carry_in[idx-1]);
        end else begin    // == LAST_CHUNK
            assign { sub_carry_out[idx], sub[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } = { 1'b0, I1[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } - { 1'b0, I2[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } - (idx == 0 ? 1'b0 : sub_carry_in[idx-1]);
        end
    end 

//gate_and
    output  wire    gate_and;
    input   wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0] gate_and_carry_in;
    output  wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0] gate_and_carry_out;
    `define OPERATION &
    if( LATENCY == 0 )
        assign gate_and = gate_and_carry_out[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
    else
        assign gate_and = gate_and_carry_in[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
        
    // take sections of 'I1' then perform the operation on them.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_AND_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            assign gate_and_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH];// edit operation here
        end else begin    // == LAST_CHUNK
            assign gate_and_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_CARRYCHAIN_WIDTH; unit_index = unit_index + 1) begin : GATE_AND_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_AND_input_loop
                assign unit_inputs[input_index] = gate_and_carry_in[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        assign gate_and_carry_out[CHUNK_COUNT+unit_index] = `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//gate_or
    output  wire                                            gate_or;
    input   wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   gate_or_carry_in;
    output  wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   gate_or_carry_out;
    `define OPERATION |
    if( LATENCY == 0 )
        assign gate_or = gate_or_carry_out[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
    else
        assign gate_or = gate_or_carry_in[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
    // take sections of 'I1' then perform the operation on them.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_OR_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            assign gate_or_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH];// edit operation here
        end else begin    // == LAST_CHUNK
            assign gate_or_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_CARRYCHAIN_WIDTH; unit_index = unit_index + 1) begin : GATE_OR_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_OR_input_loop
            assign unit_inputs[input_index] = gate_or_carry_in[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        assign gate_or_carry_out[CHUNK_COUNT+unit_index] = `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//gate_xor
    output  wire                                            gate_xor;
    input   wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  gate_xor_carry_in;
    output  wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  gate_xor_carry_out;
    `define OPERATION ^
    if( LATENCY == 0 )
        assign gate_xor = gate_xor_carry_out[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
    else
        assign gate_xor = gate_xor_carry_in[CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1];
    // take sections of 'I1' then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : GATE_XOR_base_loop
        if( idx != (CHUNK_COUNT - 1) ) begin // !LAST_CHUNK
            assign gate_xor_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:ALU_WIDTH] ;// edit operation here
        end else begin    // == LAST_CHUNK
            assign gate_xor_carry_out[idx] = `OPERATION I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];// edit operation here
        end
    end
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < GATE_CARRYCHAIN_WIDTH; unit_index = unit_index + 1) begin : GATE_XOR_unit_loop
        // make the input wires for this unit   
        wire [f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index)-1:0] unit_inputs;
        // assign the inputs to their proper place
        for( input_index = f_NaryRecursionGetUnitWidth(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index) - 1; input_index != ~0; input_index = input_index-1 ) begin : GATE_XOR_input_loop
                assign unit_inputs[input_index] = gate_xor_carry_in[f_NaryRecursionGetUnitInputAddress(CHUNK_COUNT, GATE_LUT_WIDTH, unit_index, input_index)];
        end
        // perform the function and store the output
        assign gate_xor_carry_out[CHUNK_COUNT+unit_index] = `OPERATION unit_inputs;  // edit operation here
    end
    `undef OPERATION

//cmp_eq 
    output  wire                                            cmp_eq;
    input   wire    [CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH:0]    cmp_eq_carry_in;  // add extra bit for cmp_neq
    output  wire    [CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH:0]    cmp_eq_carry_out;
    output  wire                                            cmp_neq;
    if( LATENCY == 0 ) begin
        assign cmp_eq = cmp_eq_carry_out[CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH-1];
        assign cmp_neq = ~cmp_eq_carry_out[CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH-1]; // just invert the cmp_eq bit
    end else begin
        assign cmp_eq = cmp_eq_carry_in[CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH-1];
        assign cmp_neq = cmp_eq_carry_in[CHUNK_COUNT+CMP_CARRYCHAIN_WIDTH];    // use the faster unit comparator
    end
    // take sections of the I1 and I3 then perform the operation on them.
    // then store the result in a register for each section.
    for( idx = 0; idx <= (CHUNK_COUNT - 1); idx = idx + 1 ) begin : CMP_EQ_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign cmp_eq_carry_out[idx] = I1[idx*ALU_WIDTH+:ALU_WIDTH] == I3[idx*ALU_WIDTH+:ALU_WIDTH];
        end else begin    // == LAST_CHUNK
            assign cmp_eq_carry_out[idx] = I1[idx*ALU_WIDTH+:LAST_CHUNK_SIZE] == I3[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];
        end
    end
    // the last unit may be a different size than the others. account for this here
    function automatic integer f_input_size;
        input integer unit_index;
        begin
            if( unit_index != (CMP_CARRYCHAIN_WIDTH-1) ) begin    // ! last unit
                f_input_size = CMP_LUT_WIDTH-1;
            end else begin                                      // == last unit
                f_input_size = CMP_LAST_LUT_WIDTH-1;
            end
        end
    endfunction
    // loop through each unit and assign the in and outs
    for( unit_index = 0; unit_index < CMP_CARRYCHAIN_WIDTH; unit_index = unit_index + 1) begin
            // make the input wires for this unit   
            wire [f_input_size(unit_index):0] unit_inputs;
            // assign the inputs to their proper place
            for( input_index = f_input_size(unit_index); input_index != ~0; input_index = input_index-1 ) begin
                // initial $display("unit_index: %d input_index:%d func:%d", unit_index, input_index, f_TailRecursionGetUnitInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index));
                assign unit_inputs[input_index] = 
                    cmp_eq_carry_in[f_TailRecursionGetUnitInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index)];
            end
            // perform the function and store the output
            assign cmp_eq_carry_out[CHUNK_COUNT+unit_index] = &unit_inputs;
            // if this is the last unit, perform an inverted comparison to find cmd_neq
            if( unit_index == CMP_CARRYCHAIN_WIDTH - 1 )
                assign cmp_eq_carry_out[CHUNK_COUNT+unit_index+1] = ~&unit_inputs;
    end
endmodule
