`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:15:05 06/18/2016 
// Design Name: 
// Module Name:    ShiftReg 
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

//serial + parallel in/out shift reg:
module ShiftReg(Q, Carry, Dp, Ds, Clock, Preset);
    parameter WIDTH = 8;

    output wire [WIDTH-1:0] Q;
    output wire Carry;

    input wire [WIDTH-1:0] Dp; //parallel in
    input wire Ds; //serial in
    input wire Clock;
    input wire Preset;

	reg[WIDTH:0] latch; //NOTE: 1 extra bit for Carry
//    reg prior; //for edge detection

	assign Carry = latch[WIDTH];
	assign Q = latch[WIDTH-1:0];

//only used for sim (real hw powers up random), so *don't* use this:
//	initial begin
//		latch = 0;
//        prior = 0;
//	end

/* BROKEN: won't synth
	always @(posedge Clock, Preset) begin
//--		if rising_edge(Reset) then --can't have to edge clocks on a FF
		if (Preset == 1) //async preset, overrides clock
        begin
			latch[WIDTH] = 0;
			latch[WIDTH-1:0] = D;
//			if rising_edge(Clock) then --and Reset = '0' then
        end
		else if (Clock == 1 && prior == 0) //rising edge
        begin
			latch[WIDTH:1] = latch[WIDTH-1:0];
			latch[0] = D[0];
        end
        prior = Clock; //for edge detection
	end
*/

/*
    always @(Preset, Dp) begin
		if (Preset == 1) begin //async reset, overrides clock
            latch[WIDTH] = 0;
            latch[WIDTH-1:0] = Dp;
        end
	end

    wire ClockEdge = (Clock == 1) && (prior == 0) && (Preset == 0);
    always @(posedge ClockEdge) begin
        latch[WIDTH:1] = latch[WIDTH-1:0];
        latch[0] = Ds; //[0];
    end
    always @(posedge Clock) prior = Clock; //for edge detection
    always @(negedge Clock) prior = Clock; //for edge detection

    always @(negedge Clock) begin
        prior = Clock; //for edge detection
	end
*/

    always @(posedge Clock, posedge Preset) begin //, prior, Dp, Ds) begin
#4 //simulate CPLD delay
		if (Preset) //async preset, overrides clock
            {latch[WIDTH], latch[WIDTH-1:0]} = {1'b0, Dp};
		else //if (Clock == 1 && prior == 0) begin //rising edge
            {latch[WIDTH:1], latch[0]} = {latch[WIDTH-1:0], Ds};
//        prior = Clock; //for edge detection
    end

endmodule


/*
//from http://www.xilinx.com/support/documentation/university/Vivado-Teaching/HDL-Design/2013x/Nexys4/Verilog/docs-pdf/lab5.pdf
module SR_latch_gate (input R, input S, output Q, output Qbar);
    nor (Q, R, Qbar);
    nor (Qbar, S, Q);
endmodule


module SR_latch_dataflow (input R, input S, output Q, output Qbar);
    assign #2 Q_i = Q;
    assign #2 Qbar_i = Qbar;
    assign #2 Q = ~ (R | Qbar);
    assign #2 Qbar = ~ (S | Q);
endmodule
*/