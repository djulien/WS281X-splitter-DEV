`timescale 1ns / 1ps
`default_nettype none
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

//tips on coding style:
// http://www.ece.ncsu.edu/asic/lect_NTU/AppendixA.pdf
// http://www.edaboard.com/thread103873.html
// http://www.sutherland-hdl.com/papers/1996-CUG-presentation_nonblocking_assigns.pdf

//SR:
/*
always @(posedge clk)
begin
y1 <= #4 in;
y2 <= #4 y1;
y3 <= #4 y2;
out <= #4 y3;
end
*/

module Counter(Q, Clock, Reset);
    parameter WIDTH = 8;

    output wire[WIDTH-1:0] Q;
//    output Debug,

    input wire Clock;
    input wire Reset;

//	FF[WIDTH-1:0] count;
    reg [WIDTH-1:0] count;
//    wire not_Reset = ~Reset;
//    reg prior; //for edge detection
//    integer i;

	assign Q = count;
//    assign Debug = prior;

//only used for sim (real hw powers up random), so *don't* use this:
//	initial begin
//		count <= 0;
//        prior <= 0;
//	end

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

/*
    always @(Reset) begin
		if (Reset == 1) //async reset, overrides clock
			count = 0;
	end

    wire ClockEdge = (Clock == 1) && (prior == 0) && (Reset == 0);
    always @(posedge ClockEdge) count = count + 1;
    always @(posedge Clock) prior = Clock; //for edge detection
    always @(negedge Clock) prior = Clock; //for edge detection
*/
    always @(posedge Clock, posedge Reset) begin
#4 //simulate CPLD delay
		if (Reset) //async reset, overrides clock
			count <= 8'b0;
		else //if (Clock) begin //rising edge
			count <= count + 1; //this generates an adder; don't use it
//            for (i = 0; i < WIDTH; i = i + 1)
//                if (i == 0) count[i] <= !count[i];
//                else count[i] <= count[i] ^ count[i - 1];
//                count[i] <= (i == 0)? ~count[i]: == 0)? 1: count[i - 1]);
//            count[0] <= count[0] ^ 1;
//            for (i = 1; i < WIDTH; i = i + 1)
//                count[i] <= count[i] ^ count[i - 1];
//        end
//        prior <= Clock; //for edge detection
    end

endmodule


/*
//don't care about race conditions since this is edge-triggered:
module FF(input Clock, input Reset, output req Q);
    always @(posedge Reset) begin
#4 //simulate CPLD delay
        Q <= 0;
    end
    always @(posedge Clock) begin
#4 //simulate CPLD delay
        Q <= ~Q;
    end
endmodule
*/


/*
//from http://www.xilinx.com/support/documentation/university/Vivado-Teaching/HDL-Design/2013x/Nexys4/Verilog/docs-pdf/lab5.pdf
module clock_divider_behavior(input Clk, output reg Q);
    always @(negedge Clk)
        Q <= ~Q;
endmodule

module T_ff_enable_behavior(input Clk, input reset_n, input T, output reg Q);
    always @(negedge Clk)
        if (!reset_n)
            Q <= 1'b0;
        else if (T)
            Q <= ~Q;
endmodule
*/