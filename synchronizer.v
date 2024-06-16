`default_nettype none

module synchronizer #(
        parameter DEPTH_INPUT  = 2,
        parameter DEPTH_OUTPUT = 2,
        parameter INIT         = 1'b0
)( clk_in, in, clk_out, out);

    input   wire clk_in;
    input   wire in;
    input   wire clk_out;
    output  wire out;

    wire w_in;
    generate
        case ( DEPTH_INPUT )
        0:  assign w_in = in;
        1: begin
            reg input_ff = INIT;
            always @( posedge clk_in ) input_ff <= in;
            assign w_in = input_ff;
        end
        default: begin
            reg [DEPTH_INPUT-1:0] input_vector = { DEPTH_INPUT{INIT} };
            always @( posedge clk_in ) 
               input_vector <= { in, input_vector[DEPTH_INPUT-1:1] };
            assign w_in = input_vector[0];
        end
        endcase

        case ( DEPTH_OUTPUT )
        0: assign out = w_in;
        1: begin
            reg output_ff = INIT;
            always @( posedge clk_out ) output_ff <= w_in;
            assign out = output_ff;
        end
        default: begin
            reg [DEPTH_OUTPUT-1:0] output_vector = { DEPTH_OUTPUT{INIT} };
            always @( posedge clk_out ) 
               output_vector <= { w_in, output_vector[DEPTH_OUTPUT-1:1] };
            assign out = output_vector[0];
        end
        endcase

    endgenerate

endmodule