////////////////////////////////////////////////////////////////////////////////
//
// Filename:	dmux_pipeline.v
//
// Project:	dmux_pipeline
// Purpose:	A variable width demultiplexer for high speed designs.
//
// Creator:	Ronald Rainwater
// Data: 2024-7-19
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
// Demultiplexer with a fixed output latency.

module dmux_pipeline #(
    parameter WIDTH = 1,
    parameter OUTPUT_COUNT = 2,
    parameter LATENCY = 0,
    parameter PRINT = 0
)( clk, sel, in, out );
    localparam SELECT_SIZE = $clog2(OUTPUT_COUNT);

    input   wire                                clk;
    input   wire    [SELECT_SIZE-1:0]           sel;
    input   wire    [WIDTH-1:0]                 in;
    output  wire    [(WIDTH*OUTPUT_COUNT)-1:0]  out;
    
    `include "recursion_iterators.vh"

    localparam MUX_SIZE         = 'd1 << $clog2(f_NaryRecursionGetUnitWidthForLatency(OUTPUT_COUNT, LATENCY));
    localparam SEL_WIDTH        = $clog2(MUX_SIZE);
    localparam STRUCTURE_DEPTH  = f_NaryRecursionGetDepth(OUTPUT_COUNT, MUX_SIZE);
    
    localparam PIPELINE_R_SIZE = f_GetPipelineVectorSize(STRUCTURE_DEPTH-1, SEL_WIDTH);
    wire    [WIDTH-1:0]                         w_in;
    wire    [SELECT_SIZE-1:0]                   w_sel_buffer;
    reg     [PIPELINE_R_SIZE-1:0]               r_sel_pipe = 0;    // .sel() pipeline register
    wire    [PIPELINE_R_SIZE-1:0]               w_sel_pipe;
    wire    [SELECT_SIZE-1:0]                   w_sel, w_sel_reverseA, w_sel_reverseB;

    if(PRINT!=0)initial $display("dmux_pipeline - SELECT_SIZE:%1d MUX_SIZE:%1d SEL_WIDTH:%1d STRUCTURE_DEPTH:%1d PIPELINE_R_SIZE:%1d",
        SELECT_SIZE, MUX_SIZE, SEL_WIDTH, STRUCTURE_DEPTH, PIPELINE_R_SIZE );
    generate
        if( LATENCY <= STRUCTURE_DEPTH ) begin
            assign w_in = in;
            assign w_sel_buffer = sel;
        end else begin
            synchronizer #(.WIDTH(WIDTH+SELECT_SIZE), .DEPTH_INPUT( LATENCY - (STRUCTURE_DEPTH-1) ), .DEPTH_OUTPUT(0) )
                dmux_latency_correction( .clk_in(clk), .in({in, sel}), .clk_out(), .out({w_in, w_sel_buffer}) );
        end        
    endgenerate



    pipeline_vector #( .WIDTH(SEL_WIDTH), .SIZE(STRUCTURE_DEPTH), .PRINT(PRINT) )
        dmux_sel_pipeline(  .in({r_sel_pipe, w_sel_buffer}), 
                            .out_shift_left(w_sel_pipe), 
                            .sel_left(w_sel),
                            .bit_reversal_inA(w_sel), 
                            .bit_reversal_outA(w_sel_reverseA)//,
                            // .bit_reversal_inB(w_sel),
                            // .bit_reversal_outB(w_sel_reverseB) 
        );
    always @( posedge clk ) r_sel_pipe <= w_sel_pipe;

    dmux_lfmr #(.WIDTH(WIDTH), .OUTPUT_COUNT(OUTPUT_COUNT), .LATENCY(LATENCY), .TYPE(0), .PRINT(PRINT) )
        object_dmux_lfmr(.clk(clk), .sel(w_sel_reverseA), .in(w_in), .out(out) );
    
endmodule

module dmux_lfmr #(
    parameter WIDTH = 1,
    parameter OUTPUT_COUNT = 2,
    parameter LATENCY = 0,
    parameter TYPE = 0,
    parameter PRINT = 0
)( clk, sel, in, out );
    
    input   wire                                clk;
    input   wire    [$clog2(OUTPUT_COUNT)-1:0]  sel;
    input   wire    [WIDTH-1:0]                 in;
    output  wire    [(WIDTH*OUTPUT_COUNT)-1:0]  out;
    `include "recursion_iterators.vh"

    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(OUTPUT_COUNT, LATENCY);
            endcase
            if(PRINT!=0)$write("f_GetMuxSize: LATENCY:%0d\tOUTPUT_COUNT:%0d \f_NaryRecursionGetUnitWidthForLatency:%0d\t",LATENCY, OUTPUT_COUNT, f_GetMuxSize );
            f_GetMuxSize = 'd1 << $clog2(f_GetMuxSize);
            if(PRINT!=0)$display("f_GetMuxSize:%0d", f_GetMuxSize);
        end
    endfunction
    localparam MUX_SIZE = f_GetMuxSize(0);

    function automatic integer f_GetVectorSize;
        input unused;
        begin
            case(TYPE)
                1:          f_GetVectorSize = f_NaryRecursionGetVectorSizeOptimized( OUTPUT_COUNT, MUX_SIZE );
                default:    f_GetVectorSize = f_NaryRecursionGetVectorSize( OUTPUT_COUNT, MUX_SIZE );
            endcase
        end
    endfunction

    localparam STRUCTURE_SIZE = f_GetVectorSize(0);
    reg     [(((STRUCTURE_SIZE-1)+OUTPUT_COUNT)*WIDTH)-1:0] r_in_pipeline = 0;
    wire    [(((STRUCTURE_SIZE-1)+OUTPUT_COUNT)*WIDTH)-1:0] w_out_pipeline;

    dmux_combinational #(.WIDTH(WIDTH), .OUTPUT_COUNT(OUTPUT_COUNT), .LATENCY(LATENCY), .TYPE(TYPE), .PRINT(PRINT) )
        object_dmux_combinational(.clk(clk), .sel(sel), .in(in), .in_pipeline(r_in_pipeline), .out(out), .out_pipeline(w_out_pipeline) );
    
    if( STRUCTURE_SIZE != 1 )
        always @( posedge clk ) r_in_pipeline <= w_out_pipeline;

///////////////////////////////////////////////////////////////////////////////
// formal verification starts here

    `ifdef FORMAL
        `define ASSERT assert
        `ifdef FORMAL_DMUX_LFMR
            `define ASSUME assume
        `else
            `define ASSUME assert
        `endif

        // Testing values
        wire past_valid;
        reg unsigned [1:0] past_counter = 0;
        initial assume( past_counter == 0 );
        assign past_valid = past_counter > 0;
        always @( posedge clk ) 
            past_counter <= (past_valid) 
                                ? past_counter 
                                : past_counter + 1;

        reg unsigned [$clog2(LATENCY):0] valid_output_tracker = 0;
        reg valid_output = 0;
        always @( posedge clk ) begin
            if( past_valid ) begin
                valid_output_tracker = $changed(sel) || $changed(in) 
                                    ? 0 
                                    : valid_output
                                        ? valid_output_tracker
                                        : valid_output_tracker + 1;
                valid_output = valid_output_tracker >= LATENCY;
            end else begin
                valid_output = 0;
            end
        end
        // Assume inputs
/////////
// sel //
/////////
        always @(posedge clk) invalid_selection: `ASSUME( !past_valid || sel < OUTPUT_COUNT );

        // ensure the simulation is working properly
        `ifdef FORMAL_DMUX_LFMR
            // report an output !zero and a sel !zero.
            always @( posedge clk ) cover( valid_output && in == out[WIDTH*sel+:WIDTH] );
        `endif

        // Assert the outputs
        // check of the output is correct when the pipeline is finished propagating.
        reg [$clog2(OUTPUT_COUNT):0]    p_sel;
        reg [WIDTH-1:0]                 p_in;
        reg [(WIDTH*OUTPUT_COUNT)-1:0]  p_out;
        always @( posedge clk ) begin
            p_sel <= sel;
            p_in  <= in;
            p_out <= out;
        end
        always @(posedge clk) dmux_valid_output: assert( !valid_output || p_in == p_out[WIDTH*p_sel+:WIDTH] );
    `endif

endmodule

module dmux_combinational #(
    parameter WIDTH = 1,
    parameter OUTPUT_COUNT = 2,
    parameter LATENCY = 0, 
    parameter TYPE = 0,     // 0 - Fixed latency for all selections
                            // 1 - Optimized structure - possible variable latency for a given selection
                            // 2 - Prioritized structure - MSB selection will have smallest latency.
    parameter PRINT = 0
)( clk, sel, in, in_pipeline, out, out_pipeline );
    input   wire                                clk;
    input   wire    [$clog2(OUTPUT_COUNT)-1:0]    sel;
    input   wire    [WIDTH-1:0]                 in;
    output  wire    [(WIDTH*OUTPUT_COUNT)-1:0]  out;

    `include "recursion_iterators.vh"
    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(OUTPUT_COUNT, LATENCY);
            endcase
            if(PRINT!=0)$write("f_GetMuxSize: LATENCY:%0d\tOUTPUT_COUNT:%0d \f_NaryRecursionGetUnitWidthForLatency:%0d\t",LATENCY, OUTPUT_COUNT, f_GetMuxSize );
            f_GetMuxSize = 'd1 << $clog2(f_GetMuxSize);
            if(PRINT!=0)$display("f_GetMuxSize:%0d", f_GetMuxSize);
        end
    endfunction
    localparam MUX_SIZE = f_GetMuxSize(0);

    function automatic integer f_GetVectorSize;
        input unused;
        begin
            case(TYPE)
                1:          f_GetVectorSize = f_NaryRecursionGetVectorSizeOptimized( OUTPUT_COUNT, MUX_SIZE );
                default:    f_GetVectorSize = f_NaryRecursionGetVectorSize( OUTPUT_COUNT, MUX_SIZE );
            endcase
        end
    endfunction

    function automatic integer f_GetUnitWidth;
        input integer unit_index;
        case(TYPE)
            default:  f_GetUnitWidth = f_NaryRecursionGetUnitWidth(OUTPUT_COUNT, MUX_SIZE, unit_index);
        endcase
    endfunction

    function automatic integer f_GetInputAddress;
    input integer unit_index, output_index;
        case(TYPE)
            1:  f_GetInputAddress = f_NaryRecursionGetUnitInputAddressOptimized(OUTPUT_COUNT, MUX_SIZE, unit_index, output_index );
            default:  f_GetInputAddress = f_NaryRecursionGetUnitInputAddress(OUTPUT_COUNT, MUX_SIZE, unit_index, output_index );
        endcase
    endfunction

    function automatic integer f_GetUnitOutputAddress;
    input integer unit_index;
        case(TYPE)
            1: f_GetUnitOutputAddress = f_NaryRecursionGetUnitOutputAddressOptimized(OUTPUT_COUNT, MUX_SIZE, unit_index);
            default:  f_GetUnitOutputAddress = unit_index;
        endcase
    endfunction

    function automatic integer f_GetUnitDepth;
    input integer unit_index;
        case(TYPE)
            default:  f_GetUnitDepth = f_NaryRecursionGetUnitDepth(OUTPUT_COUNT, MUX_SIZE, unit_index);
        endcase
    endfunction

    function automatic integer f_GetStructureDepth;
    input integer unused;
        case(TYPE)
            default: f_GetStructureDepth = f_NaryRecursionGetDepth(OUTPUT_COUNT, MUX_SIZE);
        endcase
    endfunction

    // find the size of the vector needed
    localparam STRUCTURE_SIZE = f_GetVectorSize(0);
    localparam STRUCTURE_DEPTH = f_GetStructureDepth(0);
    localparam SEL_WIDTH = $clog2(MUX_SIZE);
    localparam TOTAL_UNIT_COUNT = f_NaryRecursionGetVectorSize(OUTPUT_COUNT,MUX_SIZE);
    
    input   wire    [(((STRUCTURE_SIZE-1)+OUTPUT_COUNT)*WIDTH)-1:0] in_pipeline;
    output  wire    [(((STRUCTURE_SIZE-1)+OUTPUT_COUNT)*WIDTH)-1:0] out_pipeline;
    assign out = out_pipeline[0+:OUTPUT_COUNT];
    generate
        initial if(PRINT!=0)$display(" OUTPUT_COUNT:%0d MUX_SIZE:%0d STRUCTURE_TYPE:%0d STRUCTURE_SIZE:%0d STRUCTURE_DEPTH:%0d SEL_WIDTH:%0d TOTAL_UNIT_COUNT:%0d", OUTPUT_COUNT, MUX_SIZE, TYPE, STRUCTURE_SIZE, STRUCTURE_DEPTH, SEL_WIDTH, TOTAL_UNIT_COUNT);
        genvar unit_index, output_index;
        // flip the in's and out's compared to a mux
        for( unit_index = 0; unit_index < TOTAL_UNIT_COUNT; unit_index = unit_index + 1) begin : dmux_unit_loop
            if( f_GetUnitOutputAddress(unit_index) != ~0 ) begin
                // build the unit's outputs.
                for( output_index = 0; output_index < MUX_SIZE; output_index = output_index + 1 ) begin : dmux_input_loop
                    if( output_index < f_GetUnitWidth(unit_index) ) begin
                        initial if(PRINT!=0)$write(" (OI:%0d OA:%0d IA:%0d)", output_index, f_GetInputAddress(unit_index, output_index), (f_GetUnitOutputAddress(unit_index)+OUTPUT_COUNT) );
                        assign out_pipeline[f_GetInputAddress(unit_index, output_index)*WIDTH+:WIDTH] 
                            = sel[f_GetUnitDepth(unit_index)*SEL_WIDTH+:SEL_WIDTH] == output_index
                                ? unit_index == TOTAL_UNIT_COUNT-1
                                    ? in
                                    : in_pipeline[(f_GetUnitOutputAddress(unit_index)+OUTPUT_COUNT)*WIDTH+:WIDTH]
                                : {WIDTH{1'b0}};
                    end
                    if( output_index == MUX_SIZE-1)
                        initial $display("");
                end
            end else begin
                initial if(PRINT!=0)$display("");
            end
            initial if(PRINT!=0)$write(" unit_index:%2d input_address:%2d unit_width:%2d unit_depth:%2d", unit_index, f_GetUnitOutputAddress(unit_index)!=~0?f_GetUnitOutputAddress(unit_index)+OUTPUT_COUNT:~0, f_GetUnitWidth(unit_index), f_GetUnitDepth(unit_index));
        end
    endgenerate
endmodule
