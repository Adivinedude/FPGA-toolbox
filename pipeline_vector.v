////////////////////////////////////////////////////////////////////////////////
//
// Filename:	pipeline_vector.v
//
// Project:	pipeline vector logic
//
// Purpose:	a purely combinational sequential vector pipeline data structures.
//
// Creator:	Ronald Rainwater
// Data: 2024-8-14
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

////////////////////////////////////
// pipeline vector. diagram
// <MSB --> LSB>
//  step 1        |  step 2        |  step 3
// out_shift_left
// <A2> <A1> <A0> | <B2> <B1> <B0> | <C2> <C1> <C0>
// <XX> <XX>      | <A1> <A0>      | <B1> <B0>
// <XX>           | <XX>           | <A0>
// sel_left
// <XX> <XX> <A2> | <XX> <A1> <B2> | <A0> <B1> <C2>

// out_shift_right
// <A2> <A1> <A0> | <B2> <B1> <B0> | <C2> <C1> <C0>
//      <XX> <XX> |      <A2> <A1> |      <B2> <B1>
//           <XX> |           <XX> |           <A2>
// sel_right
// <XX> <XX> <A0> | <XX> <A1> <B0> | <A2> <B1> <C0>


`default_nettype none

module pipeline_vector #( 
    parameter WIDTH = 1,
    parameter SIZE  = 3,
    parameter PRINT = 0
    )( in, out_shift_left, out_shift_right, sel_left, sel_right, bit_reversal_inA, bit_reversal_inB, bit_reversal_outA, bit_reversal_outB );

    `include "recursion_iterators.vh"

    localparam VECTOR_SIZE = f_GetPipelineVectorSize( SIZE - 1, WIDTH );

    input   wire    [f_GetPipelineVectorSize(SIZE, WIDTH)-1:0]   in;
    output  wire    [VECTOR_SIZE-1:0]   out_shift_left;
    output  wire    [VECTOR_SIZE-1:0]   out_shift_right;
    output  wire    [SIZE*WIDTH -1:0]   sel_left;
    output  wire    [SIZE*WIDTH -1:0]   sel_right;
    input   wire    [SIZE*WIDTH -1:0]   bit_reversal_inA, bit_reversal_inB;
    output  wire    [SIZE*WIDTH -1:0]   bit_reversal_outA, bit_reversal_outB;
    // out_shift_left
    genvar idx;
    generate
        for( idx = 0; idx < SIZE-1; idx = idx + 1 )begin
            if(PRINT!=0&&idx==0)initial $display("pipeline_vector - WIDTH:%1d SIZE:%1d", WIDTH, SIZE);
            if(PRINT!=0)initial $display( "pipeline_vector - idx:%1d out_shift_left[%1d:%1d] = in[%1d:%1d]", 
                idx,
                f_GetPipelineDepthEndAddress(SIZE-1, WIDTH, idx),
                f_GetPipelineDepthStartAddress(SIZE-1, WIDTH, idx),
                f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx)-WIDTH,
                f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx)
            );
            assign out_shift_left[   f_GetPipelineDepthEndAddress(SIZE-1, WIDTH, idx)
                                    :f_GetPipelineDepthStartAddress(SIZE-1, WIDTH, idx) ]
                    = in[    f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx)-WIDTH
                            :f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx)];
        end
        // out_shift_right
        for( idx = 0; idx < SIZE-1; idx = idx + 1 )begin
            if(PRINT!=0)initial $display( "pipeline_vector - idx:%1d out_shift_right[%1d:%1d] = in[%1d:%1d]", 
                idx,
                f_GetPipelineDepthEndAddress(SIZE-1, WIDTH, idx),
                f_GetPipelineDepthStartAddress(SIZE-1, WIDTH, idx),
                f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx),
                f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx)+WIDTH
            );
            assign out_shift_right[  f_GetPipelineDepthEndAddress(SIZE-1, WIDTH, idx)
                                    :f_GetPipelineDepthStartAddress(SIZE-1, WIDTH, idx) ]
                    = in[    f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx)
                            :f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx)+WIDTH];
        end
        // sel_left
        for( idx = 0; idx < SIZE; idx = idx + 1 )begin
            if(PRINT!=0)initial $display( "pipeline_vector - idx:%1d sel_left[%1d+:%1d] = in[%1d+:%1d]", 
                idx,
                idx*WIDTH,
                WIDTH,
                f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx),
                WIDTH
            );
            assign sel_left[ idx*WIDTH+:WIDTH ] = in[f_GetPipelineDepthEndAddress(SIZE, WIDTH, idx) +: WIDTH];
        end
        // sel_right
        for( idx = 0; idx < SIZE; idx = idx + 1 )begin
            if(PRINT!=0)initial $display( "pipeline_vector - idx:%1d sel_right[%1d+:%1d] = in[%1d+:%1d]", 
                idx,
                idx*WIDTH,
                WIDTH,
                f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx),
                WIDTH
            );
            assign sel_right[ idx*WIDTH+:WIDTH ] = in[f_GetPipelineDepthStartAddress(SIZE, WIDTH, idx) +: WIDTH];
        end
        // bit_reversal
        for( idx = 0; idx < SIZE; idx = idx + 1 ) begin
            assign bit_reversal_outA[idx*WIDTH+:WIDTH] = bit_reversal_inA[(SIZE-idx-1)*WIDTH+:WIDTH];
            assign bit_reversal_outB[idx*WIDTH+:WIDTH] = bit_reversal_inB[(SIZE-idx-1)*WIDTH+:WIDTH];
        end
    endgenerate
endmodule
