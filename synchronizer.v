`default_nettype none

module synchronizer #(
        parameter WIDTH        = 1,
        parameter DEPTH_INPUT  = 2,
        parameter DEPTH_OUTPUT = 2,
        parameter INIT         = 0
)( clk_in, in, clk_out, out);

    input   wire                clk_in;
    input   wire [WIDTH-1:0]    in;
    input   wire                clk_out;
    output  wire [WIDTH-1:0]    out;

    wire [WIDTH-1:0] w_in;
    generate
        case ( DEPTH_INPUT )
        0:  assign w_in = in;
        1: begin
            reg [WIDTH-1:0] input_ff = INIT;
            always @( posedge clk_in ) input_ff <= in;
            assign w_in = input_ff;
        end
        default: begin
            reg [(DEPTH_INPUT * WIDTH)-1:0] input_vector = { DEPTH_INPUT{ INIT } };
            always @( posedge clk_in )
                input_vector <= { in, input_vector[ DEPTH_INPUT * WIDTH - 1 : WIDTH ] };

            assign w_in = input_vector[0+:WIDTH];
        end
        endcase

        case ( DEPTH_OUTPUT )
        0: assign out = w_in;
        1: begin
            reg [WIDTH-1:0] output_ff = { INIT };
            always @( posedge clk_out ) output_ff <= w_in;
            assign out = output_ff;
        end
        default: begin
            reg [(DEPTH_OUTPUT * WIDTH)-1:0] output_vector = { DEPTH_OUTPUT{ INIT } };
            always @( posedge clk_out ) 
               output_vector <= { w_in, output_vector[DEPTH_OUTPUT * WIDTH - 1 : WIDTH ] };
            assign out = output_vector[0+:WIDTH];
        end
        endcase

    endgenerate

endmodule