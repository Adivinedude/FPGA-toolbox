////////////////////////////////////////////////////////////////////////////////
//
// Filename:	mux_pipeline.v
//
// Project:	mux_pipeline
// Purpose:	A variable width multiplexer for high speed designs.
//
// Creator:	Ronald Rainwater
// Data: 2024-7-10
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

module mux_lfmr #(
    parameter WIDTH = 1,
    parameter INPUT_COUNT = 2,
    parameter LATENCY = 0,
    parameter TYPE = 0,
    parameter PRINT = 0
)( clk, sel, in, out );
    input   wire                                clk;
    input   wire    [$clog2(INPUT_COUNT):0]     sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;
    
    `include "recursion_iterators.vh"

    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(INPUT_COUNT, LATENCY);
            endcase
            if(PRINT!=0)$write("f_GetMuxSize: LATENCY:%0d\tINPUT_COUNT:%0d \f_NaryRecursionGetUnitWidthForLatency:%0d\t",LATENCY, INPUT_COUNT, f_GetMuxSize );
            f_GetMuxSize = 'd1 << $clog2(f_GetMuxSize);
            if(PRINT!=0)$display("f_GetMuxSize:%0d", f_GetMuxSize);
        end
    endfunction
    localparam MUX_SIZE = f_GetMuxSize(0);

    function automatic integer f_GetVectorSize;
        input unused;
        begin
            case(TYPE)
                1:          f_GetVectorSize = f_NaryRecursionGetVectorSizeOptimized( INPUT_COUNT, MUX_SIZE );
                default:    f_GetVectorSize = f_NaryRecursionGetVectorSize( INPUT_COUNT, MUX_SIZE );
            endcase
        end
    endfunction

    localparam STRUCTURE_SIZE = f_GetVectorSize(0);
    reg     [(STRUCTURE_SIZE*WIDTH)-1:0]    r_in_pipeline;
    wire    [(STRUCTURE_SIZE*WIDTH)-1:0]    w_out_pipeline;

    mux_combinational #(.WIDTH(WIDTH), .INPUT_COUNT(INPUT_COUNT), .LATENCY(LATENCY), .TYPE(TYPE), .PRINT(PRINT) )
        mux_object(.clk(clk), .sel(sel), .in(in), .in_pipeline(r_in_pipeline), .out(out), .out_pipeline(w_out_pipeline) );
    
    always @( posedge clk ) r_in_pipeline <= w_out_pipeline;

    `ifdef FORMAL
        `define ASSERT assert
        `ifdef FORMAL_MUX_LFMR
            `define ASSUME assume
        `else
            `define ASSUME assert
        `endif

        // Testing values
        wire past_valid;
        integer past_counter = 0;
        assign past_valid = past_counter >= LATENCY;
        always @( posedge clk ) 
            past_counter <= (past_valid) 
                                ? past_counter 
                                : past_counter + 1;

        integer ready_tracker = 0;
        wire ready = ready_tracker >= LATENCY+1;
        always @( posedge clk ) begin
            if( past_valid ) begin
                ready_tracker <= $changed(sel) || $changed(in) 
                                    ? 0 
                                    : ready
                                        ? ready_tracker
                                        : ready_tracker + 1;
            end
        end

        reg [$clog2(INPUT_COUNT)-1:0]   p_sel;
        reg [(WIDTH*INPUT_COUNT)-1:0]   p_in;
        always @(posedge clk) begin
            if( past_valid ) begin
                p_sel <= sel;
                p_in  <= in;
            end
        end

        // Assume inputs
        // keep 'sel' in a valid range
        always @(posedge clk) `ASSUME( sel < INPUT_COUNT );

        // only change 'sel' when pipeline if finished and output is valid
        always @(posedge clk) `ASSUME( !past_valid || ready || $stable(sel) );

        // only change 'in' when pipeline if finished and output is valid
        always @(posedge clk) `ASSUME( !past_valid || ready || $stable(in) );

        // ensure the simulation is working properly
        `ifdef FORMAL_MUX_LFMR
            // report an output !zero and a sel !zero.
            always @( posedge clk ) cover( ready && p_in[WIDTH*p_sel+:WIDTH] == $past(out) && p_sel != 0 && $past(out) != 0);
        `else
            always @( posedge clk ) cover( ready && in[WIDTH*sel+:WIDTH] == out && sel != 0);
        `endif

        // Assert the outputs
        // check of the output is correct when the pipeline is finished propagating.
        always @(posedge clk) begin
            if( past_valid ) begin
                if( ready )
                    assert( p_in[WIDTH*p_sel+:WIDTH] == $past(out) );
            end
        end
    `endif
endmodule

module mux_combinational #(
    parameter WIDTH = 1,
    parameter INPUT_COUNT = 2,
    parameter LATENCY = 0, 
    parameter TYPE = 0,     // 0 - Fixed latency for all selections
                            // 1 - Optimized structure - possible variable latency for a given selection
                            // 2 - Prioritized structure - MSB selection will have smallest latency.
    parameter PRINT = 0
)( clk, sel, in, in_pipeline, out, out_pipeline );
    input   wire                                clk;
    input   wire    [$clog2(INPUT_COUNT):0]     sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;

    `include "recursion_iterators.vh"
    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(INPUT_COUNT, LATENCY);
            endcase
            f_GetMuxSize = 'd1 << $clog2(f_GetMuxSize);
        end
    endfunction
    localparam MUX_SIZE = f_GetMuxSize(0);

    function automatic integer f_GetVectorSize;
        input unused;
        begin
            case(TYPE)
                1:          f_GetVectorSize = f_NaryRecursionGetVectorSizeOptimized( INPUT_COUNT, MUX_SIZE );
                default:    f_GetVectorSize = f_NaryRecursionGetVectorSize( INPUT_COUNT, MUX_SIZE );
            endcase
        end
    endfunction

    function automatic integer f_GetUnitWidth;
        input integer unit_index;
        case(TYPE)
            default:  f_GetUnitWidth = f_NaryRecursionGetUnitWidth(INPUT_COUNT, MUX_SIZE, unit_index);
        endcase
    endfunction

    function automatic integer f_GetInputAddress;
    input integer unit_index, input_index;
        case(TYPE)
            1:  f_GetInputAddress = f_NaryRecursionGetUnitInputAddressOptimized(INPUT_COUNT, MUX_SIZE, unit_index, input_index );
            default:  f_GetInputAddress = f_NaryRecursionGetUnitInputAddress(INPUT_COUNT, MUX_SIZE, unit_index, input_index );
        endcase
    endfunction

    function automatic integer f_GetUnitOutputAddress;
    input integer unit_index;
        case(TYPE)
            1: f_GetUnitOutputAddress = f_NaryRecursionGetUnitOutputAddressOptimized(INPUT_COUNT, MUX_SIZE, unit_index);
            default:  f_GetUnitOutputAddress = unit_index;
        endcase
    endfunction

    function automatic integer f_GetUnitDepth;
    input integer unit_index;
        case(TYPE)
            default:  f_GetUnitDepth = f_NaryRecursionGetUnitDepth(INPUT_COUNT, MUX_SIZE, unit_index);
        endcase
    endfunction

    function automatic integer f_GetStructureDepth;
    input integer unused;
        case(TYPE)
            default: f_GetStructureDepth = f_NaryRecursionGetDepth(INPUT_COUNT, MUX_SIZE);
        endcase
    endfunction

    // find the size of the vector needed
    localparam STRUCTURE_SIZE = f_GetVectorSize(0);
    localparam STRUCTURE_DEPTH = f_GetStructureDepth(0);
    localparam SEL_WIDTH = $clog2(MUX_SIZE);
    localparam TOTAL_UNIT_COUNT = f_NaryRecursionGetVectorSize(INPUT_COUNT,MUX_SIZE);
    
    input   wire    [(STRUCTURE_SIZE*WIDTH)-1:0]        in_pipeline;
    output  wire    [(STRUCTURE_SIZE*WIDTH)-1:0]        out_pipeline;
    wire    [((INPUT_COUNT+STRUCTURE_SIZE-1)*WIDTH)-1:0]  w_input_chain;
    assign w_input_chain = {in_pipeline,in};
    generate
        initial if(PRINT!=0)$display("INPUT_COUNT:%0d MUX_SIZE:%0d STRUCTURE_TYPE:%0d STRUCTURE_SIZE:%0d STRUCTURE_DEPTH:%0d SEL_WIDTH:%0d", INPUT_COUNT, MUX_SIZE, TYPE, STRUCTURE_SIZE, STRUCTURE_DEPTH, SEL_WIDTH);
        genvar unit_index, input_index;
        for( unit_index = 0; unit_index < TOTAL_UNIT_COUNT; unit_index = unit_index + 1) begin : mux_unit_loop
            if( f_GetUnitOutputAddress(unit_index) != ~0 ) begin
                // build the unit's inputs.
                wire [MUX_SIZE*WIDTH-1:0] unit_inputs;
                for( input_index = 0; input_index < MUX_SIZE; input_index = input_index + 1 ) begin : mux_input_loop
                    if( input_index < f_GetUnitWidth(unit_index) ) begin
                        initial if(PRINT!=0)$write(" (II:%2d A:%2d)", input_index, f_GetInputAddress(unit_index, input_index) );
                        assign unit_inputs[WIDTH*input_index+:WIDTH] = w_input_chain[f_GetInputAddress(unit_index, input_index)*WIDTH+:WIDTH];
                    end else 
                        assign unit_inputs[WIDTH*input_index+:WIDTH] = {WIDTH{1'b0}};
                end
                // select the units output.
                if( f_GetUnitWidth(unit_index) != 1 ) begin
                    initial if(PRINT!=0)$display(" sel - SEL[%0d+:%0d]", f_GetUnitDepth(unit_index)*SEL_WIDTH, SEL_WIDTH );
                    assign out_pipeline[(f_GetUnitOutputAddress(unit_index))*WIDTH+:WIDTH] = unit_inputs[sel[f_GetUnitDepth(unit_index)*SEL_WIDTH+:SEL_WIDTH]*WIDTH+:WIDTH];
                end else begin
                    initial if(PRINT!=0)$display(" set");
                    assign out_pipeline[(f_GetUnitOutputAddress(unit_index))*WIDTH+:WIDTH] = unit_inputs[0+:WIDTH];
                end
                if( unit_index == f_NaryRecursionGetVectorSize(INPUT_COUNT,MUX_SIZE)-1 ) begin
                    initial if(PRINT!=0)$display("OUT = UI:%0d", unit_index);
                    // always @(posedge clk) $display("OUT:%0d UI:%0d SEL:%0d", out, unit_index, sel);
                    assign out = unit_inputs[ sel[f_GetUnitDepth(unit_index)*SEL_WIDTH+:SEL_WIDTH]*WIDTH +:WIDTH ];
                end
            end else begin
                initial if(PRINT!=0)$display("");
            end
            initial if(PRINT!=0)$write(" unit_index:%2d output_index:%2d unit_width:%2d unit_depth:%2d", unit_index, f_GetUnitOutputAddress(unit_index)!=~0?f_GetUnitOutputAddress(unit_index)+INPUT_COUNT:~0, f_GetUnitWidth(unit_index), f_GetUnitDepth(unit_index));
        end
    endgenerate
endmodule
