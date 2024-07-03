# FPGA-Toolbox
A collection of modules I have written while learning verilog.

## alu.v
A Simulation model for Gowin GW1NR-9 ALU primitives. along with 2 helper modules<br>
alu_chain - this module links together 'width' number of alu primitives into a functional unit<br<
alu_pipeline - this module is the same as 'alu_chain' except the .cout() & .cin() are exposed for pipelining 

## counter.v
High speed, self pipelining counter with strobe output. Automatic pipelining is based on the parameter 'latency', which specifies the maximum number of clock cycles plus one, that the output should take to be
valid.

## math_piplined.v
Building blocks for a fast pipelined ripple carry ALU with configurable width and latency.<br>
math_lfmr - linear feedback math register. Wrapper module, managing the pipelining of a single vector.<br>
math_combinational - Purely combinational ALU module, with automatic data structure configuration.


## recursion_iterators.v
Functions used for building pipeline data structures. Structure diagrams included.<br>
Tail Recursion - useful for running a magnitude comparison while data is in the pipeline.<br>
Nary Recursion - useful for large reduction operations

## synchronizer.v
A dff chain for external input synchronization. Parameters for input/output chain size, and both input
and output clocks.
