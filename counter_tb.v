// `timescale 1ns/100ps
`default_nettype none
`define WIDTH       4
`define LATENCY     4
`define count_to    4
`define max_strobe_count 10
`define TEST_BENCH_RUNNING
`define MAKE_DUMP
module test();
    //Test in/out
    reg                             rst         = 1;
    reg                             clk         = 0;        // input clock
    reg                             enable      = 0;
    reg     [`WIDTH-1:0]            reset_value = `count_to;
    wire                            strobe;
    wire                            ready;
    wire                            valid;

    //Test Modules
    counter_with_strobe
    #( 
        .WIDTH( `WIDTH ), 
        .LATENCY( `LATENCY )
    ) 
    counter
    (
        .rst(           rst),
        .clk(           clk),
        .enable(        enable),
        .reset_value(   reset_value),
        .strobe(        strobe),
        .ready(         ready),
        .valid(         valid)
    );
    reg [15:0] clock_counter = 0;
    always @( posedge clk )
        if( !rst )
            clock_counter <= clock_counter + 1'b1;

    reg [15:0] tick_counter = 0;
    reg [15:0] strobe_counter = 0;
    always #0.5 clk <= ~clk;
    always @( posedge clk ) tick_counter = tick_counter + ( (!rst && enable) );
    //always @( tick_counter) $display("%d", tick_counter );
    // Test Setup
    initial begin
        `ifdef MAKE_DUMP
            $dumpfile("UUT.vcd");
            $dumpvars(0, test);
        `endif
        $display("starting counter_tb.v");
        $display("WIDTH: %d\t LATENCY: %d\t count_to: %d", `WIDTH, `LATENCY, `count_to);
        #20000 $display( "***WARNING*** Forcing simulation to end");
        $finish;
    end

    //Test
    reg [15:0] current_test     = 0;
    reg [15:0] current_stage    = 0;

    integer a;

    always @( posedge clk ) 
        if( strobe )
            $display( "%d %d counter strobe received %d",$time, tick_counter, tick_counter % `count_to );

    always @(posedge clk) begin
        current_test <= current_test + 1;
        case( current_stage )
        /*  // reuse this block for each test stage
            1: begin
                if( current_test == 0 )
                    $display("new test");
                // test code here
                if( current_test == `depth-1 ) begin
                    current_stage <= current_stage + 1;
                    current_test <= 0;
                end
            end
        */
            0: begin    // reset device
                rst <= 1;
                current_stage <= current_stage + 1; // next stage
                current_test <= 0;
            end

            1: begin
                rst <= 0;
                current_stage <= current_stage + 1; // next stage
                current_test <= 0;
            end
            2: begin
                if( current_test == 0 ) begin
                    $display("enable counters, 1/8 ratio");
                end
                // enable <= (clock_counter % 10 == 0);    // enable writing
                if( !enable && ready )
                    enable <= 1'b1;
                else
                    enable <= 1'b0;
                if( strobe ) begin
                    strobe_counter = strobe_counter + 1;
                    // if( strobe_counter > (`max_strobe_count / 2) ) begin
                    if( strobe_counter > (`max_strobe_count) ) begin
                        current_stage <= current_stage + 1; // next stage
                        current_test <= 0;
                    end
                end
            end
            // 3: begin
            //     if( current_test == 0 )
            //         $display("enable counters, unstable enable");
            //     enable <= ~enable;
            //     if( strobe ) begin   // stop when finished
            //         strobe_counter = strobe_counter + 1;
            //         if( strobe_counter > `max_strobe_count ) begin
            //             current_stage <= current_stage + 1; // next stage
            //             current_test <= 0;
            //         end
            //     end
            // end
            default: begin
                $display("Test finished Properly");
                #6 $finish;
            end
        endcase
    end

endmodule