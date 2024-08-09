///////////////////////////////////////////////////////////////////////////////
//
// Filename:	mux_pipeline.v
//
// Project:	mux_pipeline
// Purpose:	A variable width multiplexer for high speed designs.
//
// Creator:	Ronald Rainwater
// Data: 2024-7-10
///////////////////////////////////////////////////////////////////////////////
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
///////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////
// Content:
//  mux_combinational   - All the combinational logic required to generate a 
//                          variable with and latency mux pipeline
//  mux_lfmr            - A pipelined mux which backfeeds into a single vector
//                          object. Providing high FMAX, with low throughput
//  mux_pipeline        - A fully pipelined mux which produces high FMAX with
//                          full throughput
`default_nettype none

module mux_pipeline #(
    parameter WIDTH = 1,
    parameter INPUT_COUNT = 3,
    parameter LATENCY = 1,
    parameter PRINT = 0
)( clk, sel, in, out );
    localparam SELECT_SIZE = $clog2(INPUT_COUNT);

    input   wire                                clk;
    input   wire    [SELECT_SIZE-1:0]           sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;
    
    `include "recursion_iterators.vh"

    localparam MUX_SIZE         = 'd1 << $clog2(f_NaryRecursionGetUnitWidthForLatency(INPUT_COUNT, LATENCY));
    localparam SEL_WIDTH        = $clog2(MUX_SIZE);
    localparam STRUCTURE_SIZE   = f_NaryRecursionGetVectorSize( INPUT_COUNT, MUX_SIZE );
    localparam STRUCTURE_DEPTH  = f_NaryRecursionGetDepth(INPUT_COUNT, MUX_SIZE);
    
    // pipeline the 'sel' input
    function automatic integer f_select_register_size;
        input integer structure_depth;
        begin : named_block
        integer total_size;
            total_size              = $clog2(INPUT_COUNT);
            f_select_register_size  = 0;
            for( structure_depth = structure_depth; structure_depth > 0; structure_depth = structure_depth - 1) begin
                total_size = total_size - SEL_WIDTH;
                f_select_register_size = f_select_register_size + total_size;
            end
        end
    endfunction

    localparam PIPELINE_R_SIZE = f_select_register_size(STRUCTURE_DEPTH);

    reg     [PIPELINE_R_SIZE-1:0]               r_sel = 0;    // .sel() pipeline register
    wire    [SELECT_SIZE-1:0]                   w_sel;        // wires to pass to combinational .sel()
    wire    [SELECT_SIZE+PIPELINE_R_SIZE-1:0]   w_sel_in_pipe = { r_sel, sel };
    if(PRINT!=0)initial $display("mux_pipeline - SELECT_SIZE:%1d MUX_SIZE:%1d SEL_WIDTH:%1d STRUCTURE_SIZE:%1d STRUCTURE_DEPTH:%1d PIPELINE_R_SIZE:%1d",
        SELECT_SIZE, MUX_SIZE, SEL_WIDTH, STRUCTURE_SIZE, STRUCTURE_DEPTH, PIPELINE_R_SIZE );
    generate
        genvar idx;
            // perform w_sel assignment
            for( idx = 0; idx < STRUCTURE_DEPTH; idx = idx + 1 )begin
                if(PRINT!=0)initial $display( "mux_pipeline - idx:%1d w_sel[%1d+:%1d] = w_sel_in_pipe[%1d+:%1d]", 
                    idx,
                    idx*SEL_WIDTH, 
                        SEL_WIDTH,
                    (idx==0)?0:f_select_register_size(idx-1)+SELECT_SIZE, 
                        SEL_WIDTH 
                );
                assign w_sel[idx*SEL_WIDTH+:SEL_WIDTH] 
                    = w_sel_in_pipe[
                        (idx==0)?0:f_select_register_size(idx-1)+SELECT_SIZE
                        +:SEL_WIDTH ];                  
            end
    //////////// { r_sel, sel }    { r_sel }
    //    sel // 0- 3 2 1 0     // 
    //  r_sel // 1- 6 5 4       // 2 1 0
              // 2- 8 7         // 4 3
              // 3- 9           // 5
    //  w_sel //    9 7 4 0     // 5 3 0 x
            for( idx = 0; idx < STRUCTURE_DEPTH-1; idx = idx + 1 )begin
                if(PRINT!=0)initial $display( "mux_pipeline - idx:%1d r_sel[%1d+:%1d] <= w_sel_in_pipe[%1d+:%1d]"/**/ ,
                    idx,
                    f_select_register_size(idx), 
                        f_select_register_size(idx+1)-f_select_register_size(idx),
                    (idx==0)?SEL_WIDTH:f_select_register_size(idx-1)+SELECT_SIZE+1,
                        f_select_register_size(idx+1)-f_select_register_size(idx)
                );
                always @( posedge clk ) 
                    r_sel[ f_select_register_size(idx) 
                        +: f_select_register_size(idx+1)-f_select_register_size(idx) ]
                    <= w_sel_in_pipe[ (idx==0)?SEL_WIDTH:f_select_register_size(idx-1)+SELECT_SIZE+1 
                        +: f_select_register_size(idx+1)-f_select_register_size(idx) ];
            end
    endgenerate

    mux_lfmr #(.WIDTH(WIDTH), .INPUT_COUNT(INPUT_COUNT), .LATENCY(LATENCY), .TYPE(0), .PRINT(PRINT) )
        mux_object(.clk(clk), .sel(w_sel), .in(in), .out(out) );
    
endmodule

module mux_lfmr #(
    parameter WIDTH = 1,
    parameter INPUT_COUNT = 2,
    parameter LATENCY = 0,
    parameter TYPE = 0,
    parameter PRINT = 0
)( clk, sel, in, out );
    input   wire                                clk;
    input   wire    [$clog2(INPUT_COUNT)-1:0]   sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;
    
    `include "recursion_iterators.vh"

    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(INPUT_COUNT, LATENCY);
            endcase
            if(PRINT!=0)$write("mux_lfmr - f_GetMuxSize: LATENCY:%0d\tINPUT_COUNT:%0d \f_NaryRecursionGetUnitWidthForLatency:%0d\t",LATENCY, INPUT_COUNT, f_GetMuxSize );
            f_GetMuxSize = 'd1 << $clog2(f_GetMuxSize);
            if(PRINT!=0)$display("mux_lfmr - f_GetMuxSize:%0d", f_GetMuxSize);
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
        always @(posedge clk) `ASSUME( !past_valid || sel < INPUT_COUNT );

        `ifdef FORMAL_MUX_LFMR
            // only change 'sel' when pipeline if finished and output is valid
            always @(posedge clk) `ASSUME( !past_valid || valid_output || $stable(sel) );

            // only change 'in' when pipeline if finished and output is valid
            always @(posedge clk) `ASSUME( !past_valid || valid_output || $stable(in) );

        // ensure the simulation is working properly
            // report an output !zero and a sel !zero.
            always @( posedge clk ) cover( valid_output && p_in[WIDTH*p_sel+:WIDTH] == $past(out) && p_sel != 0 && $past(out) != 0);
        `else
            always @( posedge clk ) cover( valid_output && in[WIDTH*sel+:WIDTH] == out && sel != 0);
        `endif

        // Assert the outputs
        // check of the output is correct when the pipeline is finished propagating.
        always @(posedge clk) assert( !valid_output || p_in[WIDTH*p_sel+:WIDTH] == $past(out) );
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
    input   wire    [$clog2(INPUT_COUNT)-1:0]   sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;

    `include "recursion_iterators.vh"
    function automatic integer f_GetMuxSize;
        input unused;
        begin
            case(TYPE)
                default:    f_GetMuxSize = f_NaryRecursionGetUnitWidthForLatency(INPUT_COUNT, LATENCY); // BUG. for input_count 3 LATENCY 1 - returns incorrect value. rt is 4four. should be 2two
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
        initial if(PRINT!=0)$display("mux_combinational - INPUT_COUNT:%0d MUX_SIZE:%0d STRUCTURE_TYPE:%0d STRUCTURE_SIZE:%0d STRUCTURE_DEPTH:%0d SEL_WIDTH:%0d", INPUT_COUNT, MUX_SIZE, TYPE, STRUCTURE_SIZE, STRUCTURE_DEPTH, SEL_WIDTH);
        genvar unit_index, input_index;
        for( unit_index = 0; unit_index < TOTAL_UNIT_COUNT; unit_index = unit_index + 1) begin : mux_unit_loop
            if( f_GetUnitOutputAddress(unit_index) != ~0 ) begin
                // build the unit's inputs.
                wire [MUX_SIZE*WIDTH-1:0] unit_inputs;
                for( input_index = 0; input_index < MUX_SIZE; input_index = input_index + 1 ) begin : mux_input_loop
                    if( input_index < f_GetUnitWidth(unit_index) ) begin
                        initial if(PRINT!=0)$write(" (II:%2d A:%2d)", input_index, f_GetInputAddress(unit_index, input_index) );
                        assign unit_inputs[WIDTH*input_index+:WIDTH] = w_input_chain[f_GetInputAddress(unit_index, input_index)*WIDTH+:WIDTH];
                    end else // Todo rewrite this if/else block to remove the below line and not infer a latch
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
