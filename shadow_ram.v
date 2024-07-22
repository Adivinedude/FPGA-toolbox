`default_nettype none
// basic ssram semi-dual port 4bits wide 16 words deep max.
// datasheet: UG285E.pdf Page 55
// URL: http://cdn.gowinsemi.com.cn/UG285E.pdf
module ssram16dp #(
    parameter width = 4,
    parameter depth = 16
)
(
    clk,
    re,         // Read Enable
    we,         // Write Enable
    raddress,
    waddress,
    dataIn,
    dataOut
)/* synthesis syn_ramstyle = "distributed_ram" */;
    localparam aw = $clog2(depth) - 1; // address width
    localparam w  = width - 1;
    localparam d  = depth - 1;
    input   wire            clk;
    input   wire            re;
    input   wire            we;
    input   wire    [aw:0]  raddress;
    input   wire    [aw:0]  waddress;
    input   wire    [w:0]   dataIn;
    output  wire    [w:0]   dataOut;

    reg [w:0] ram [d:0]; 
    `ifndef FORMAL
        assign dataOut = re ? ram[raddress] : 4'bzzzz;
    `endif
    always @( posedge clk )begin
        if( we )
            ram[waddress] <= dataIn;
    end
endmodule 

/* This module stack the basic blocks together in columns and rows to provide custom width and 
depth. Increasing the width will be simple as each column module will provide data for its section
of output bits. Increasing the rows or depth will require the use of a multiplexer to select which
ram blocks will be accessed.

// This module can read from one address while writing to another. Writing is performed on the negedge
// of the clk, and reading on the posedge. 
// Pay special attention to the timing diagram, table 5-5 on page 49.
// Writes to the memory occure on the posedge of the clock, with half a tick setup time.
// Reads from the memory occure on the negedge of the clock, with half a tick setup time.
// Simulation showed Sucessful results with zero setup time, but the code would not run on the chip.
// After strictly following these timing diagrams, the error was corrected.
//
// This solution inverts the clock going to the memory, so that setup time for data Writes will be 
// meet when using modules that write data on the posedge of the clk at the same time write enable goes high.
// Read request should be implmented no later than the negedge of the clk, so that data will be available at
// the next posedge.
*/
module ssram16dp_array #(
    parameter width = 8,
    parameter depth = 32,
    parameter type = 0 // 0 = ssram 1 = bram
)
(
    clk,
    we,
    raddress,
    waddress,
    dataIn,
    dataOut
);
    localparam array_width  = (width / 4 ) ? width / 4 : 1;     // data columns
    localparam array_depth  = (depth / 16) ? depth / 16 : 1;    // data rows
    localparam aw           = ($clog2(depth)-1 >= 4 ) ? $clog2(depth)-1 : 3;  // address width

    input wire              clk;
    input wire              we;
    input wire  [aw:0]      raddress;
    input wire  [aw:0]      waddress;
    input wire  [width-1:0] dataIn;
    output wire [width-1:0] dataOut;

    wire        [array_depth-1:0]   write_enable; // one hot registers
    wire        [array_depth-1:0]   read_enable;
    genvar a, b;    
    generate 
        for( a = 0; a < array_depth; a = a + 1 ) begin : ssramArray_rows
            for( b = 0; b < array_width; b = b + 1 ) begin : ssramArray_columns
                ssram16dp memory_array(
                    .clk(       clk ),
                    .we(        write_enable[a] ),
                    .re(        read_enable[a] ),
                    .raddress(  raddress[3:0] ),
                    .waddress(  waddress[3:0] ),
                    .dataIn(    dataIn [3+b*4 : b*4] ),
                    `ifndef FORMAL
                        .dataOut(   dataOut[3+b*4 : b*4] )
                    `endif 
                );
            end
            if( aw > 3 ) begin
                assign write_enable[a] = ( waddress[aw:4] == a ) ? we   : 0;
                assign read_enable[a]  = ( raddress[aw:4] == a ) ? 1'b1 : 0;
            end else begin
                assign write_enable[a] = we;
                assign read_enable[a]  = 1'b1;
            end
        end
    endgenerate
`ifdef FORMAL
    // Check that only 1 write_enable bit is set at a time
    always @( * ) assert( $countones( write_enable ) <= 1 );
    // Check that only 1 read_enable bit is alway set at any time
    always @( * ) assert( $countones( read_enable ) == 1 );
    // Check that we are within the proper address range
    always @( * ) assert( raddress < depth );
    always @( * ) assert( waddress < depth );
    
`endif
endmodule