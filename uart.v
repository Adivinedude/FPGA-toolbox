/*
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
*/

`default_nettype none
`include "uart/uart_include.v"
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
    reg     [DATA_WIDTH-1:0]    r_uart_tx_dataIn;
    reg                         r_uart_tx_dataIn_valid = 0;
    always @( posedge clk ) begin
        r_uart_tx_dataIn <= w_uart_tx_dataIn;
        r_uart_tx_dataIn_valid <= send_tx;
    end
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
        .datain(                    r_uart_tx_dataIn ),
        .send_tx(                   r_uart_tx_dataIn_valid ),
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
    reg r_tx_empty = 0;
    always @( posedge clk ) begin
        r_tx_empty <= tx_empty;
        if( send_tx ) begin
            send_tx  <= 0;
        end else if( uart_tx_txReady && ~r_tx_empty ) begin
            send_tx <= 1;
        end
    end
endmodule