////////////////////////////////////////////////////////////////////////////////
// Filename:	math_pipeline.v
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

///////////////////////////////////////////////////////////////////////////////
// Content:
//  math_combinational   - All the combinational logic required to generate a 
//                          variable with and latency ALU pipeline
//  math_lfmr            - A pipelined ALU which backfeeds into a single vector
//                          object. Only the ALU's are pipelined, not the 
//                          results, .I2() or .I3() ports
//  mux_pipeline        - A fully pipelined ALU which produces high FMAX with
//                          full throughput. here the results, .I2(), and .I3()
//                          port are pipelined

module math_pipeline
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4,
        parameter PRINT     = 1
    )
    (
        input   wire                clk,
        input   wire                rst,
        input   wire                ce,
        input   wire    [WIDTH-1:0] I1,
        input   wire    [WIDTH-1:0] I2,
        input   wire    [WIDTH-1:0] I3,
        output  wire    [WIDTH-1:0] sum,
        output  wire                cmp_sum_eq,
        output  wire                cmp_sum_neq,
        output  wire    [WIDTH-1:0] sub,
        output  wire                gate_and,
        output  wire                gate_or,
        output  wire                gate_xor,
        output  wire                cmp_eq,
        output  wire                cmp_neq
    );
    `include "recursion_iterators.vh"
    // ----- directly copied from math_lfmr
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
    initial $display("CHUNK_COUNT: %1d LATENCY: %1d", CHUNK_COUNT, LATENCY);
    localparam GATE_LUT_WIDTH        = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_CARRYCHAIN_WIDTH = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_LUT_WIDTH );// use the operator input width to find how many units are needed
    // find values for cmp
    localparam CMP_LUT_WIDTH        = f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY > 1 ? LATENCY : 1); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_CARRYCHAIN_WIDTH = f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed
    // ----- end of copy

    // Notes: input pipelining in required for the following operations
    // Arithmetic - sum, sub - each chunk takes a turn in the pipeline, from LSB to MSB. 
    //      this requires the input be ordered the same for 100% throughput
    // total input sampling is performed for all gate_* and cmp_* operations.
    //      The initial operation is performed when the data is sampled. 
    //      being a reducing gate operand, no input structure is required
    // I don't like the way the cmp_* operators are implemented. 
    //      They work independently from the arithmetic operation, much like gate_* and do not require a piped_vector input.
    // I would like the ability to generate a magnitude comparator with the result of a sum or sub.

    // Pipeline inputs and outputs.
    // the inputs will be processed 1 chunk at a time, resulting in an output of 1 chunk for each clock period.
    // by using a pipeline_vector for an input, the output requires one too.
    // gate_* and cmp_*do not require any pipeline_vector
    localparam I_PIPE_SIZE = f_GetPipelineVectorSize( CHUNK_COUNT-1, ALU_WIDTH);
    reg     [I_PIPE_SIZE-1:0]   r_I1_pipe, r_I2_pipe, r_I3_pipe, r_sum_pipe, r_sub_pipe;
    wire    [I_PIPE_SIZE-1:0]   w_I1_pipe, w_I2_pipe, w_I3_pipe, w_sum_pipe, w_sub_pipe;
    wire    [WIDTH-1:0]         w_I1, w_I2, w_I3, w_sum, w_sub;
    wire                        w_gate_and, w_gate_or, w_gate_xor, w_cmp_eq, w_cmp_neq, w_cmp_sum_eq, w_cmp_sum_neq;

// Input pipelined vectors
    pipeline_vector #( .SIZE( CHUNK_COUNT ), .WIDTH( ALU_WIDTH ), .PRINT( PRINT ) )
        I1_pipe( .in({r_I1_pipe, I1}), .out_shift_right(w_I1_pipe), .sel_right(w_I1) );

    pipeline_vector #( .SIZE( CHUNK_COUNT ), .WIDTH( ALU_WIDTH ), .PRINT( 0 ) )
        I2_pipe( .in({r_I2_pipe, I2}), .out_shift_right(w_I2_pipe), .sel_right(w_I2) );

    pipeline_vector #( .SIZE( CHUNK_COUNT ), .WIDTH( ALU_WIDTH ), .PRINT( 0 ) )
        I3_pipe( .in({r_I3_pipe, I3}), .out_shift_right(w_I3_pipe), .sel_right(w_I3) );

// Output pipelined vectors
    pipeline_vector #( .SIZE( CHUNK_COUNT ), .WIDTH( ALU_WIDTH ), .PRINT( 0 ) )
        SUM_pipe( .in({r_sum_pipe, w_sum}), .out_shift_right(w_sum_pipe), .sel_right(sum) );

    pipeline_vector #( .SIZE( CHUNK_COUNT ), .WIDTH( ALU_WIDTH ), .PRINT( 0 ) )
        SUB_pipe( .in({r_sub_pipe, w_sub}), .out_shift_right(w_sub_pipe), .sel_right(sub) );

    always @( posedge clk ) begin
        if( rst ) begin
            r_I1_pipe  <= 0;
            r_I2_pipe  <= 0;
            r_I3_pipe  <= 0;
            r_sum_pipe <= 0;
            r_sub_pipe <= 0;
        end else if( ce ) begin
            r_I1_pipe  <= w_I1_pipe;
            r_I2_pipe  <= w_I2_pipe;
            r_I3_pipe  <= w_I3_pipe;
            r_sum_pipe <= w_sum_pipe;
            r_sub_pipe <= w_sub_pipe;
        end
    end
    math_lfmr #(.WIDTH( WIDTH ), .LATENCY( LATENCY ), .PRINT( PRINT ) )
        ALU_CARRY_CHAIN_PIPE (
            .clk(           clk ),
            .rst(           rst ),
            .ce(            ce ),
            .I1(            w_I1 ),
            .I2(            w_I2 ),
            .I3(            I3 ),
            .sum(           w_sum ),
            .cmp_sum_eq(    w_cmp_sum_eq),
            .cmp_sum_neq(   w_cmp_sum_neq),
            .sub(           w_sub ),
            .gate_and(      w_gate_and ),
            .gate_or(       w_gate_or ),
            .gate_xor(      w_gate_xor ),
            .cmp_eq(        w_cmp_eq ),
            .cmp_neq(       w_cmp_neq )
        );
    // sync up the output of the gate_* and cmp_* functions with the arithmetic output
    // localparam GATE_DELAY = (LATENCY - f_NaryRecursionGetDepth(WIDTH, GATE_LUT_WIDTH)) * 3;
    // localparam CMP_DELAY  = (LATENCY - f_NaryRecursionGetDepth(WIDTH, CMP_LUT_WIDTH )) * 2;
    localparam GATE_DELAY = 5;
    localparam CMP_DELAY = 5;
    initial $display( "WIDTH: %1d GATE_LUT_WIDTH: %1d CMP_LUT_WIDTH %1d", WIDTH, GATE_LUT_WIDTH, CMP_LUT_WIDTH);
    reg     [GATE_DELAY:0]   r_gate_delay = 0;
    reg     [CMP_DELAY :0]   r_cmp_delay  = 0;
    always @( posedge clk ) begin
        if( rst ) begin
            r_gate_delay <= 0;
            r_cmp_delay  <= 0;
        end else if( ce ) begin
            r_gate_delay <= { r_gate_delay[GATE_DELAY-3:0], {w_gate_and, w_gate_or, w_gate_xor} };
            r_cmp_delay  <= { r_cmp_delay[ CMP_DELAY-2 :0], {w_cmp_eq, w_cmp_neq} };
        end
    end
    assign gate_and = r_gate_delay[GATE_DELAY];
    assign gate_or  = r_gate_delay[GATE_DELAY-1];
    assign gate_xor = r_gate_delay[GATE_DELAY-2];
    assign cmp_eq   = r_cmp_delay[CMP_DELAY];
    assign cmp_neq  = r_cmp_delay[CMP_DELAY-1];
    assign cmp_sum_eq = w_cmp_sum_eq;
    assign cmp_sum_neq = w_cmp_sum_neq;
endmodule

module math_lfmr // linear feedback math register, 1 input, get answer LATENCY clocks later.
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4,
        parameter PRINT     = 0
    )
    (
        input   wire                clk,
        input   wire                rst,
        input   wire                ce,
        input   wire    [WIDTH-1:0] I1,
        input   wire    [WIDTH-1:0] I2,
        input   wire    [WIDTH-1:0] I3,
        output  wire    [WIDTH-1:0] sum,
        output  wire                cmp_sum_eq,
        output  wire                cmp_sum_neq,
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

    `include "recursion_iterators.vh"
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
    reg  [CHUNK_COUNT-1:0]  r_sum_chain = 0, r_sum_eq_chain = 0;
    wire [CHUNK_COUNT-1:0]  w_sum_chain, w_sum_eq_chain;
    always @( posedge clk ) begin
        if( rst ) begin
            r_sum_chain <= 0;
            r_sum_eq_chain <= 0;
        end else if( ce ) begin
            r_sum_chain <= w_sum_chain;
            r_sum_eq_chain <= w_sum_eq_chain;
        end
    end

//subtraction
    reg  [CHUNK_COUNT-1:0] r_sub_chain = 0;
    wire [CHUNK_COUNT-1:0] w_sub_chain;
    always @( posedge clk ) begin
        if( rst ) begin
            r_sub_chain <= 0;
        end else if( ce ) begin
            r_sub_chain <= w_sub_chain;
        end
    end

//gate_and
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  r_GATE_AND_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  w_GATE_AND_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_AND_CHAIN <= 0;
        end else if( ce ) begin
            r_GATE_AND_CHAIN <= w_GATE_AND_CHAIN;
        end
    end

//gate_or
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   r_GATE_OR_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]   w_GATE_OR_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_OR_CHAIN <= 0;
        end else if( ce ) begin
            r_GATE_OR_CHAIN <= w_GATE_OR_CHAIN;
        end
    end

//gate_xor
    reg     [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  r_GATE_XOR_CHAIN = 0;
    wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0]  w_GATE_XOR_CHAIN;
    always @( posedge clk ) begin
        if( rst ) begin
            r_GATE_XOR_CHAIN <= 0;
        end else if( ce ) begin
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
        end else if( ce ) begin
            r_CMP_EQ_CHAIN <= w_CMP_EQ_CHAIN;
        end
    end

    math_combinational #(.WIDTH(WIDTH), .LATENCY(LATENCY), .PRINT(PRINT) ) ALU_LOGIC
    (
        .clk(clk),
        .I1(I1),
        .I2(I2), 
        .I3(I3),
        .sum(sum), 
        .sum_carry_in(r_sum_chain), 
        .sum_carry_out(w_sum_chain),
        .cmp_sum_eq(cmp_sum_eq),
        .cmp_sum_neq(cmp_sum_neq),
        .sum_eq_carry_in(r_sum_eq_chain),
        .sum_eq_carry_out(w_sum_eq_chain),
        .sub(sub), 
        .sub_carry_in(r_sub_chain), 
        .sub_carry_out(w_sub_chain),
        //.sub_eq_carry_in(r_sub_eq_chain),
        //.sub_eq_carry_out(w_sub_eq_chain),
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
        parameter LATENCY   = 4,
        parameter PRINT     = 0
    )
    (   clk, I1, I2, I3,
        sum, sum_carry_in, sum_carry_out, cmp_sum_eq, cmp_sum_neq, sum_eq_carry_in, sum_eq_carry_out,
        sub, sub_carry_in, sub_carry_out, //cmp_sub_eq, cmp_sub_neq, sub_eq_carry_in, sub_eq_carry_out,
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

    `include "recursion_iterators.vh"
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
    localparam GATE_LUT_WIDTH   = f_NaryRecursionGetUnitWidthForLatency( CHUNK_COUNT, LATENCY );// use the maximum 'latency' to find the operator unit input width
    localparam GATE_CARRYCHAIN_WIDTH = f_NaryRecursionGetVectorSize( CHUNK_COUNT, GATE_LUT_WIDTH );// use the operator input width to find how many units are needed

    // find values for cmp
    localparam CMP_LUT_WIDTH        = f_TailRecursionGetUnitWidthForLatency(CHUNK_COUNT, LATENCY > 1 ? LATENCY - 1 : 1); // use the maximum 'latency' to find the comparators unit width
    localparam CMP_CARRYCHAIN_WIDTH     = f_TailRecursionGetVectorSize(CHUNK_COUNT, CMP_LUT_WIDTH); // use the comparators width to find how many units are needed
    localparam CMP_LAST_LUT_WIDTH   = f_TailRecursionGetLastUnitWidth(CHUNK_COUNT, CMP_LUT_WIDTH); // find the width of the last unit.

    if(PRINT!=0) begin 
        initial 
        $display("math_combinational - WIDTH:%1d LATENCY:%1d DENOMINATOR:%1d ALU_WIDTH:%1d CHUNK_COUNT:%1d LAST_CHUNK_SIZE:%1d GATE_LUT_WIDTH:%1d GATE_CARRYCHAIN_WIDTH:%1d CMP_LUT_WIDTH:%1d CMP_CARRYCHAIN_WIDTH:%1d CMP_LAST_LUT_WIDTH:%1d", 
        WIDTH, LATENCY, DENOMINATOR, ALU_WIDTH, CHUNK_COUNT, LAST_CHUNK_SIZE, GATE_LUT_WIDTH, GATE_CARRYCHAIN_WIDTH, CMP_LUT_WIDTH, CMP_CARRYCHAIN_WIDTH, CMP_LAST_LUT_WIDTH);
    end

    genvar idx;
    genvar unit_index;
    genvar input_index;
//addition
    output  wire    [WIDTH-1:0]         sum;
    output  wire                        cmp_sum_eq, cmp_sum_neq;
    input   wire    [CHUNK_COUNT-1:0]   sum_carry_in, sum_eq_carry_in;
    output  wire    [CHUNK_COUNT-1:0]   sum_carry_out, sum_eq_carry_out;
    // assign w_sum_cout_chain[CHUNK_COUNT-1] = 1'b0;  // removes warning about bit being unset. will be optimized away
    for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin : sum_base_loop
        if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
            assign { sum_carry_out[idx], sum[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, I1[idx*ALU_WIDTH+:ALU_WIDTH] } + { 1'b0, I2[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? 1'b0 : sum_carry_in[idx-1]);
            assign sum_eq_carry_out[idx] = &{ sum[idx*ALU_WIDTH+:ALU_WIDTH] == I3[idx*ALU_WIDTH+:ALU_WIDTH], (idx == 0) ? 1'b1 : sum_carry_in[idx-1] } ;
        end else begin    // == LAST_CHUNK
            assign { sum_carry_out[idx], sum[WIDTH-1:WIDTH-LAST_CHUNK_SIZE]} = { 1'b0, I1[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + { 1'b0, I2[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + (idx == 0 ? 1'b0 : sum_carry_in[idx-1]);
            assign cmp_sum_eq = &{ sum[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] == I3[WIDTH-1:WIDTH-LAST_CHUNK_SIZE], (idx == 0) ? 1'b1 : sum_eq_carry_in[idx-1] };
            assign cmp_sum_neq = |{sum[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] != I3[WIDTH-1:WIDTH-LAST_CHUNK_SIZE], (idx == 0) ? 1'b0 : ~sum_eq_carry_in[idx-1] };
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
    input   wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0] gate_xor_carry_in;
    output  wire    [CHUNK_COUNT+GATE_CARRYCHAIN_WIDTH-1:0] gate_xor_carry_out;
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
    for( unit_index = 0; unit_index < CMP_CARRYCHAIN_WIDTH; unit_index = unit_index + 1) begin : CMP_EQ_unit_loop
            // make the input wires for this unit   
            wire [f_input_size(unit_index):0] unit_inputs;
            // assign the inputs to their proper place
            for( input_index = f_input_size(unit_index); input_index != ~0; input_index = input_index-1 ) begin : CMP_EQ_input_loop
                if(PRINT!=0)begin initial $display("cmp_eq - unit_index: %1d input_index:%1d func:%1d", unit_index, input_index, f_TailRecursionGetUnitInputAddress(CHUNK_COUNT, CMP_LUT_WIDTH, unit_index, input_index));end
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
