////////////////////////////////////////////////////////////////////////////////
//
// Filename:	uart_rx.v
//
// Project:	uart_rx 
//
// Purpose:	a fast, configurable universal asynchronous receiver
//
// Creator:	Ronald Rainwater
// Data: 2024-7-20
////////////////////////////////////////////////////////////////////////////////
// Copyright (C) 2024, Ronald Rainwater
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program. If not, see <http://www.gnu.org/licenses/> for a copy.
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
////////////////////////////////////////////////////////////////////////////////

// This module implements a multi-sample uart input. 
// 'uart_rx_ready' will go high for 1 clk cycle when dataout is valid.
// dataout will stay valid until the next transmission is complete 
// input clock frequency must be  clk_freq >= 1 ÷ [1 ÷ (brad_rate × sample_count)]
//
// Order of Operation.
//  1) When 'w_rx_pin_syn' goes low, start 'sample_counter','bit_counter' & oversampling.
//      When the bit period has expired('w_bit_ce'==HIGH), test 'w_sample_value'
//      2A) if 'w_sample_value' is HIGH, where was a false trigger, GoTo Idle State.
//      2B) if 'w_sample_value' is LOW, We have received the start bit. GoTo Read State.
//  3) When entering Read State, set 'rxDataBits' to 'UART_CONFIG_BITS_DATABITS'
//  4) Store incoming data at each 'w_bit_ce' and decrement 'rxDataBit' until it == Zero
//  5) 

`default_nettype none
`include "uart/uart_include.v"
module uart_rx
#(
    parameter COUNTER_WIDTH       = `UART_CONFIG_WIDTH_DELAYFRAMES,
    parameter DATA_WIDTH          = `UART_CONFIG_WIDTH_DATABITS,
    parameter SAMPLE_COUNT        = 1, // number of r_sample_buffer taken per bit of a frame. needs to be an (2**x)-1 for speed. 1, 3, 7, 15, 31....
    parameter LATENCY             = 0
)
(
    input   wire                    clk,
    input   wire                    ce,
    input   wire                    uart_rxpin,     // input rx pin
    output  reg [DATA_WIDTH-1:0]    dataout,        // output data, only valid after uart_rx_ready goes high
    output  reg                     uart_rx_ready,  // dataout is valid on HIGH, duration 1 clk cycle
    output  reg                     uart_rx_error,  // Transmission contained a parity error
    input   wire                    rst,
    input   wire [`UART_CONFIG_WIDTH-1:0] settings
);
    // for loop iterator
    integer a;
    // states
    localparam RX_STATE_IDLE    = 0;
    localparam RX_STATE_START   = 1;
    localparam RX_STATE_READ    = 2;
    localparam RX_STATE_PARITY  = 3;
    localparam RX_STATE_STOP    = 4;
    localparam RX_NUMBER_OF_STATES = 5;

    // shift input r_sample_buffer into the 'r_sample_buffer' register
    localparam SAMPLE_WIDTH     = $clog2(SAMPLE_COUNT)+1;
    localparam COUNTER_LATENCY  = (LATENCY == 0) ? LATENCY : LATENCY - 1;

    // registers
    reg     [$clog2(RX_NUMBER_OF_STATES)-1:0]               r_rx_state              = RX_STATE_IDLE;
    reg                                                     r_rx_state_changed      = 0;
    reg     [COUNTER_WIDTH - $clog2(SAMPLE_COUNT) - 1:0]    r_sample_clk_rst_value  = ~0; // sample clock reset value
    reg     [SAMPLE_WIDTH-1:0]                              r_sample_buffer         = SAMPLE_COUNT;
    reg     [`UART_CONFIG_WIDTH-1:0]                        r_current_settings      = 0; // config settings - see 'uart_include.v' for details
    reg     [DATA_WIDTH-1:0]                                r_data_frame            = 0; // over sampled result
    reg     [$clog2(DATA_WIDTH):0]                          r_rx_bit_number         = 0;
    reg                                                     r_rx_parity             = 0;
    reg     [`UART_CONFIG_WIDTH_DATABITS-1:0]               r_rx_bit_number_I2      = 0;


    wire [`UART_CONFIG_WIDTH_DELAYFRAMES-1:0]   UART_CONFIG_DELAY_FRAMES = r_current_settings[`UART_CONFIG_BITS_DELAYFRAMES];
    wire [`UART_CONFIG_WIDTH_STOPBITS-1:0]      UART_CONFIG_STOPBITS     = r_current_settings[`UART_CONFIG_BITS_STOPBITS];
    wire [`UART_CONFIG_WIDTH_PARITY-1:0]        UART_CONFIG_PARITY       = r_current_settings[`UART_CONFIG_BITS_PARITY];
    wire [`UART_CONFIG_WIDTH_DATABITS-1:0]      UART_CONFIG_DATABITS     = r_current_settings[`UART_CONFIG_BITS_DATABITS];

    wire                                        w_rx_pin_syn;               // Rx pin input after being synchronized to this clock domain
    wire [DATA_WIDTH-1:0]                       w_data_frame;
    wire                                        w_bit_ce;                   // a ce signal for bit timed logic
    wire                                        w_sample_ce;                // a ce signal for sampling rx input state
    wire                                        w_sample_value = r_sample_buffer > (SAMPLE_COUNT / 2);// results from oversampling the Rx input
    wire [$clog2(DATA_WIDTH):0]                 w_rx_bit_number_SUM;
    wire                                        w_rx_bit_number_eq_DATABITS;
    wire                                        w_rx_bit_number_neq_DATABITS;
    wire                                        w_sample_buffer_SUM;
    wire                                        w_sample_buffer_neq_zero;
    wire                                        w_sample_buffer_neq_SAMPLE_COUNT;
    wire [3:0]                                  w_goto_next_state;
    wire [3:0]                                  w_goto_idle_state;

    initial begin
        uart_rx_ready   <= 0;
        uart_rx_error   <= 0;
        dataout         <= 0;
    end

    // submodules
    // Synchronize rx pin to prevent metastbality
    synchronizer #(.DEPTH_INPUT(0), .DEPTH_OUTPUT(2), .INIT(1'b1) ) 
        rx_pin_synchronizer( .clk_in(clk), .in(uart_rxpin), .clk_out(clk), .out(w_rx_pin_syn) );
    
    // Demultiplexer to store the incoming data
    dmux_lfmr #(.WIDTH(1), .OUTPUT_COUNT(DATA_WIDTH))
        dmux_next_data_bit(.clk(clk), .sel(r_rx_bit_number), .in(w_sample_value), .out(w_data_frame) );
    
    // Brad rate timer
    counter_with_strobe #( .WIDTH( COUNTER_WIDTH ), .LATENCY(COUNTER_LATENCY) ) 
        bit_counter( .clk( clk ), .rst( r_rx_state == RX_STATE_IDLE ), .enable( ce ),
            .reset_value( UART_CONFIG_DELAY_FRAMES ), .strobe( w_bit_ce ) );

    // Over sample timer
    counter_with_strobe #( .WIDTH( COUNTER_WIDTH - $clog2(SAMPLE_COUNT) ), .LATENCY(COUNTER_LATENCY) ) 
        sample_counter ( .clk( clk ), .rst( r_rx_state == RX_STATE_IDLE ), .enable( ce ),
            .reset_value( r_sample_clk_rst_value ), .strobe( w_sample_ce ) );

    // High speed adder to increment r_rx_bit_number
    math_lfmr #( .WIDTH($clog2(DATA_WIDTH)+1), .LATENCY(LATENCY) )
        r_rx_bit_number_math( .clk(clk), .rst(w_bit_ce), .I1(r_rx_bit_number), .I2(r_rx_bit_number_I2), .I3(UART_CONFIG_DATABITS), 
            .sum(w_rx_bit_number_SUM), .cmp_eq(w_rx_bit_number_eq_DATABITS), .cmp_neq(w_rx_bit_number_neq_DATABITS) );

    // r_sample_buffer
    always @( posedge clk ) begin
        if( w_sample_ce ) begin
            case ( w_rx_pin_syn )
                1'b0: begin
                    if( r_sample_buffer != 0 )
                        r_sample_buffer <= r_sample_buffer - 1'b1;
                end
                1'b1: begin
                    if( r_sample_buffer != SAMPLE_COUNT )
                        r_sample_buffer <= r_sample_buffer + 1'b1;
                end
            endcase
        end
    end

    // r_sample_clk_rst_value
    always @( posedge clk ) begin
        r_sample_clk_rst_value <= UART_CONFIG_DELAY_FRAMES / (SAMPLE_COUNT + 1'b1);
    end

    // r_current_settings
    always @( posedge clk ) begin
        if( r_rx_state == RX_STATE_IDLE ) begin
            r_current_settings <= settings;
        end else begin
            if( r_rx_state_changed ) begin
                if(r_rx_state == RX_STATE_PARITY) begin
                    r_current_settings[`UART_CONFIG_BITS_DATABITS] <= 
                        {{`UART_CONFIG_WIDTH_DATABITS-`UART_CONFIG_WIDTH_PARITY{1'b0}}, UART_CONFIG_PARITY == `UART_PARITY_NONE ? 1'b0 : 1'b1 };
                end
                if(r_rx_state == RX_STATE_STOP) begin
                    r_current_settings[`UART_CONFIG_BITS_DATABITS] <= 
                    {{`UART_CONFIG_WIDTH_DATABITS-2{1'b0}}, UART_CONFIG_STOPBITS == `UART_STOPBITS_1 ? 2'd1 : 2'd2 };
                end
            end
        end
    end

// r_rx_state
    assign w_goto_next_state =  {   &{r_rx_state == RX_STATE_IDLE,      ce,         !w_rx_pin_syn},                 // enter start state
                                    &{r_rx_state == RX_STATE_START,     w_bit_ce,   !w_sample_value},               // enter read state
                                    &{r_rx_state == RX_STATE_READ,      w_rx_bit_number_eq_DATABITS},               // enter parity state
                                    &{r_rx_state == RX_STATE_PARITY,    w_bit_ce || UART_CONFIG_PARITY == `UART_PARITY_NONE} };//enter stop state
    
    assign w_goto_idle_state =  {   &{r_rx_state == RX_STATE_START,     w_bit_ce,   w_sample_value},                // exit false start
                                    r_rx_state == RX_STATE_STOP,                                                    // exit when finished
                                    r_rx_state >= RX_NUMBER_OF_STATES,                                              // exit on invalid state
                                    rst };

    always @( posedge clk ) begin
        r_rx_state_changed <= 1'b0;
        if( |w_goto_idle_state ) begin
            r_rx_state <= RX_STATE_IDLE;
            r_rx_state_changed <= 1'b1;
        end else begin 
            if( |w_goto_next_state ) begin
                r_rx_state <= r_rx_state + 1'b1;
                r_rx_state_changed <= 1'b1;
            end
        end
    end

    // r_data_frame
    always @( posedge clk ) begin
        if( r_rx_state == RX_STATE_IDLE ) begin
            r_data_frame <= 0;
        end else begin
            if( r_rx_state == RX_STATE_READ && w_bit_ce )
                r_data_frame <= r_data_frame | w_data_frame;
        end
    end // always

    //////////////
    // r_rx_bit_number
    always @( posedge clk ) begin
        r_rx_bit_number <= w_rx_bit_number_SUM;
        r_rx_bit_number_I2 <= 0;
        if( w_bit_ce ) begin
            r_rx_bit_number_I2 <= 1'b1;
        end
        if( r_rx_state_changed ) begin
            r_rx_bit_number <= 0;
        end

    end // always
    /////////
    // r_rx_parity
    always @( posedge clk ) begin
        if( w_bit_ce ) begin
            if( w_sample_value )
                r_rx_parity <= ~r_rx_parity;
            if( r_rx_state == RX_STATE_START ) begin
                if( !w_sample_value ) begin
                    r_rx_parity <= 0;
                end
            end 
        end
    end // always

    // uart_rx_ready
    always @( posedge clk ) begin
        uart_rx_ready <= 0; // Toggle uart_rx_ready for 1 tick
        if( r_rx_state == RX_STATE_STOP ) begin
            uart_rx_ready <= 1;
        end
    end // always
////////////////
// uart_rx_error
    always @( posedge clk ) begin
        uart_rx_error <= 0; // Toggle uart_rx_error for 1 tick
        if( rst ) begin
            uart_rx_error <= 0;
        end else begin 
            if( ce ) begin
                if( r_rx_state == RX_STATE_STOP ) begin
                    if( w_rx_bit_number_eq_DATABITS ) begin
                        // r_rx_state <= RX_STATE_IDLE;
                        case ( UART_CONFIG_PARITY )
                            0: uart_rx_error <= 0;
                            1: uart_rx_error <= !r_rx_parity;
                            2: uart_rx_error <= r_rx_parity;
                            default: uart_rx_error <= 1'b1;
                        endcase
                    end
                end
            end // ce
        end // reset
    end // always

// dataout
    always @( posedge clk ) begin
        if( rst ) begin
            dataout <= 0;
        end else begin 
            if( r_rx_state == RX_STATE_STOP )
                dataout <= r_data_frame; 
        end
    end
endmodule