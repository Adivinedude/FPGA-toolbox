# FPGA-Toolbox
A collection of modules I have written while learning verilog.

## [alu.v](alu.v)
A Simulation model for Gowin GW1NR-9 ALU primitives. along with 2 helper modules
* alu_chain - this module links together 'width' number of alu primitives into a functional unit
* alu_pipeline - this module is the same as 'alu_chain' except the .cout() & .cin() are exposed for pipelining 

## [counter.v](counter.v)
High speed, self pipelining counter with strobe output. Automatic pipelining is based on the parameter 'latency', which specifies the maximum number of clock cycles plus one, that the output should take to be
valid.

## [math_pipelined.v](math_pipelined.v)
Building blocks for a fast pipelined ripple carry ALU with configurable width and latency.
* math_lfmr - linear feedback math register. Wrapper module, managing the pipelining of a single vector.
* math_combinational - Purely combinational ALU module, with automatic data structure and carry chain construction.


## [recursion_iterators.v](recursion_iterators.v)
Functions used for building pipeline data structures. Structure diagrams included.
* Tail Recursion - useful for running a magnitude comparison while data is in the pipeline.
* Nary Recursion - useful for large reduction operations

## [synchronizer.v](synchronizer.v)
A dff chain for external input synchronization. Parameters for input/output chain size, and both input
and output clocks.
