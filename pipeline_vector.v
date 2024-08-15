////////////////////////////////////////////////////////////////////////////////
//
// Filename:	pipeline_vector.v
//
// Project:	pipeline vector logic
//
// Purpose:	a sequential vector pipeline data structures.
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
// <2> <1> <0>
//     <4> <3>
//         <5>
// 

`default_nettype none

module pipeline_vector #( 
    parameter WIDTH = 1,
    parameter SIZE  = 2
    )( clk, in, out_shift_left, out_shift_right, sel_left, sel_right );

    `include "recursion_iterators.vh"

    localparam VECTOR_SIZE = f_GetPipelineVectorSize( SIZE, WIDTH );

    input   wire                        clk;
    input   wire    [VECTOR_SIZE-1:0]   in;
    output  wire    [VECTOR_SIZE-1:0]   out_shift_left;
    output  wire    [VECTOR_SIZE-1:0]   out_shift_right;
    output  wire    [SIZE*WIDTH -1:0]   sel_left;
    output  wire    [SIZE*WIDTH -1:0]   sel_right;

endmodule