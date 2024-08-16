# FPGA-Toolbox
A collection of modules I have written while learning verilog.

## [counter.v](counter.v)
High speed, self pipelining counter with strobe output. Configurable retiming is based on the parameter 'latency', which specifies the maximum number of clock cycles plus one, that the output should take to be valid. <sub>[verified](verification/counter.sby)</sub>

## [dmux_pipeline.v](dmux_pipeline.v)
High speed demultiplexer with variable width and configurable retiming.
* dmux_pipeline - fully pipelined dmux module. Wrapper module, managing the pipelining of the sel structure.
* dmux_lfmr - linear feedback dmux module. Wrapper module, managing the pipelining of a multicycle demultiplexer.<sub>[verified](verification/dmux_lfmr.sby)</sub>
* dmux_combinational - Purely combinational dmux module, with automatic data structure and dmux chain construction.

## [math_pipeline.v](math_pipeline.v)
Building blocks for a fast pipelined ripple carry ALU with configurable width and retiming.
* math_lfmr - linear feedback math register. Wrapper module, managing the retiming of a single vector.
* math_combinational - Purely combinational ALU module, with automatic data structure and carry chain construction.
    * sum
    * sub
    * reducing AND
    * reducing OR
    * reducing XOR
    * equals
    * not equals

## [mux_pipeline.v](mux_pipeline.v)
Building blocks for a fast pipelined multiplexer with configurable width and retiming. Operating modes include 'Fixed latency' and 'Optimize for size'
* mux_pipeline - fully pipelined mux module. Wrapper module, managing the pipelining of the sel structure.
* mux_lfmr - linear feedback mux module. Wrapper module, managing the pipelining of a multicycle multiplexer. <sub>[verified](verification/mux_lfmr.sby)</sub>
* mux_combinational - Purely combinational mux module, with automatic data structure and mux chain construction.

## [pipeline_vector.v](pipeline_vector.v)
A module that fragments and organizes a vector for use in a pipeline. Structure diagrams included. 

## [recursion_iterators.vh](recursion_iterators.vh)
Functions used for building pipeline and retiming data structures. Structure diagrams included.
* Tail Recursion - useful for running a magnitude comparison while data is in the pipeline.
* Nary Recursion - useful for large reduction operations with fixed latency
* Nary Recursion Optimized - useful for large reduction operations with varable latency and reduced register usage

## [synchronizer.v](synchronizer.v)
A dff chain for external input synchronization. Parameters for input/output chain size, and both input
and output clocks.

## [uart.v](uart.v)
A Universal Asynchronous Receiver Transmitter with configurable retiming.
* [uart_include.vh](uart_include.vh) - Configuration parameters for the uart objects.
* [uart_rx.v](uart_rx.v) - Uart receiver module.
* [uart_tx.v](uart_tx.v) - Uart transmitter module.
