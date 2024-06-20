////////////////////////////////////////////////////////////////////////////////
// Filename:	adder_pipelined.v
//
// Project:	adder_pipelined 
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
module adder_pipelined
    #(
        parameter WIDTH     = 4,
        parameter LATENCY   = 4
    )
    (
        input   wire                clk,
        input   wire                ce,
        input   wire    [WIDTH-1:0] d,
        input   wire    [WIDTH-1:0] i,
        output  wire    [WIDTH-1:0] q
    );
    // determine the chunk width. knowing that each chunk will take 1 tick, 'width' / 'latency' will provide
    // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    localparam ALU_WIDTH  = WIDTH / LATENCY * LATENCY == WIDTH ? WIDTH / LATENCY : WIDTH / LATENCY + 1; 
    // find the minimum amount of chunks needed to contain the counter
    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1; 
    // find the size of the last chunk needed to contain the counter.
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH; 
    genvar idx;
    generate
        wire [CHUNK_COUNT-1:0] w_cout_chain;
        assign w_cout_chain[CHUNK_COUNT-1] = 1'b0;  // removes warning about bit being unset. will be optimized away
        reg  [CHUNK_COUNT-1:0] r_cout_chain = 0;
        reg  [WIDTH-1:0]       r_addend = 0;

        for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin
            if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
                assign { w_cout_chain[idx], q[idx*ALU_WIDTH+:ALU_WIDTH] } = { 1'b0, d[idx*ALU_WIDTH+:ALU_WIDTH] } + { 1'b0, r_addend[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? 1'b0 : r_cout_chain[idx-1]);
            end else begin    // == LAST_CHUNK
                assign q[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] = d[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] + { 1'b0, r_addend[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] } + (idx == 0 ? 1'b0 : r_cout_chain[idx-1]);
            end
        end 
        always @( posedge clk ) begin
            if( ce ) begin
                r_addend <= i;
                r_cout_chain <= 0;
            end else begin
                r_addend <= 0;
                r_cout_chain <= w_cout_chain;
            end
        end
    endgenerate
endmodule
