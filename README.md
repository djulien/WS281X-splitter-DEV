# WS281X-splitter
Verilog code for a WS281X string splitter and breakout box.

This code has 2 purposes:
1. split one long string of WS281X nodes into multiple shorter strings
2. show the last WS281X node (24 bits) as a breakout box

I am initially developing this for a Xilinx XC9572XL CPLD (72 macrocells) on a Guzunty board, but it might work on other CPLDs or FPGAs as well.

I chose Verilog over VHDL because I prefer the more C-like syntax and the pre-processor macros in particular.  This is my first CPLD/FPGA project, so the code probably isn't that great.

Current status:
- the main module (WS281X-Splitter) doesn't sim or synth yet
- the tester module is able to run sims of all the other components (controlled by #defines near the top)

/eof
