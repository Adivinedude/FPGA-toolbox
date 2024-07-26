`default_nettype none
module fifo #(
    parameter WIDTH = 16,
    parameter DEPTH = 16,
    parameter A_EMPTY = 2,
    parameter A_FULL  = 2
)
(
    input   wire                clk,
    input   wire                rst,
    input   wire                re,         // Read Enable
    input   wire                we,         // Write Enable
    input   wire [WIDTH-1:0]    dataIn,
    output  wire [WIDTH-1:0]    dataOut,
    output  wire                full_flag,
    output  wire                almost_full,
    output  wire                empty_flag,
    output  wire                almost_empty
);

    localparam aw = $clog2(DEPTH);    // address WIDTH
    reg     [aw:0]  front   = 0;      // use extra bit in address to test for empty or full
    reg     [aw:0]  back    = 0;

    assign empty_flag   = front == back;
    assign full_flag    = {~front[aw], front[aw-1:0]} == back;

    reg     [aw:0] r_almost_empty = 0;
    always @( posedge clk ) r_almost_empty <= front + A_EMPTY[0+:aw];
    assign almost_empty = r_almost_empty >= back;

    reg     [aw:0] r_almost_full = 0;
    always @( posedge clk ) r_almost_full <= {~front[aw], front[aw-1:0]} - back;
    assign almost_full  = r_almost_full <= A_FULL;

    wire    buffer_we;
    assign  buffer_we = we;// && !full_flag;
    // ssram16dp_array #( .width( WIDTH ), .depth( DEPTH ) ) 
    //     buffer( .clk(       clk ), 
    //             .we(        buffer_we ),
    //             .raddress(  front[aw-1:0]),
    //             .waddress(  back [aw-1:0]),
    //             .dataIn(    dataIn),
    //             .dataOut(   dataOut)
    //             );
    reg [WIDTH-1:0] buffer [DEPTH-1:0]/* synthesis syn_ramstyle = "distributed_ram" */;
    
    always @( posedge clk ) begin
        if( buffer_we )
            buffer[back[aw-1:0]] <= dataIn;
    end
    assign dataOut = buffer[front[aw-1:0]];
    `ifdef TEST_BENCH_RUNNING
        reg [WIDTH-1:0] last_data_written;
        always @( posedge clk ) begin
            if( !rst ) begin
                if( buffer_we )
                    last_data_written <= dataIn;
            end
        end
    `endif

    always @( posedge clk ) begin
        if( rst ) begin
            back    <= 0;
            front   <= 0;
        end else begin
            if( buffer_we ) begin
                back <= back + 1'b1;
            end
            if( re ) begin // && !empty_flag) begin
                front <= front + 1'b1;
            end
        end
    end

    `ifdef FORMAL
        reg past_valid = 0;
        always @( posedge clk ) past_valid <= 1'b1;
        always @( posedge clk ) assume( rst == !past_valid );

        // How much is in the fifo
        wire [aw:0] addr_diff;
        assign addr_diff = DEPTH - ({~front[aw], front[aw-1:0]} - back);
        
        always @( posedge clk ) overflow:   assert( addr_diff <= DEPTH );                           // check overflow
        always @( posedge clk ) empty:      assert( rst || ((addr_diff == 0) == empty_flag) );      // check empty
        always @( posedge clk ) full:       assert( rst || ((addr_diff == DEPTH)   == full_flag) ); // check full
        always @( posedge clk ) al_empty:   assert( rst || ((addr_diff <= A_EMPTY) == almost_empty) ); // check almost empty
        always @( posedge clk ) al_full:    assert( rst || ((addr_diff >= (DEPTH - A_FULL) ) == almost_full ) ); // check almost full

        // check read/write pointer changes        
        always @( posedge clk ) begin
            if( !rst ) begin
                if( past_valid ) begin
                    assert(  
                        ($past(front) == front) ||      // Value has not changed
                        ($past(front) + 1'b1 == front)  // Value has incremented
                    );
                    assert(  
                        ($past(back) == back) ||        // Value has not changed
                        ($past(back) + 1'b1 == back)    // Value has incremented
                    );
                end
            end
        end
    `endif

endmodule
