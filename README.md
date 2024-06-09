# FPGA-Toolbox
A collection of modules I have written while learning verilog.

## alu.v
A Simulation model for Gowin GW1NR-9 ALU primitives. along with 2 helper modules
alu_chain - this module links together 'width' number of alu primitives into a functional unit
alu_pipeline - this module is the same as 'alu_chain' except the .cout() & .cin() are exposed for pipelining 

## counter.v
High speed, self pipelining counter with strobe output. This is a second attempt at implementation of a variable width counter with strobe output. automatic pipelining is based
on the parameter 'latency', which specifies the maximum number of clock cycles+1 the output should take to be valid.

## synchronizer.v
A dff chain for external input synchronization. has parameters for input/output chain size, and both clocks.
