/*  stats
    counter width   15
    fmax            168.454(MHz)
    logic levels    3
    LUT             36
    reg             22

    counter width   32
    fmax            168.454(MHz)
    logic levels    3
    LUT             76
    reg             47
*/

`default_nettype none
module counter_eq_cc_pipeline
    #( 
        parameter WIDTH = 15,    // WIDTH must be >= LUT_SIZE or this will break the module
        parameter LUT_SIZE = 4
    )
    ( rst_n, clk, enable, reset_value, strobe);
    input   wire                rst_n;
    input   wire                clk;
    input   wire                enable;
    input   wire [WIDTH-1:0]    reset_value;
    output  wire                strobe;
    input   wire                lut_top;
   
    // the 'reg [WIDTH-1:0] counter;' will be broken into chunks.
    // each chunk will use it's last bit to pipeline the carrie chain.
    // Each '!=' operator will also be pipelined so that the final output will be a much smaller LUT chain,
    // resulting if a faster maxf I hope

    localparam REG_SIZE             = LUT_SIZE + 1;                 // Size of the new registers
    localparam CHUNK_COUNT          = WIDTH % LUT_SIZE == 0         // find the minimum amount of chunks needed to contain the counter
                                        ? WIDTH / LUT_SIZE
                                        : WIDTH / LUT_SIZE + 1;
    localparam LAST_CHUNK_SIZE      = WIDTH % LUT_SIZE == 0         // find the size of the last chunk needed to contain the counter.
                                        ? LUT_SIZE
                                        : WIDTH % LUT_SIZE;
    localparam END_OF_COUNTER       = WIDTH + CHUNK_COUNT - 1 - 1;  // Find the total size of the counter needed, 
                                                                    // includeing the carryover flip flops. Adjust by -1 for zero0 indexing
    reg [END_OF_COUNTER:0]          counter;                        // registers and carry bits for each chunk that has a carry bit
    reg                             prefire = 0;                    // strobe flip flop
 
    assign  strobe  = prefire && enable && rst_n;                   // only fire strobe, when enable && rst_n are HIGH

    integer idx, idy;                                               // for loop iterators
    wire [LUT_SIZE-1:0] next_counter;
    assign next_counter = { 1'b0, counter[ 0 +: LUT_SIZE ] } - 1'b1;
    always @( posedge clk ) begin
        // reset condition
        if( !rst_n || strobe ) begin
            // split the reset_value up into chunks, append the carry bit, and store in the counter register
            for(idx = 0; idx < CHUNK_COUNT-1; idx = idx + 1) begin
                counter[ idx * REG_SIZE +: REG_SIZE ] <= { 1'b0, reset_value[ idx * LUT_SIZE +: LUT_SIZE ] };
            end
            // process the last chunk. it does not have a carry bit and may be <= full LUT_SIZE
            counter[ END_OF_COUNTER -: LAST_CHUNK_SIZE ] <= reset_value[ WIDTH-1 -:LAST_CHUNK_SIZE ];
            prefire         <= 0;   // turn prefire off.
        end else begin 
            // carry chain propagation, start with the second chunk and stop before the last
            for( idy = 1; idy < CHUNK_COUNT-1; idy = idy + 1 ) begin
                // reset this chunks carry bit, then subtract the carry bit of the last chunk
                counter[ idy * REG_SIZE +: REG_SIZE ] 
                    <= { 1'b0, counter[ (idy * REG_SIZE) +: LUT_SIZE ] } - counter[ idy * REG_SIZE - 1 ];
                // Set the lut_bottom flag if the register(without carry bit) == 0
                lut_bottom[ idy - 1 ] <= counter[ idy * REG_SIZE +: LUT_SIZE ] != 0;
            end
            // handle the last chunk, which does not have a carry bit.
            counter[ END_OF_COUNTER -: LAST_CHUNK_SIZE ] 
                <= counter[ END_OF_COUNTER -: LAST_CHUNK_SIZE ] - counter[ END_OF_COUNTER - LAST_CHUNK_SIZE ];

            counter[ 0 +: REG_SIZE ] <= enable ? next_counter : counter;
            //counter[ 0 +: REG_SIZE ] <= { 1'b0, counter[ 0 +: LUT_SIZE ] } - enable;
            if( counter[ 0 +: LUT_SIZE ] == 1 && lut_top ) begin
                prefire <= 1;
            end
        end
    end
    
//////////////////////////////////////////
// Test the counter as a blackbox circuit.
`ifdef FORMAL
    `define TEST_BENCH_RUNNING
    // formal verification comparisions values
    reg             past_valid          = 0;
    reg [WIDTH-1:0] last_reset_value    = 0;
    reg [WIDTH-1:0] tick_counter        = 0;
    always @( posedge clk ) begin
        // verifiy $past is valid
        past_valid <= 1;                    

        // store the current reset_value anytime it is loaded and reset the counter    
        if( !past_valid || !rst_n || strobe ) begin    
            last_reset_value <= reset_value;
            tick_counter <= 0;   
        end else if( rst_n && enable && !strobe ) begin
            // increment the tick counter when 'rst_n' is HIGH and 'enable' is HIGH
            tick_counter <= tick_counter + 1'b1;
        end
    end
// Assume inputs to pass bmc test
    // force the test to start in a reset state
    always @( posedge clk )
        if( !past_valid )
            assume( !rst_n );
 
    // force the 'reset_value' to be greater than one1 but less than sby test 'DEPTH' / 3
    always @( posedge clk ) assume( reset_value > 1);//  && reset_value <= 5);

    // force 'enable' to be LOW no more than 1 tick
    // always @( posedge clk ) assume( enable || $past(enable) );
    // force 'enable' to be HIGH
    always @( posedge clk ) assume( enable == past_valid );

    // induction testing
    // using a 8 bit counter, need a test depth > 255
///////////////////////////////////
// Start testing expected behaviors
    // The strobe bit will only stays HIGH for 1 clock cycle
    always @( posedge clk ) assert( !past_valid ||                  // past is invalid
                                    !strobe     ||                  // strobe is off
                                    $changed(strobe)                // strobe has changed to HIGH
                            );

    // The strobe can NOT go HIGH when 'enable' is LOW
    always @( posedge clk ) assert( enable ? 1 : !strobe );  

    // The strobe can NOT go HIGH when 'rst_n' is LOW
    always @( posedge clk ) assert( rst_n ? 1 : !strobe );                          

    // The strobe must go HIGH every 'reset_value' ticks when 'rst_n' is HIGH and 'enable' is HIGH
    always @( posedge clk ) assert( !rst_n || !enable ||
                                strobe == ( tick_counter == last_reset_value )
                            );
`endif 

`ifdef TEST_BENCH_RUNNING
    // nice visual for GTKWave
    generate
        genvar idz;
        for( idz = 0; idz < CHUNK_COUNT-1; idz = idz + 1 ) begin
            wire [REG_SIZE-1 : 0] chunk_value;
            assign chunk_value = counter[ idz * REG_SIZE +: REG_SIZE ];
        end
        wire [LAST_CHUNK_SIZE-1:0] chunk_value_last;
        assign chunk_value_last = counter[ END_OF_COUNTER -: LAST_CHUNK_SIZE ];
    endgenerate
`endif

endmodule
