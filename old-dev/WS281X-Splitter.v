`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    10:03:29 06/18/2016 
// Design Name: 
// Module Name:    ws281x-breakout 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////

//notes about clock sync + edge detect:
// https://www.doulos.com/knowhow/fpga/synchronisation/
// http://stackoverflow.com/questions/8413661/proper-way-for-signal-edge-detection-in-verilog
// http://stackoverflow.com/questions/28658363/vhdl-equivalent-for-verilog-posedge-clk
// http://electronics.stackexchange.com/questions/26502/verilog-check-for-two-negedges-in-always-block
// https://geekwentfreak-raviteja.rhcloud.com/blog/2010/10/07/designing-asynchronous-and-synchronous-reset-in-verilog/
// http://www.xilinx.com/support/documentation/university/ISE-Teaching/HDL-Design/14x/Nexys3/Verilog/docs-pdf/lab5.pdf
// http://web.mit.edu/6.111/www/f2007/handouts/L04.pdf

//`define CLK_FREQ  (50 `MHz) //expected CPLD clock frequency (determines other timing values)
//`define TICKS(sec)  (sec * `CLK_FREQ) //.5 usec == 25, .6 usec == 30, 1 usec == 50
`define TICKS(nsec)  (nsec / 20)

//`define MHz  * 1000000
`define MSEC  * 1000000 // / 1000
`define USEC  * 1000 // / 1000000
`define NSEC  * 1 // / 1000000000


module WS281X_Splitter (Node, /*Valid, Sync,*/ BranchOut, Din, Clock); //#(parameter CLK_FREQ = 50 `MHz)(
//XC9572XL PLCC44 has 34 I/O pins available:
// Din + Clock + Node:24 + Valid + Sync = 28, leaving only 6 for parallel branch strings
// (we could have 8 if we drop the Valid and Sync signals)
    parameter NUM_BR = 8; //16 //max #branches to split out
    parameter WANT_VALID = 1; //turn off to get an extra WS281X branch
    parameter WANT_SYNC = 1; //turn off to get an extra WS281X branch
    parameter ESC_NEXT_BRANCH = 24'h010203; //escape code to step to next output branch

    input wire Din; //WS281X data stream
    input wire Clock; //CPLD clock

    output wire [23:0] Node; //last-seen node value
    /*output*/ wire Valid; //Node bits are valid
    output wire [NUM_BR-1:0] BranchOut; //parallel strings after split
//`ifdef WANT_SYNC
    /*output*/ reg Sync; //WS281X refresh signal; NOTE: a FF is used to reduce amount of comparisons on timer outputs
//`endif

`include "NumBits.vh"

//timing control:
//50 MHz clock is free-running and drives a 12-bit counter (allows ~82 usec before wrap)
//leading edge of incoming data bit resets this counter to generate 20 nsec time slices within data bit (or a timeout if data stops arriving):
//  @slice 0 (T + 0), data bit starts arriving
//  @slice 25 (T + 0.5 usec), node recovery sentinel bit is preloaded
//  @slice 30 (T + 0.6 usec), data bit is recovered
//  @slice 50 (T + 1.0 usec), next serial branch is selected
//  @slice 62.5 (T + 1.25 usec), next data bit should start arriving (counter resets at this point)
//  @slice 2500 (T + 50 usec), sync pulse begins (if no further data bit arrives)
//  @slice 2505 (T + 50.1 usec), sync pulse ends
    wire [12-1:0] timer_count;
   	Counter#(.WIDTH(12)) timer(
		.Q(timer_count), 
		.Clock(Clock), 
		.Reset(Din)
	);
//    assign recover_bit = (delay_count == 30); //600 `NSEC / `CLK_PERIOD); //30 @50 MHz
//    assign sync_begin = (delay_count >= 2500); //50 `USEC / `CLK_PERIOD); //2500 @50 MHz
//    assign sync_end = (delay_count <= 2501); //(50 `USEC + `SYNC_PULSE) / `CLK_PERIOD); //250X @50 MHz
//    assign Sync = sync_begin && sync_end;
// TIMER(0.5 usec) = .5 / .020 = 25
//CAUTION: use bit-wise & here, not &&
//CAUTION: each == generates a compare on timer output lines
//kludge: Verilog doesn't seem to support floating point, so use fractions instead
    wire preset_clk = (timer_count == `TICKS(/*0.5*/ 1 `USEC / 2)) & Clock; //20 when to preload shift reg with sentinel value
    wire recover_bit_clk = (timer_count == `TICKS(/*0.6*/ 3 `USEC / 5)) & Clock; //30 when to recover incoming data bit
    wire branch_sel_clk = (timer_count == `TICKS(/*1.0*/ 1 `USEC)) & Clock; //50 when to advance to next branch (Data must be low to avoid fragments)
    wire sync_begin_clk = (timer_count == `TICKS(50 `USEC)) & Clock; //2500 start of sync pulse (WS281X latch signal)
    wire sync_end_clk = (timer_count == `TICKS(/*50.1*/ 50 `USEC + 100 `NSEC)) & Clock; //2505 end of sync pulse
//    assign Sync = (timer_count == 2500) | (timer_count == 2501) | (timer_count == 2502) | (timer_count == 2503) | (timer_count == 2504) | (timer_count == 2505); //(timer_count >= 2500) & (timer_count <= 2505);
//`define SYNC_PULSE  (25 `NSEC) //desired width of sync (reset) signal
//`define CLK_PERIOD  (1 / `CLK_FREQ) //@50 MHz = 20 nsec
//    always @(Clock) begin
//    end
//    assign BranchOut[0] = preset_clk;
//    assign BranchOut[1] = recover_bit_clk;
//    assign BranchOut[2] = branch_sel_clk;
//    assign BranchOut[3] = sync_begin_clk;
//    assign BranchOut[4] = (timer_count >= 2500);
//    assign BranchOut[5] = (timer_count <= 2505);
//    assign Node[11:0] = timer_count;
//    wire timer_is_25 = (timer_count == 25); //!timer_count[11:5] & timer_count[4] & timer_count[3] & !timer_count[2] & !timer_count[1] & timer_count[0]; //0x19
//    wire timer_is_30 = (timer_count == 30); //!timer_count[11:5] & timer_count[4] & timer_count[3] & timer_count[2] & timer_count[1] & !timer_count[0]; //0x1E
//    wire timer_is_50 = (timer_count == 50); //!timer_count[11:6] & timer_count[5] & timer_count[4] & !timer_count[3:2] & timer_count[1] & !timer_count[0]; //0x32
//    wire timer_is_2500s = timer_count[11] & !timer_count[10:9] & timer_count[8] & timer_count[7] & timer_count[6] & !timer_count[5:4]; //0x9CX
//    wire timer_is_2500 = (timer_count == 2500); //timer_is_2500s & !timer_count[3] & timer_count[2] & !timer_count[1:0]; //0x9C4
//    wire timer_is_2501 = (timer_count == 2501); //timer_is_2500s & !timer_count[3] & timer_count[2] & !timer_count[1] & !timer_count[0]; //0x9C5
//    wire timer_is_2502 = (timer_count == 2502); //timer_is_2500s & !timer_count[3] & timer_count[2] & timer_count[1] & !timer_count[0]; //0x9C6
//    wire timer_is_2503 = (timer_count == 2503); //timer_is_2500s & !timer_count[3] & timer_count[2] & timer_count[1] & timer_count[0]; //0x9C7
//    wire timer_is_2504 = (timer_count == 2504); //timer_is_2500s & timer_count[3] & !timer_count[2:0]; //0x9C8
//    wire timer_is_2505 = (timer_count == 2505); //timer_is_2500s & timer_count[3] & !timer_count[2:1] & timer_count[0]; //0x9C9

//    assign preset_clk = timer_is_25 & Clock; 
//    assign recover_bit_clk = timer_is_30 & Clock;
//    assign branch_sel_clk = timer_is_50 & Clock;
//    assign sync_begin_clk = timer_is_2500 & Clock;
//    assign sync_end_clk = timer_is_2505 & Clock;
//    assign Sync = timer_is_2500 | timer_is_2501 | timer_is_2502 | timer_is_2503 | timer_is_2504 | timer_is_2505;

//    always @(sync_begin_clk) Sync = 1;
//    always @(sync_end_clk) Sync = 0;
    always @(posedge sync_begin_clk, posedge sync_end_clk)
        if (sync_begin_clk) Sync = 1;
        else Sync = 0;

//`ifdef EXCLUDE
//collect in-coming WS281X node bits (serial in, parallel out):
//    wire node_valid; //RGB value recovered
//    wire node_clock; //node shift clock
//    wire node_init; //setup for next node value
//    wire next_branch; //redirect to next branch
    wire [24-1:0] preset_bits = 24'h000001; //preload end-of-node sentinel bit
//    wire [23:0] node_value;
   	ShiftReg#(.WIDTH(24)) node(
        .Dp(preset_bits),
        .Ds(Din),
		.Q(Node), //node_value), 
        .Carry(Valid), //node_valid),
		.Clock(recover_bit_clk), 
		.Preset(preset_clk)
	);
//    assign Node = node_value;
//    assign Valid = node_valid;
//    assign node_clock = (recover_bit == 1) && (Clock == 1);
//    assign node_init = (recover_bit == 1) && (Clock == 1) && (Valid == 1); //node_valid == 1);
    wire next_branch_clk = (Node /*node_value*/ == ESC_NEXT_BRANCH) & Valid & branch_sel_clk; //node_valid == 1);


//redirect incoming data to a series branch string:
    initial begin
        $display("branch sel is %d bits wide", `NumBits(NUM_BR - 1));
    end
    wire [`NumBits(NUM_BR - 1)-1:0] branch_sel; //which branch to send to
   	Counter#(.WIDTH(`NumBits(NUM_BR - 1))) brselect(
		.Q(branch_sel), 
		.Clock(next_branch_clk), 
		.Reset(sync_begin_clk)
	);
    
//    assign BranchOut = Din << branch_sel;
    wire [NUM_BR-1:0] demux = Din << branch_sel;
    assign BranchOut = {WANT_SYNC? Sync: demux[NUM_BR-1], WANT_VALID? Valid: demux[NUM_BR-2], demux[NUM_BR-3:0]};
//`else

//    assign Node[23:12] = 0;
//    assign Node[11:0] = timer_count;
//    assign BranchOut[5:1] = {preset_clk, recover_bit_clk, branch_sel_clk, sync_begin_clk, sync_end_clk}; //, 1'b0};
//    assign BranchOut[0] = 0;
//    assign Valid = Din;
//`endif
/*
    assign BranchOut[0] = (branch_sel == 0) && Din;
//    if (`NUM_BR > 1) begin
        assign BranchOut[1] = (branch_sel == 1) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[2] = (branch_sel == 2) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[3] = (branch_sel == 3) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[4] = (branch_sel == 4) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[5] = (branch_sel == 5) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[6] = (branch_sel == 6) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[7] = (branch_sel == 7) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[8] = (branch_sel == 8) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[9] = (branch_sel == 9) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[10] = (branch_sel == 10) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[11] = (branch_sel == 11) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[12] = (branch_sel == 12) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[13] = (branch_sel == 13) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[14] = (branch_sel == 14) && Din;
//    end
//    if (`NUM_BR > 2) begin
        assign BranchOut[15] = (branch_sel == 15) && Din;
//    end
*/
//    integer brnum;
//    reg [`NUM_BR-1:0] branches;
//    assign branch_clock = (next_branch == 1) && (Clock == 1);
//	initial begin
//    always @(branch_sel, Din) begin
//        for (brnum = 0; brnum < `NUM_BR; brnum = brnum + 1)
//            branches[brnum] = (branch_sel == brnum) && (Din == 1);
//    end
//    assign BranchOut = branches;

endmodule