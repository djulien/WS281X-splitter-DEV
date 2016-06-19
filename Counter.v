`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    11:08:15 06/18/2016 
// Design Name: 
// Module Name:    Counter 
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

module Counter #(parameter WIDTH = 8)(
    output [WIDTH-1:0] Q,
    input Clock,
//    output Debug,
    input Reset
    );

	reg[WIDTH-1:0] count;
    reg prior; //for edge detection

	initial begin
		count = 0;
        prior = 0;
	end

/* BROKEN: won't synth
	always @(posedge Clock, Reset) begin
//--		if rising_edge(Reset) then --can't have to edge clocks on a FF
		if (Reset == 1) //async reset, overrides clock
			count = 0;
		else if (Clock == 1 && prior == 0) //rising edge
			count = count + 1;
        prior = Clock; //for edge detection
	end
*/
    always @(Reset) begin
		if (Reset == 1) //async reset, overrides clock
			count = 0;
	end

    wire ClockEdge = (Clock == 1) && (prior == 0) && (Reset == 0);
    always @(posedge ClockEdge) count = count + 1;
    always @(posedge Clock) prior = Clock; //for edge detection
    always @(negedge Clock) prior = Clock; //for edge detection

	assign Q = count;
//    assign Debug = prior;

endmodule