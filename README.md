# FPGA-Toolbox
A collection of modules I have written while learning verilog.

## alu.v
A Simulation model for Gowin GW1NR-9 ALU primitives. along with 2 helper modules
alu_chain - this module links together 'width' number of alu primitives into a functional unit
alu_pipeline - this module is the same as 'alu_chain' except the .cout() & .cin() are exposed for pipelining 

## counter.v - work in progress. 
High speed, self pipelining counter with strobe output. This is a second attempt at implementation of a variable width counter with strobe output. automatic pipelining is based
on the parameter 'latency', which specifies the maximum number of clock cycles+1 the output should take to be valid.

## counter.v_backup
This is a simple counter with strobe output, formally verified. using 3 different implementation. 'CWS_TYPE_SIMPLE' uses less resources, but is the slowest. 'CWS_TYPE_PRIMITIVE' is functionaly equivalent to the simple counter, put uses Gowin alu primitives. 'CWS_TYPE_PIPELINE' is a faster, but not fully functional implementation.

