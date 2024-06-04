`default_nettype none
//`define TEST_BENCH_RUNNING
`ifdef FORMAL
    `define TEST_BENCH_RUNNING
`endif
`ifdef TEST_BENCH_RUNNING
    `define ALU_PRIMITIVE alu_simulation_wrapper
`else
    `define ALU_PRIMITIVE ALU
`endif

`define ALU_TYPE_ADD        0
`define ALU_TYPE_SUB        1
`define ALU_TYPE_ADDSUB     2
`define ALU_TYPE_NOTEQ      3
`define ALU_TYPE_GREATER_EQ 4
`define ALU_TYPE_LESS_EQ    5
`define ALU_TYPE_COUNTUP    6
`define ALU_TYPE_COUNTDOWN  7
`define ALU_TYPE_COUNTUPDOWN 8
`define ALU_TYPE_MULTIPLIER 9


module ALU_PIPELINE #(
        parameter WIDTH     = 15,
        parameter TYPE      = 0,
        parameter ALU_WIDTH  = 4
)( clk, I0, I1, I3, CIN, PL_IN, COUT, SUM, PL_OUT );

    localparam CHUNK_COUNT = WIDTH % ALU_WIDTH == 0  // find the amount of chunks needed to contain the counter
                            ? WIDTH / ALU_WIDTH
                            : WIDTH / ALU_WIDTH + 1;

    input   wire                        clk;
    input   wire    [WIDTH-1:0]         I0;
    input   wire    [WIDTH-1:0]         I1;                 
    input   wire                        I3;
    input   wire                        CIN;
    input   wire    [CHUNK_COUNT-2:0]   PL_IN;
    output  wire                        COUT;
    output  wire    [WIDTH-1:0]         SUM;
    output  wire    [CHUNK_COUNT-2:0]   PL_OUT;
   
    // find the size of the last chunk
    localparam LAST_CHUNK_SIZE = WIDTH % ALU_WIDTH == 0 ? ALU_WIDTH : WIDTH % ALU_WIDTH;
    generate
        genvar ida;                                     // for loop iterator
        // tSize is the size of the current instance, all but the last will be a full ALU_WIDTH, the last can be shorter
        // The last can also be the only instnace
        `define alu_pipeline_tSize (ida < CHUNK_COUNT - 1) ? ALU_WIDTH : LAST_CHUNK_SIZE
        for( ida = 0; ida < CHUNK_COUNT; ida = ida + 1 ) begin :gen_alu_pipeline
            wire alu_CIN;
            if( ida == 0 ) begin
                assign alu_CIN = CIN;
            end else begin
                assign alu_CIN = PL_IN[ida-1];
            end

            wire alu_COUT;
            if( ida >= CHUNK_COUNT-1 ) begin
                assign COUT = alu_COUT;
            end else begin
                assign PL_OUT[ida] = alu_COUT;
            end

            ALU_CHAIN #( .WIDTH( `alu_pipeline_tSize ),
                         .TYPE(  TYPE ))
                alu_chain_inst(
                    .I0(    I0[ ida * ALU_WIDTH +: `alu_pipeline_tSize ] ),
                    .I1(    I1[ ida * ALU_WIDTH +: `alu_pipeline_tSize ] ),
                    .I3(    I3 ),
                    .CIN(   alu_CIN ),
                    .COUT(  alu_COUT ),
                    .SUM(   SUM[ida * ALU_WIDTH +: `alu_pipeline_tSize ] )
            );
        end
        `undef alu_pipeline_tSize   // clear the tempary define tSize
    endgenerate
endmodule

module ALU_CHAIN #(
        parameter WIDTH = 4,
        parameter TYPE  = 0
)
(
    input   wire [WIDTH-1:0]    I0,
    input   wire [WIDTH-1:0]    I1,                 
    input   wire                I3,
    input   wire                CIN,
    output  wire                COUT,
    output  wire [WIDTH-1:0]    SUM
);

    wire [WIDTH:0] carry_chain;
    generate
        genvar ida;
        assign carry_chain[0] = CIN;
        assign COUT = carry_chain[WIDTH];
        for( ida = 0; ida < WIDTH; ida = ida + 1) begin : gen_alu_chain
            `ALU_PRIMITIVE alu_element( .I0(    I0[ida] ),
                                        .I1(    I1[ida] ),
                                        .I3(    I3 ),
                                        .CIN(   carry_chain[ida] ),
                                        .COUT(  carry_chain[ida+1] ),
                                        .SUM(   SUM[ida] )
                                      );
                                      defparam alu_element.ALU_MODE = TYPE;
        end
    endgenerate

endmodule

module alu_simulation_wrapper #(
    parameter ALU_MODE = 0
)
(
    input   wire    I0,
    input   wire    I1,                 
    input   wire    I3,
    input   wire    CIN,
    output  wire    COUT,
    output  wire    SUM
);
    case(ALU_MODE)
        `ALU_TYPE_ADD: begin // add
            assign COUT = |{ &{I1, CIN}, &{I0, CIN}, &{I0, I1} };
            assign SUM  = |{ &{!I0, !I1, CIN}, &{!I0, I1, !CIN}, &{I0, !I1, !CIN}, &{I0, I1, CIN} };       
        end
        `ALU_TYPE_SUB: begin // sub
            assign COUT = |{ &{!I1, CIN}, &{I0, !I1}, &{I0, CIN} };
            assign SUM  = |{ &{!I0, !I1, !CIN}, &{!I0, I1, CIN}, &{I0, !I1, CIN}, &{I0, I1, !CIN} };
        end
        `ALU_TYPE_ADDSUB: begin // AddSub
            assign COUT = |{ &{I0, CIN}, &{!I1, CIN, !I3}, &{I1, CIN, I3}, &{I0, !I1, !I3}, &{I0, I1, I3} };
            assign SUM  = |{ &{!I0, !I1, !CIN, !I3}, &{!I0, !I1, CIN, I3}, &{!I0, I1, !CIN, I3}, &{!I0, I1, CIN, !I3}, &{I0, !I1, !CIN, I3}, &{I0, !I1, CIN, !I3}, &{I0, I1, !CIN, !I3}, &{I0, I1, CIN, I3} };
        end
        `ALU_TYPE_NOTEQ: begin // Not Equal
            assign COUT = |{ CIN, &{!I0, I1}, &{I0, !I1} };
            assign SUM  = |{ &{!I0, !I1, !CIN}, &{!I0, I1, CIN}, &{ I0, !I1, CIN}, &{I0, I1, !CIN} };
        end
        `ALU_TYPE_GREATER_EQ: begin // Greater than equals
            assign COUT = |{ &{!I1, CIN}, &{I0, !I1}, &{I0, CIN} };
            assign SUM  = |{ &{!I0, !I1, !CIN}, &{!I0, I1, CIN}, &{I0, !I1, CIN}, &{I0, I1, !CIN} };
        end
        `ALU_TYPE_LESS_EQ: begin// Less than or equals  // not correct
            assign COUT = |{ &{!I0, CIN}, &{!I0, I1}, &{I1, CIN} };
            assign SUM  = |{ &{!I0, !I1, !CIN}, &{!I0, I1, CIN}, &{I0, !I1, CIN}, &{I0, I1, !CIN} };
        end
        `ALU_TYPE_COUNTUP: begin // Count up
            assign COUT = &{I0, CIN};
            assign SUM  = |{ &{!I0, CIN}, &{I0, !CIN} };
        end
        `ALU_TYPE_COUNTDOWN: begin // Count Down
            assign COUT = |{ CIN, I0 };
            assign SUM  = |{ &{!I0, !CIN}, &{I0, CIN} };
        end
        `ALU_TYPE_COUNTUPDOWN: begin // Count Up Down
            assign COUT = |{ &{CIN, !I3}, &{I0, !I3}, &{I0, CIN} };
            assign SUM  = |{ &{!I0, !CIN, !I3}, &{!I0, CIN, I3}, &{I0, !CIN, I3}, &{I0, CIN, !I3} };
        end
        `ALU_TYPE_MULTIPLIER: begin // Multiplier
            assign COUT = &{ I0, I1, CIN };
            assign SUM  = |{ &{!I0, CIN}, &{!I1, CIN}, &{I0, I1, !CIN} };
        end
    endcase
endmodule