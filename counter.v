`default_nettype none
module counter_with_strobe
    #( 
        `ifdef FORMAL
            parameter WIDTH     = 4,
            parameter LATENCY   = 2
        `else
            parameter WIDTH     = 32,
            parameter LATENCY   = 5
        `endif
    )
    (
        input   wire                rst,
        input   wire                clk,
        input   wire                enable,
        input   wire [WIDTH-1:0]    reset_value,
        output  wire                strobe,
        output  wire                valid
    );
    // the 'reg [WIDTH-1:0] counter;' will be broken into chunks, the number of which will be based on the LATENCY 
    // each chunk's arithmetic COUT will be stored in the reg carrie_chain[] for the next chunks CIN.
    // the first chunk will not have a CIN, but the enable signal
    // the last chunk will not have a COUT
    // the counter may contain only one chunk.

    integer idx;    // for loop iterator

    // determin the chunk width. knowing that each chunk will take 1 tick, width divided by latency will provide
    // the needed delay as specified in parameter LATENCY. protect values from base2 rounding errors
    localparam ALU_WIDTH    = WIDTH / LATENCY * LATENCY == WIDTH ? WIDTH / LATENCY : WIDTH / LATENCY + 1;
    // find the minimum amount of chunks needed to contain the full counter
    localparam CHUNK_COUNT  = WIDTH % ALU_WIDTH == 0 ? WIDTH / ALU_WIDTH : WIDTH / ALU_WIDTH + 1;
    // find the size of the last chunk needed to contain for the counter.
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH;
    // Build the counter and carry chain registers
    reg     [WIDTH-1:0]         counter_ff = 'd1;
    reg     [CHUNK_COUNT-1:0]   carry_chain = 0;

    // 'valid' used for formal verification
    reg [CHUNK_COUNT:0] valid_tracker   = 0;
    assign              valid           = valid_tracker[CHUNK_COUNT];
    always @( posedge clk ) begin
        if( rst ) begin
            valid_tracker <= 'd1;
        end else begin
            if( enable )
                valid_tracker <= 'd1;
            else begin
                if( !valid )
                    valid_tracker <= { valid_tracker[CHUNK_COUNT-1:0], 1'b0 };
            end
        end
    end
    // 'trigger' comparator construction diagram
    // By using a overlapping slope structure (name not known), the comparators latency can be controlled
    // in order to produce a valid output, 1 clock after the carry chain has completly propagated 
    //  LUT width 2                                 LUT width 3                                 LUT width 4
    //  base #  0___1   2   3   4   5   6   7   8   9   0___1___2   3   4   5   6   7   8   9   0___1___2___3   4   5   6   7   8   9
    //              0___|   |   |   |   |   |   |   |           0___|___|   |   |   |   |   |               0___|___|___|   |   |   |
    //                  1___|   |   |   |   |   |   |                   1___|___|   |   |   |                           1___|___|___|
    //                      2___|   |   |   |   |   |                           2___|___|   |                                       trigger
    //                          3___|   |   |   |   |                                   3___|
    //                              4___|   |   |   |                                       trigger
    //                                  5___|   |   |
    //                                      6___|   |
    //                                          7___|
    //                                              trigger

    // Define a few 'tail recursion iterators' to help build the structure seen above

    // f_GetCmpWidth - Returns the number of LUT needed to build structure
    //  base        - Total number of input bits to compare
    //  lut_width   - Maxium width of the LUT used.
    //  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
    //
    // First Call f_GetCmpWidth(CHUNK_COUNT, LUT_WIDTH, 0 );
    function automatic [7:0] f_GetCmpWidth;
        input [7:0] base, lut_width, rt;         
        f_GetCmpWidth=base==0?rt:f_GetCmpWidth(base-(base>=lut_width?(rt==0?lut_width:lut_width-1):base),lut_width,rt+1);
    endfunction
        // initial begin:test_GetCmpWidth integer idx;$display("f_GetCmpWidth()");for(idx=2;idx<=10;idx=idx+1)begin $display("base_width:10 lut_width:%d cmp_width:%d",idx,f_GetCmpWidth(10,idx,0));end end
 
    // f_GetLastLutWidth - Returns the total number of inputs for the last LUT of the comparator structure
    //  base        - Total number of input bits to compare
    //  lut_width   - Maxium width of LUT used.
    //  rt          - Set to 0zero when calling this function, used internaly, exposed for recursion propertys
    //
    // First Call f_GetLastLutWidth(CHUNK_COUNT, LUT_WIDTH, 0, 0);
    function automatic [7:0] f_GetLastLutWidth;
        input [7:0] base, lut_width, rt, results;
            f_GetLastLutWidth = base == 0 ?results+1:f_GetLastLutWidth(base-(base>=lut_width?(rt==0?lut_width:lut_width-1):base),lut_width,rt+1, (base>=lut_width?(rt==0?lut_width:lut_width-1):base));
    endfunction
        // initial begin:test_GetLastLutWidth integer idx; for(idx=2;idx<10;idx=idx+1)$display("\t\t\tf_GetCmpWireCount(.base(10).lut_width(%d)) last_lut_width%d",idx,f_GetLastLutWidth(10, idx, 0, 0));end   
    // f_GetLutWidthForLatency - Returns the smalles LUT width needed to set the structure's latency to a maxium value.
    //                           The actual latency will be less than or equal to the request
    //  base        - Total number of input bits to compare
    //  latency     - Maxium latency.
    //  lut_width   - MUST BE greater than to 1one. Minium size LUT to use for the comparator. Exposed for recursion propertys
    //
    // First Call f_GetLutWidthForLatency(CHUNK_COUNT, LATENCY, 2);
    function automatic [7:0] f_GetLutWidthForLatency;
        input [7:0] base, latency, lut_width;
        f_GetLutWidthForLatency=(f_GetCmpWidth(base,lut_width,0)<=latency)?lut_width:f_GetLutWidthForLatency(base,latency,lut_width+1);
    endfunction
        // initial begin:test_GetLutWidthForLatency integer idx;$display("f_GetLutWidthForLatency()");for(idx=1;idx<=10;idx=idx+1)begin $display("base:10 latency:%d lut_width:%d",idx,f_GetLutWidthForLatency(10,idx,2));end end
    // f_GetLutInputAddress - Returns the index for the base bit requested.
    //  cmp_width       - width of the comparator
    //  lut_width       - width of the lut used in the comparator
    //  unit_index      - which LUT index is being requested
    //  input_index     - which input of the LUT is being requested
    //  base_input_index- Base input address. Exposed for recursion propertys
    //  past_output_index- Past output address. Exposed for recursion propertys
    //  current_unit    - current unit_index. Exposed for recursion propertys
    //
    //  First Call f_GetLutInputAddress( CHUNK_COUNT, LUT_WIDTH, LUT_NUMBER, INPUT_NUMBER, 0, ~0, 0);
    function automatic [7:0] f_GetLutInputAddress;
        input [7:0] cmp_width, lut_width, unit_index, input_index, base_input_index, past_output_index, current_unit;
            f_GetLutInputAddress = (current_unit==unit_index)?unit_index==0?input_index:input_index==0?past_output_index:(base_input_index-1)+input_index:f_GetLutInputAddress(cmp_width,lut_width,unit_index,input_index,base_input_index==0?base_input_index+lut_width:base_input_index+(lut_width-1),past_output_index+1,current_unit+1);
    endfunction
        // initial begin:test_GetLutInputAddress integer unit_index,input_index;$display("f_GetLutInputAddress");$display("Base:10 LUT_WIDTH:4 LUT_COUNT:3");for(unit_index=0;unit_index<3;unit_index=unit_index+1)for( input_index=0;input_index<4;input_index=input_index+1)$display("unit:%d input:%d address:%d",unit_index,input_index,f_GetLutInputAddress(10,4,unit_index,input_index,0,~0,0));end

    wire trigger;
    localparam CMP_LUT_WIDTH = f_GetLutWidthForLatency(CHUNK_COUNT, LATENCY, 2);
    localparam CMP_REG_WIDTH = f_GetCmpWidth(CHUNK_COUNT, CMP_LUT_WIDTH, 0 );
    localparam CMP_LAST_LUT_WIDTH = f_GetLastLutWidth(CHUNK_COUNT, CMP_LUT_WIDTH, 0, 0);
    initial $display("CMP_LUT_WIDTH %d CMP_REG_WIDTH %d", CMP_LUT_WIDTH, CMP_REG_WIDTH);
    if( CHUNK_COUNT == 1)
        assign trigger = counter_ff >= reset_value;
    else begin
        reg [CHUNK_COUNT-1:0] comparator_base = 0;
        always @( posedge clk ) begin
            if( rst ) begin
                comparator_base <= 0;
            end else begin
                for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin
                    if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
                        comparator_base[idx] <= counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] >= reset_value[idx*ALU_WIDTH+:ALU_WIDTH];
                    end else begin    // == LAST_CHUNK
                        comparator_base[idx] <= counter_ff[idx*ALU_WIDTH+:LAST_CHUNK_SIZE] >= reset_value[idx*ALU_WIDTH+:LAST_CHUNK_SIZE];
                    end
                end
            end
        end
        reg [CMP_REG_WIDTH-1:0] comparator_structure = 0;
        integer unit_index;
        always @( posedge clk ) begin
            if( rst ) begin
                comparator_structure <= 0;
            end else begin
                for( unit_index = 0; unit_index < CMP_REG_WIDTH; unit_index = unit_index + 1) begin
                        comparator_structure[unit_index] <= unit_index==0
                                                            ? &comparator_base[0+:CMP_LUT_WIDTH]
                                                            : unit_index != CMP_REG_WIDTH - 1
                                                                ? &{comparator_structure[unit_index-1], comparator_base[((unit_index-1)*(CMP_LUT_WIDTH-1)+CMP_LUT_WIDTH) +: CMP_LUT_WIDTH-1]}
                                                                : &{comparator_structure[unit_index-1], comparator_base[((unit_index-1)*(CMP_LUT_WIDTH-1)+CMP_LUT_WIDTH) +: CMP_LAST_LUT_WIDTH-1]};
                end
            end
        end
        assign trigger = comparator_structure[CMP_REG_WIDTH-1];
    end                                                                     

    reg     strobe_ff = 0;
    assign  strobe  = strobe_ff;
    always @( posedge clk ) begin
        strobe_ff <= 0;   // turn strobe_ff off.
        if( rst ) begin
            counter_ff <= 'd1;
            carry_chain <= 0;
        end else begin
            // carry chain propagation,
            // exceptions
            //  first chunk - .CIN(enable), all others .CIN(carry_chain[idx-1])
            //  last_chunk  - .COUT(null)
            //  last_chunk  - .WIDTH(LAST_CHUNK_SIZE)
            for( idx = 0; idx <= CHUNK_COUNT - 1; idx = idx + 1 ) begin
                if( idx != CHUNK_COUNT - 1 ) begin // !LAST_CHUNK
                    { carry_chain[idx], counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] } <= { 1'b0, counter_ff[idx*ALU_WIDTH+:ALU_WIDTH] } + (idx == 0 ? enable : carry_chain[idx-1]);
                end else begin    // == LAST_CHUNK
                    counter_ff[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] <= counter_ff[WIDTH-1:WIDTH-LAST_CHUNK_SIZE] + (idx == 0 ? enable : carry_chain[idx-1]);
                end
            end 
            if( enable ) begin
                if( trigger ) begin
                    counter_ff <= 'd1;
                    carry_chain <= 0;
                    strobe_ff <= 1;
                end
            end
        end // !rst
    end 
/////////////////////////////////////////////
// Test the counter as a blackbox circuit. //
/////////////////////////////////////////////
`ifdef FORMAL
    `define TEST_BENCH_RUNNING
`endif 

`ifdef TEST_BENCH_RUNNING
    // formal verification comparisions values
    reg             past_valid          = 0;
    reg             past_valid_1        = 0;
    //initial assume( past_valid == 0 && past_valid_1 == 0 );

    reg [WIDTH-1:0] tick_counter        = 0;
    always @( posedge clk ) begin
        // verifiy $past is valid
        past_valid   <= 1;
        past_valid_1 <= past_valid;                    

        // store the current reset_value anytime it is loaded and reset the counter    
        if( rst || strobe ) begin    
            tick_counter = 0;   
        end 
        if(!rst && enable ) begin
            // increment the tick counter when 'rst' is HIGH and 'enable' is HIGH
            tick_counter <= tick_counter + 1'b1;
        end
    end
`endif 

`ifdef FORMAL
// Assume inputs to pass bmc test
    // // // //
    // rst   //
    // // // //
        // force the test to start in a reset state
        initial assume(rst);
        // force any reset to last 2 clock cycles
        // always @( posedge clk ) if( past_valid_1 ) assume( $fell(rst) ? $past(rst,2) : 1);
    // // // // //
    // enable   //
    // // // // //
            // force 'enable' to be LOW when '!valid' and no more than 2 ticks when 'valid'
            always @( posedge clk ) begin
                if( !past_valid_1 || rst )
                    assume(!enable);
                else
                    assume( &{!valid, !enable} || &{ $past(valid), |{enable, $past(enable), $past(enable,2)} } );

            end
    // // // // // //
    // reset_value //
    // // // // // //
        // force the 'reset_value' to be greater than 1 but less than sby test 'DEPTH' / 3 b/c of the alternating enable bit
        always @( posedge clk ) assume( reset_value >= 2 && reset_value <= 15 );

        // force the 'reset_value to stay stable while running
        // always @( posedge clk ) if( past_valid ) assume( (!rst || !strobe) ? !$changed(reset_value) : 1 );



// induction testing
// using a 8 bit counter, need a test depth > 255 with enable forced high, 510 with enable toggling
///////////////////////////////////
// Start testing expected behaviors
    // The strobe can only go high when  ticks == 'reset_value'
    always @( posedge clk ) assert( |{  !past_valid_1,
                                        rst,
                                        strobe == &{tick_counter == reset_value, $past(valid,2) }
                                    } );
    // always @( posedge clk ) assert( !past_valid || rst || !strobe ||( strobe == ( tick_counter >= reset_value ) ) );
    // The strobe bit will only stays HIGH for 1 clock cycle
    always @( posedge clk ) assert( !past_valid ||                  // past is invalid
                                    !strobe     ||                  // strobe is off
                                    $changed(strobe)                // strobe has changed to HIGH
                            );

    always @( posedge clk ) cover( strobe == 1'b1 );

`endif
endmodule