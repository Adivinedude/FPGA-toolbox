////////////////////////////////////////////////////////////////////////////////
//
// Filename:	uart_include.v
//
// Project:	uart_include 
//
// Purpose:	configurations for the uart project
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
`default_nettype none
`ifndef UART_INCLUDE_V
    `define UART_INCLUDE_V
// Settings
    //Mode
    `define UART_MODE_FULL_DUPLEX           1'b0
    `define UART_MODE_HALF_DUPLEX           1'b1
    //Parity bit
    `define UART_PARITY_NONE                2'b00
    `define UART_PARITY_ODD                 2'b01
    `define UART_PARITY_EVEN                2'b10
    `define UART_PARITY_UNUSED              2'b11
    //Stop bit
    `define UART_STOPBITS_1                 1'b0
    `define UART_STOPBITS_2                 1'b1
    //Flow control
    `define UART_FLOWCTRL_NONE              2'b00
    `define UART_FLOWCTRL_RTS               2'b01
    `define UART_FLOWCTRL_CTS               2'b10
    `define UART_FLOWCTRL_RTS_CTS           2'b11

    // maximum parameters    
    `define UART_CONFIG_FIFO_DEPTH          64
    `define UART_CONFIG_MAX_DATA            16

    // Setting register widths
    `define UART_CONFIG_WIDTH               25

    // Setting part width
    `define UART_CONFIG_WIDTH_MODE          1
    `define UART_CONFIG_WIDTH_DATABITS      4
    `define UART_CONFIG_WIDTH_PARITY        2
    `define UART_CONFIG_WIDTH_STOPBITS      1
    `define UART_CONFIG_WIDTH_FLOWCTRL      2
    `define UART_CONFIG_WIDTH_DELAYFRAMES   15

    // single register configuration for modules, define parts
    `define UART_CONFIG_BITS_MODE           24
    `define UART_CONFIG_BITS_DATABITS       23:20
    `define UART_CONFIG_BITS_PARITY         19:18
    `define UART_CONFIG_BITS_STOPBITS       17
    `define UART_CONFIG_BITS_FLOWCTRL       16:15
    `define UART_CONFIG_BITS_DELAYFRAMES    14:0
    // default setup fullduplex 8n1  9600
    `define UART_CONFIG_INITIAL_SETTING {   `UART_MODE_FULL_DUPLEX, \
                                            `UART_CONFIG_WIDTH_DATABITS'd8,\
                                            `UART_PARITY_NONE,      \
                                            `UART_STOPBITS_1,       \
                                            `UART_FLOWCTRL_NONE,    \
                                            `UART_CONFIG_WIDTH_DELAYFRAMES'd2604 }
`endif