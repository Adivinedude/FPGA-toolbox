`default_nettype none
`ifdef FORMAL
    `define TEST_BENCH_RUNNING
`endif

module ff_dffre
    #(
        parameter INIT = 1'b0
    )
    (
        input   wire    D,
        input   wire    CLK,
        input   wire    RESET,
        input   wire    CE,
        output  wire    Q
    );
`ifndef TEST_BENCH_RUNNING
    DFFRE dffre (
        .D(     D),
        .CLK(   CLK),
        .RESET( RESET),
        .CE(    CE),
        .Q(     Q)
    );
    defparam dffre.INIT=INIT;
`else
    reg data = INIT;
    assign Q = data;
    always @(posedge CLK) begin
        if( RESET )
            data <= INIT;
        else if( CE )
            data <= D;
    end
`endif


endmodule