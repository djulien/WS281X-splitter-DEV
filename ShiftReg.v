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
module ShiftReg #(parameter WIDTH = 8)(
    input [WIDTH-1:0] D,
    output [WIDTH-1:0] Q,
    output Carry,
    input Clock,
    input Preset
    );

	reg[WIDTH:0] latch = 0; //NOTE: 1 extra bit for Carry
    reg prior = 0; //for edge detection

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
    always @(Preset) begin
		if (Preset == 1) begin //async reset, overrides clock
            latch[WIDTH] = 0;
            latch[WIDTH-1:0] = D;
        end
	end

    wire ClockEdge = (Clock == 1) && (prior == 0) && (Preset == 0);
    always @(posedge ClockEdge) begin
        latch[WIDTH:1] = latch[WIDTH-1:0];
        latch[0] = D[0];
    end
    always @(posedge Clock) prior = Clock; //for edge detection
    always @(negedge Clock) prior = Clock; //for edge detection

    always @(negedge Clock) begin
        prior = Clock; //for edge detection
	end

	assign Carry = latch[WIDTH];
	assign Q = latch[WIDTH-1:0];

endmodule