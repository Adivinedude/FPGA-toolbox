////////////////////////////////////////////////////////////////////////////////
//
// Filename: uart.v
//
// Project:	Universal Asynchronous Receiver Transmitter
//
// Purpose:	a fast, configurable, over engineered uart controller. 
// (+210MHz Fmax on the tang nano 9k)
//
// Creator:	Ronald Rainwater
// Data: 2024-7-21
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

// Top Down View
//     uart \
//         - uart_config
//         \ uart_rx_fifo
//             - uart_rx
//         \ uart_tx_fifo
//             - uart_tx
// This module ties together the rx and tx modules with 2 FIFO buffers for sending and receiving
// data using the uart protocol.
// ToDo: 
//  1) implement flow control
//  2) implement half duplex mode


`default_nettype none
`include "toolbox/uart_include.vh"
module uart
#(
    parameter   COUNTER_WIDTH   = `UART_CONFIG_WIDTH_DELAYFRAMES,
    parameter   DATA_WIDTH      = `UART_CONFIG_MAX_DATA,
    parameter   RX_BUF_SIZE     = `UART_CONFIG_FIFO_DEPTH,
    parameter   TX_BUF_SIZE     = `UART_CONFIG_FIFO_DEPTH,
    parameter   RX_CONFIG_INIT  = `UART_CONFIG_INITIAL_SETTING,
    parameter   TX_CONFIG_INIT  = `UART_CONFIG_INITIAL_SETTING,
    parameter   LATENCY         = 0
)
(
    // pins
    input   wire                        clk,
    input   wire                        ce,
    input   wire                        rst,
    input   wire                        rx_pin,
    output  wire                        tx_pin,
    // rx ports
    output  wire    [DATA_WIDTH - 1:0]  rx_data,    // Data Out
    input   wire                        rx_read,    // Word has been read, Pulse high to read the next word
    output  wire                        rx_empty,   // Rx buffer is empty on HIGH (when low, rxData is valid)
    output  wire                        rx_almost_empty,
    output  wire                        rx_full,    // Rx buffer is full on HIGH
    output  wire                        rx_almost_full,
    // tx ports
    input   wire    [DATA_WIDTH - 1:0]  tx_data,    // Data In
    input   wire                        tx_write,   // Data ready to store, Pulse high write the next word
    output  wire                        tx_empty,   // Tx buffer is empty on HIGH
    output  wire                        tx_almost_empty,
    output  wire                        tx_full,    // Rx buffer is full on HIGH (attempts to write data will fail)
    output  wire                        tx_almost_full,
    // config ports
    input   wire [`UART_CONFIG_WIDTH-1:0] config_value, // Configuration Value
    input   wire                        tx_config_valid,
    input   wire                        rx_config_valid
);
    reg [`UART_CONFIG_WIDTH-1:0] tx_config = TX_CONFIG_INIT; 
    reg [`UART_CONFIG_WIDTH-1:0] rx_config = RX_CONFIG_INIT;
    always @( posedge clk ) begin
        if( rst ) begin
            tx_config <= TX_CONFIG_INIT;
            rx_config <= RX_CONFIG_INIT;
        end else begin
            if( tx_config_valid )
                tx_config <= config_value;
            if( rx_config_valid )
                rx_config <= config_value;
        end
    end

// Wires to connect to the RX module
    wire    [DATA_WIDTH-1:0]    uart_rx_dataOut;
    wire                        uart_rx_ready;
    wire                        uart_rx_error;
    wire                        uart_rx_write_to_fifo;
    wire                        uart_rx_busy;

// Rx Module
    uart_rx #(
        .COUNTER_WIDTH( COUNTER_WIDTH ),
        .DATA_WIDTH(    DATA_WIDTH ),
        .LATENCY(       LATENCY )
    ) rx(
        .clk(           clk ),
        .ce(            ce ),
        .uart_rxpin(    rx_pin ),
        .dataout(       uart_rx_dataOut ),
        .uart_rx_ready( uart_rx_ready ),
        .uart_rx_error( uart_rx_error ),
        .uart_rx_busy(  uart_rx_busy ),
        .rst(           rst ),
        .settings(      rx_config )
    );
// rx memory
    fifo #(
        .WIDTH( DATA_WIDTH ),
        .DEPTH( RX_BUF_SIZE )
    ) 
    rxBuffer (
        .clk(           clk ),
        .rst(           rst ),
        .re(            rx_read ),
        .we(            uart_rx_ready ),
        .dataIn(        uart_rx_dataOut ),
        .dataOut(       rx_data ),
        .full_flag(     rx_full ),
        .almost_full(   rx_almost_full),
        .empty_flag(    rx_empty ),
        .almost_empty(  rx_almost_empty )
    );    
    assign uart_rx_write_to_fifo = uart_rx_ready && !uart_rx_error;

// Wires to connect Tx Module
    wire                        uart_tx_txReady;
    reg                         send_tx = 0;
    wire    [DATA_WIDTH-1:0]    w_uart_tx_dataIn;
// Tx Module
    uart_tx #(  
        .COUNTER_WIDTH( COUNTER_WIDTH ),
        .DATA_WIDTH(    DATA_WIDTH ),
        .LATENCY(       LATENCY )
    ) tx(
        .clk(                       clk ),
        .ce(                        ce ),
        .uart_txpin(                tx_pin ),
        .uart_tx_busy(),
        .datain(                    w_uart_tx_dataIn ),
        .send_tx(                   send_tx ),
        .uart_tx_ready(             uart_tx_txReady ),
        .rst(                       rst ),
        .settings(                  tx_config )
    );
// tx memory
    fifo #(
        .WIDTH( DATA_WIDTH ),
        .DEPTH( TX_BUF_SIZE )
    )
    txBuffer(
        .clk(           clk ),
        .rst(           rst ),
        .re(            send_tx),
        .we(            tx_write ),
        .dataIn(        tx_data ),
        .dataOut(       w_uart_tx_dataIn ),
        .full_flag(     tx_full ),
        .almost_full(   tx_almost_full),
        .empty_flag(    tx_empty ),
        .almost_empty(  tx_almost_empty )
    );

    // Send data stored in tx buffer when its available and tx is ready
    reg [2:0] r_tx_empty = 0; // timing fix
    reg r_tx_ready = 0;
    reg r_tx_lockout = 0;

    reg [2:0] r_rx_busy = 0;
    always @( posedge clk ) begin
        r_tx_empty <= { tx_empty, r_tx_empty[1+:2]}; // timing fix
        r_rx_busy <= {uart_rx_busy, r_rx_busy[1+:2]};
        r_tx_ready <= uart_tx_txReady;
        send_tx  <= 0;


        if( r_tx_ready && !r_tx_empty[0] && ce  && !r_tx_lockout ) begin
            send_tx <= 1;
            r_tx_lockout <= 1;
        end
        if( r_tx_lockout && !r_tx_ready ) begin
            if( (uart_rx_busy == 0) || (tx_config[`UART_CONFIG_BITS_MODE] == `UART_MODE_FULL_DUPLEX) )
                r_tx_lockout <= 0;
        end
    end
endmodule
