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


`define NUM_BR  16 //max #branches to split out
`define CLK_FREQ  50 `MHz //CPLD clock frequency
`define ESC_NEXT_BRANCH  24'h010203 //esc code to step to next branch
`define SYNC_PULSE  (25 `NSEC) //desired width of sync (reset) signal
`define CLK_PERIOD  (1 / `CLK_FREQ) //@50 MHz = 20 nsec

`define MHz  * 1000000
`define USEC  / 1000000
`define NSEC  / 1000000000


module WS281X_Breakout ( //#(parameter CLKFREQ = 50 `MHz)(
    input Din,
    input Clock,
    output [23:0] Node,
    output Valid,
    output [`NUM_BR-1:0] BranchOut,
    output Sync
    );

`include "NumBits.vh"

//timer to control data and sync recovery:
    wire recover_bit; //when to recover incoming data bit
    wire sync_begin; //WS281X latch signal detected
    wire sync_end; //end of sync pulse

    wire [12-1:0] delay_count;
   	Counter#(.WIDTH(12)) timer(
		.Q(delay_count), 
		.Clock(Clock), 
		.Reset(Din)
	);
    assign recover_bit = (delay_count == 30); //600 `NSEC / `CLK_PERIOD); //30 @50 MHz
    assign sync_begin = (delay_count >= 2500); //50 `USEC / `CLK_PERIOD); //2500 @50 MHz
    assign sync_end = (delay_count <= 2501); //(50 `USEC + `SYNC_PULSE) / `CLK_PERIOD); //250X @50 MHz
    assign Sync = sync_begin && sync_end;

//collect in-coming WS281X node:
//    wire node_valid; //RGB value recovered
    wire node_clock; //node shift clock
    wire node_init; //setup for next node value
    wire next_branch; //redirect to next branch

    wire [23:0] node_value;
   	ShiftReg#(.WIDTH(24)) node(
        .D(preset_bits),
		.Q(Node), //node_value), 
        .Carry(Valid), //node_valid),
		.Clock(node_clock), 
		.Preset(node_init)
	);
//    assign Node = node_value;
//    assign Valid = node_valid;
    assign node_clock = (recover_bit == 1) && (Clock == 1);
    assign node_init = (recover_bit == 1) && (Clock == 1) && (Valid == 1); //node_valid == 1);
    assign next_branch = (Node /*node_value*/ == `ESC_NEXT_BRANCH) && (Valid == 1); //node_valid == 1);

//redirect incoming data to a branch string:
    wire [`NumBits(`NUM_BR) - 1:0] branch_sel; //which branch to send to
    wire branch_clock;

   	Counter#(.WIDTH(`NumBits(`NUM_BR))) brselect(
		.Q(branch_sel), 
		.Clock(branch_clock), 
		.Reset(sync_begin)
	);

    integer brnum;
    reg [`NUM_BR-1:0] branches;
    assign branch_clock = (next_branch == 1) && (Clock == 1);
//	initial begin
    always @(branch_sel, Din) begin
        for (brnum = 0; brnum < `NUM_BR; brnum = brnum + 1)
            branches[brnum] = (branch_sel == brnum) && (Din == 1);
    end
    assign BranchOut = branches;

endmodule