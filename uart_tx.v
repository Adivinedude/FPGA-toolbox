////////////////////////////////////////////////////////////////////////////////
//
// Filename:	uart_tx.v
//
// Project:	uart_tx 
//
// Purpose:	a fast, configurable universal asynchronous transmitter
//
// Creator:	Ronald Rainwater
// Data: 2024-7-19
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

// System Summary
// UART tx module
// Order of Operation.
// 1) When 'send_tx(HIGH)', 'datain' and 'start bit' are loaded into the 'r_tx_data' vector. 'send_tx' will be ignored for the remaining of the transmission
// 2) 'r_tx_data' feeds a multiplexer, providing the 'w_next_tx_data' based on the current 'r_tx_bit_number'
// 3) Another multiplexer fed with 'stop', 'r_parity', 'w_next_tx_data', and 'idle' bits feeds into 'r_tx_pin' based on 'r_tx_state' 
// 4) 'r_tx_data' parity is calculated at every bit interval and stored in 'r_parity'
// 5) GoTo step #1.

                                                  
`default_nettype none
`include "uart_include.vh"

module uart_tx
#(
    parameter COUNTER_WIDTH       = `UART_CONFIG_WIDTH_DELAYFRAMES,
    parameter DATA_WIDTH          = `UART_CONFIG_MAX_DATA,
    parameter LATENCY             = 0, 
    parameter END_EARLY           = 2
)
(
    input   wire                    clk,            // input clock
    input   wire                    ce,
    input   wire                    rst,
    input   wire [DATA_WIDTH-1:0]   datain,         // Data to send
    input   wire                    send_tx,        // Trigger to start sending data
    input   wire [`UART_CONFIG_WIDTH-1:0] settings,     
    output  wire                    uart_tx_ready,  // flag, HIGH when ready for new data. LOW when sending
    output  wire                    uart_txpin,     // output tx pin
    output  wire                    uart_tx_busy
);
    // States
    localparam TX_STATE_IDLE    = 0;
    localparam TX_STATE_DATA    = 1;
    localparam TX_STATE_PARITY  = 2;
    localparam TX_STATE_STOP    = 3;
    localparam TX_NUMBER_OF_STATES = 4;

    // Registers
    reg [$clog2(TX_NUMBER_OF_STATES)-1:0]       r_tx_state          = TX_STATE_IDLE;
    reg                                         r_tx_state_changed  = 0;
    reg [1:0]                                   r_tx_pin            = 2'b11;
    reg [DATA_WIDTH-1:0]                        r_tx_data           = 0;
    reg [`UART_CONFIG_WIDTH-1:0]                r_current_settings  = 0;
    reg [$clog2(DATA_WIDTH):0]                  r_tx_bit_number     = 0;
    reg [$clog2(DATA_WIDTH):0]                  r_tx_bit_number_I2  = 0;
    reg                                         r_parity            = 0;

    // config settings - see 'uart_include.v' for details.
    wire [`UART_CONFIG_WIDTH_DELAYFRAMES-1:0]   UART_CONFIG_DELAY_FRAMES = r_current_settings[`UART_CONFIG_BITS_DELAYFRAMES];
    wire [`UART_CONFIG_WIDTH_STOPBITS-1:0]      UART_CONFIG_STOPBITS     = r_current_settings[`UART_CONFIG_BITS_STOPBITS];
    wire [`UART_CONFIG_WIDTH_PARITY-1:0]        UART_CONFIG_PARITY       = r_current_settings[`UART_CONFIG_BITS_PARITY];
    wire [`UART_CONFIG_WIDTH_DATABITS-1:0]      UART_CONFIG_DATABITS     = r_current_settings[`UART_CONFIG_BITS_DATABITS];

    // Wires
    wire                                        w_start_tx_procedure;
    wire                                        w_bit_ce;
    wire [$clog2(DATA_WIDTH):0]                 w_tx_bit_number_SUM;
    wire                                        w_tx_bit_number_eq_DATABITS;  
    wire                                        w_next_tx_data;
    wire                                        w_next_tx_pin;
    wire [3:0]                                  w_mux_next_tx_pin_in;
    wire [2:0]                                  w_goto_next_state;
    wire [1:0]                                  w_goto_idle_state;

    // assignments
    assign w_start_tx_procedure = r_tx_state == TX_STATE_IDLE && send_tx;
    assign uart_tx_busy         = r_tx_state != 0 || rst;
    assign uart_tx_ready        = r_tx_state == 0 && !rst;
    assign uart_txpin           = r_tx_pin[1];

    // wire     w_txParity_bit  = UART_CONFIG_PARITY == `UART_PARITY_EVEN ?  w_parity_xor_gate
    //              : UART_CONFIG_PARITY == `UART_PARITY_ODD  ? ~w_parity_xor_gate 
    //              : 1'b1;              // `UART_PARITY_NONE
    // submodules
    //  select data based on tx_bit_number
    mux_lfmr #(.WIDTH(1), .INPUT_COUNT(DATA_WIDTH+1), .LATENCY(LATENCY) ) 
        mux_next_data_bit( .clk(clk), .sel(r_tx_bit_number), .in({r_tx_data, 1'b0}), .out(w_next_tx_data) );

    //  select output based on tx_state
    mux_lfmr #(.WIDTH(1), .INPUT_COUNT(TX_NUMBER_OF_STATES)) 
        mux_next_tx_pin(.clk(clk), .sel(r_tx_state), .in({1'b1, r_parity, w_next_tx_data, 1'b1}), .out(w_next_tx_pin) );

    // High speed adder to increment tx_bit_number
    math_lfmr #( .WIDTH($clog2(DATA_WIDTH)+1), .LATENCY(LATENCY) )
        math_tx_bit_number( .clk(clk), .rst(1'b0), .I1(r_tx_bit_number), .I2(r_tx_bit_number_I2), .I3(UART_CONFIG_DATABITS),
            .sum(w_tx_bit_number_SUM), .sub(), .gate_and(), .gate_or(), .gate_xor(), .cmp_eq(w_tx_bit_number_eq_DATABITS), .cmp_neq() );

    // Brad rate timer
    counter_with_strobe #( .WIDTH( COUNTER_WIDTH ), .LATENCY( LATENCY ) ) 
        bit_counter( .clk( clk ), .rst( r_tx_state == 0 ), .enable( ce ), .reset_value( UART_CONFIG_DELAY_FRAMES ), .strobe( w_bit_ce ) );
    
    // r_tx_state
    reg [2:0] r_goto_next_state = 0;
    assign w_goto_next_state    = { w_start_tx_procedure,
                                    w_bit_ce && w_tx_bit_number_eq_DATABITS,
                                    (r_tx_state == TX_STATE_PARITY && UART_CONFIG_PARITY == `UART_PARITY_NONE) ? 1'b1 : 1'b0 };
    reg [1:0] r_goto_idle_state = 0;
    assign w_goto_idle_state    = { rst,
                                    r_tx_state >= TX_NUMBER_OF_STATES };

    always @( posedge clk ) begin
        r_tx_state_changed <= 0;
        r_goto_next_state <= w_goto_next_state;
        r_goto_idle_state <= w_goto_idle_state;

        if( |r_goto_next_state ) begin
            r_tx_state <= r_tx_state + 1'b1;
            r_tx_state_changed <= 1'b1;
            r_goto_next_state <= 0;
            r_goto_idle_state <= 0;
        end
        if( |r_goto_idle_state ) begin
            r_tx_state <= TX_STATE_IDLE;
        end
    end    

    // r_tx_bit_number
    always @( posedge clk ) begin
        r_tx_bit_number_I2  <= { {$clog2(DATA_WIDTH)-1{1'b0}}, w_bit_ce };
        r_tx_bit_number     <= w_tx_bit_number_SUM;
        if( r_tx_state == TX_STATE_IDLE || r_tx_state_changed ) begin
            r_tx_bit_number <= 0;
        end
    end

    // r_tx_data    item 1:
    always @( posedge clk ) begin
        if( rst ) begin
            r_tx_data <= 0;
        end else begin 
            if( w_start_tx_procedure )
                r_tx_data <= datain;
        end
    end

    // r_tx_pin     item 2, 3:
    always @( posedge clk ) begin
        r_tx_pin[1] <= r_tx_pin[0];
        if( ce )
            r_tx_pin[0] <= w_next_tx_pin;
    end

    // r_parity     item 4:
    always @( posedge clk ) begin
        if( w_start_tx_procedure ) begin
            r_parity <= UART_CONFIG_PARITY == `UART_PARITY_ODD ? 1'b1 : 1'b0;
        end if( r_tx_state == TX_STATE_DATA && w_bit_ce ) begin
            if( w_next_tx_pin )
                r_parity <= r_parity + 1'b1;
        end
    end

    // r_current_settings
    always @( posedge clk ) begin
        if( r_tx_state == TX_STATE_IDLE ) begin
            r_current_settings <= settings;
        end
        case( r_tx_state )
            TX_STATE_PARITY:
                r_current_settings[`UART_CONFIG_BITS_DATABITS] <= `UART_CONFIG_WIDTH_DATABITS'd1;
            TX_STATE_STOP:
                r_current_settings[`UART_CONFIG_BITS_DATABITS] 
                    <= { {`UART_CONFIG_WIDTH_DATABITS - `UART_CONFIG_WIDTH_STOPBITS{1'b0}}, UART_CONFIG_STOPBITS};
        endcase
    end  

 ///////////////////////////////////////////////////////////////////////////////
// formal verification starts here
    `ifdef FORMAL
        `define ASSERT assert
        `ifdef FORMAL_UART_TX
            `define ASSUME assume
        `else
            `define ASSUME assert
        `endif
    ////////////////
    // past_valid //
    ////////////////
        reg unsigned [1:0] past_valid_counter = 0;
        wire past_valid = past_valid_counter > 0;
        always @( posedge clk ) past_valid_counter = (past_valid) ? past_valid_counter : past_valid_counter + 1;
        // test this as a black box circuit.
    /////////
    // rst //
    /////////
        always @( posedge clk ) `ASSUME( past_valid || rst );
    ////////
    // ce //
    ////////
        reg unsigned [$clog2(LATENCY):0] ce_counter = 0;
        wire    ce_valid = (ce_counter >= LATENCY);

        always @( posedge clk ) begin
            ce_counter = (!past_valid || rst || ce) 
                            ? 0 
                            : ce_valid 
                                ? ce_counter 
                                : ce_counter + 1;
            if( !ce_valid ) 
                `ASSUME( !ce );
        end

    ////////////////
    // uart_txpin //
    ////////////////
        // always @( posedge clk )
        //     `ASSUME($stable(uart_txpin) || ce );
    //////////////
    // settings //
    //////////////
        // ensure the settings are within a valid range
        always @( posedge clk ) 
            `ASSUME( 
                &{  settings[`UART_CONFIG_BITS_DELAYFRAMES] >= 4,              // brad rate - limit for testing.
                                                                                // stop bits - no action required.
                    settings[`UART_CONFIG_BITS_PARITY] != `UART_PARITY_UNUSED,  // parity bit - valid
                    settings[`UART_CONFIG_BITS_DATABITS] >= 'd6 && settings[`UART_CONFIG_BITS_DATABITS] <= DATA_WIDTH, //word width
                    $stable(settings) || rst
                }
            );
    //////////////////////
    // internal signals //
    //////////////////////
        // check FSM for invalid state
        always @( posedge clk )
            `ASSERT( r_tx_state < TX_NUMBER_OF_STATES );

        // ensure r_rx_bit_number is in bounds
        always @( posedge clk )
            `ASSUME( r_tx_bit_number < DATA_WIDTH );
   
    ///////////////////////
    // cover all signals //
    ///////////////////////
        `ifdef FORMAL_UART_TX
            always @( posedge clk ) cover_past_valid:       cover( past_valid );
            always @( posedge clk ) cover_ce:               cover( ce );
            always @( posedge clk ) cover_tx_ready_high:    cover(  uart_tx_ready );
            always @( posedge clk ) cover_tx_ready_low:     cover( !uart_tx_ready );
            always @( posedge clk ) cover_uart_txpin_low:   cover( !uart_txpin );
            always @( posedge clk ) cover_uart_txpin_high:  cover(  uart_txpin );
            always @( posedge clk ) cover_uart_tx_busy:     cover(  uart_tx_busy );
        `endif
`endif
endmodule