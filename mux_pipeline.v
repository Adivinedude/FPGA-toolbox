`default_nettype none
// Multiplexer with a fixed output latency.
module mux_fixed_pipeline #(
    parameter WIDTH = 4,
    parameter INPUT_COUNT = 2,
    parameter MUX_SIZE = 2, // must be a 2**N value, 2,4,8,16.....
    parameter PRIORITY = 0  // 0 - fixed latency for all outputs, !0 priority given to MSB selection.
)( clk, sel, in, out );
    input   wire                                clk;
    input   wire    [$clog2(INPUT_COUNT)-1:0]   sel;
    input   wire    [(WIDTH*INPUT_COUNT)-1:0]   in;
    output  wire    [WIDTH-1:0]                 out;

    `ifndef FORMAL
        `include "./toolbox/recursion_iterators.h"
    `else
        `include "recursion_iterators.h"
    `endif
    //  LUT width 2 Unit Count 11 PRIORITY-FIXED                   
    //  base #  0___1   2___3   4___5   6___7   8___9
    //              |       |       |       |       |
    //             10______11      12______13      14
    //                      |               |       |
    //                     15______________16      17
    //                                      |       |
    //                                     18______19
    //                                              |
    //                                            trigger

    function automatic integer f_GetVectorSize;
        input unused;
        f_GetVectorSize = f_NaryRecursionGetVectorSize( INPUT_COUNT, MUX_SIZE );
    endfunction

    function automatic integer f_GetUnitWidth;
        input integer unit_index;
        f_GetUnitWidth = f_NaryRecursionGetUnitWidth(INPUT_COUNT, MUX_SIZE, unit_index);
    endfunction

    function automatic integer f_GetAddress;
    input integer unit_index, input_index;
        f_GetAddress = f_NaryRecursionGetUnitInputAddress(INPUT_COUNT, MUX_SIZE, unit_index, input_index );
    endfunction

    function automatic integer f_GetDepth;
    input integer unit_index;
        f_GetDepth = f_NaryRecursionGetUnitDepth(INPUT_COUNT, MUX_SIZE, unit_index);
    endfunction

    // find the size of the vector needed
    localparam STRUCTURE_SIZE = f_GetVectorSize(0);
    wire    [ ( ( INPUT_COUNT + STRUCTURE_SIZE ) * WIDTH ) - 1 : 0 ]    w_input_chain;
    reg     [ ( STRUCTURE_SIZE * WIDTH ) - 1 : 0 ]                      r_mux_structure;
    assign w_input_chain = { r_mux_structure, in };
    assign out = w_input_chain[ ( ( INPUT_COUNT + STRUCTURE_SIZE - 1 ) * WIDTH ) +: WIDTH ];
    genvar unit_index, input_index;
    for( unit_index = 0; unit_index < STRUCTURE_SIZE; unit_index = unit_index + 1) begin : mux_unit_loop
        for( input_index = 0; input_index != f_GetUnitWidth(unit_index); input_index = input_index + 1 ) begin : mux_input_loop
            // perform the selection and store the output
            // initial $display( "unit_index:%d input_index:%d addr:%d", unit_index, input_index, f_GetAddress(unit_index, input_index) );
            if( f_GetUnitWidth(unit_index) != 1 ) begin
                always @(posedge clk) begin
                    // $display("sel:%b unit:%d input:%d sel:%b depth:%d", sel, unit_index, input_index, sel[f_GetDepth(unit_index)*(MUX_SIZE/2)+:(MUX_SIZE/2)], f_GetDepth(unit_index));
                    if( sel[f_GetDepth(unit_index)*(MUX_SIZE/2)+:(MUX_SIZE/2)] == input_index )begin
                        r_mux_structure[unit_index*WIDTH+:WIDTH] <= w_input_chain[f_GetAddress(unit_index, input_index)*WIDTH+:WIDTH];
                    end
                end
            end else begin
                always @(posedge clk) r_mux_structure[unit_index*WIDTH+:WIDTH] <= w_input_chain[f_GetAddress(unit_index, input_index)*WIDTH+:WIDTH];
            end
        end
    end
endmodule


module mux_tb;
    reg             clk = 0;
    reg     [39:0]   in;
    integer in_loop;
    initial begin
        for(in_loop = 0; in_loop < 10; in_loop = in_loop + 1 )
            in[in_loop*4+:4] = in_loop[3:0];
    end

    wire    [3:0]   out;
    reg     [7:0]   sel = 0;

    mux_fixed_pipeline#(.WIDTH(4), .INPUT_COUNT(10))
        UUT( .clk(clk), .sel(sel[7:4]), .in(in), .out(out) );

    always #1 clk <= ~clk;
    always @(posedge clk) begin
        sel <= sel + 1'b1;
        // $display("sel:%d\tout:%d", sel[5:4], out);
    end

    initial begin
        $dumpfile("UUT.vcd");
        $dumpvars(0, mux_tb);
        $display("starting mux_tb.v");
        #512 $display( "***WARNING*** Forcing simulation to end");
        $finish;
    end
endmodule