`timescale 1us / 1ps

////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer:
//
// Create Date:   07:20:35 06/18/2016
// Design Name:   counter12
// Module Name:   /home/dj/xilinx/ws281x-breakout-vlog/tester.v
// Project Name:  ws281x-breakout
// Target Device:  
// Tool versions:  
// Description: 
//
// Verilog Test Fixture created by ISE for module: counter12
//
// Dependencies:
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
////////////////////////////////////////////////////////////////////////////////

`unconnected_drive pull0  // set unconnected inputs to 0

//`define NUM_LED 24
//`define NUM_SW 24

//select what to test (first one will be used):
//`define TEST_COUNTER12
//`define TEST_COUNTER4
//`define TEST_SHIFT24
//`define TEST_NUMBITS
`define TEST_BITSTREAM
//`define TEST_BREAKOUT


`ifdef TEST_BREAKOUT
 `define TEST_BITSTREAM //TODO: figure out how to do #ifdef X OR Y
`endif
 
module tester;

	// Inputs (tester outputs)
//	reg [`NUM_SW-1:0] Switches;
//	reg clk = 0; //Clock;
//	reg clear = 0; //Reset;
//	reg shift = 0;
//	reg load = 0;
//	reg [9:0] cycles = 0; //10'b0000000000;

	// Outputs (tester inputs)
//	wire [`NUM_LED-1:0] LEDs;
//    wire ovfl; //Carry
//    wire debug;


`ifdef TEST_COUNTER12
	// Outputs (tester inputs)
	wire [12-1:0] LEDs;

	// Instantiate the Unit Under Test (UUT)
	Counter#(.WIDTH(12)) uut(
		.Q(LEDs), 
		.Clock(clk), 
		.Reset(clear)
	);

	initial begin
      $monitor("testing Counter12 ...");
#51 //wait 51 usec more
		$finish;
	end


`elsif TEST_COUNTER4
	// Outputs (tester inputs)
	wire [4-1:0] LEDs;
//    wire ovfl; //Carry
//    wire debug;

	// Instantiate the Unit Under Test (UUT)
	Counter#(.WIDTH(4)) uut(
		.Q(LEDs), 
		.Clock(clk),
//        .Debug(debug),
		.Reset(clear)
	);

	initial begin
      $monitor("testing Counter4 ...");
#0.500 //wait 500 usec
		$finish;
	end


`elsif TEST_SHIFT24
	reg [24-1:0] Switches;
//	reg clk = 0; //Clock;
//	reg clear = 0; //Reset;
//	reg shift = 0;
	reg load = 0;
//	reg [9:0] cycles = 0; //10'b0000000000;

	// Outputs (tester inputs)
	wire [24-1:0] LEDs;
    wire ovfl; //Carry
//    wire debug;

	// Instantiate the Unit Under Test (UUT)
	ShiftReg#(.WIDTH(24)) uut(
        .D(Switches),
		.Q(LEDs), 
        .Carry(ovfl),
		.Clock(clk),
//        .Debug(debug),
		.Preset(load)
	);

	initial begin
      $monitor("testing ShiftReg24 ...");
//        load = 0;
        Switches = 24'h123456; //b010010010010010010010010;

#0.020 //wait 20 nsec
        load = 1;
#0.0025
        Switches = 1; //0; //check LEDs every 4th cycle; should see 0s or Fs being shifted in from bottom
#0.0025
        load = 0;

#0.500 //wait 500 usec
		$finish;
	end


`elsif TEST_NUMBITS
`include "NumBits.vh"
    reg [15:0] val = 0;
    integer size; //wire [15:0] size;

    initial begin
        $display("testing NumBits ...");
        for (val = 0; val < 20; val = val + 1)
            $display("#bits in %d = %d", val, NumBits(val)); //, `__FILE__, `__LINE__);
        $finish;
    end


`elsif TEST_BITSTREAM
`define NUM_PIXELS  7
    reg [23:0] pixels[`NUM_PIXELS-1:0]; //= {0, 1, 2, 3, 4, 5, 6}; //'{24'hAA0000, 24'h00BB00, 24'h0000CC, 24'h555555, 0, 24'hFFFFFF, 24'h123456};
    reg [23:0] rgb = 0;

	// Outputs (tester inputs)
	reg ws281x = 0; //pixel stream
//    reg [3-1:0] RedBitIndex = 0, GreenBitIndex = 0, BlueBitIndex = 0; //show which bit of pixel is being sent
//    reg [4:0] BitCount = 0;
//    integer ibit = -1;
    reg [5-1:0] ibit = 5'b11111;
//    reg [4-1:0] PixelCount = 0; //show which pixel# this is
//    integer ipix = -1;
    reg [4-1:0] ipix = 4'b1111;
    reg delayed = 0;

`ifdef TEST_BREAKOUT
    reg [4-1:0] branches = 0;
    reg [23:0] leds = 0;
    reg valid = 0;
    reg sync = 0;

	// Instantiate the Unit Under Test (UUT)
	WS281X_Breakout uut(
        .Din(ws281x),
		.Clock(clk),
//        .Debug(debug),
		.BranchOut(branches), 
        .Node(leds),
        .Valid(valid),
        .Sync(sync)
	);
`endif

    initial begin
        $display("testing Bitstream ...");
//        pixels[`NUM_PIXELS-1:0] <= {0, 1, 2, 3, 4, 5, 6}; //'{24'hAA0000, 24'h00BB00, 24'h0000CC, 24'h555555, 0, 24'hFFFFFF, 24'h123456};
//TODO: maybe use initial $readmemh ("xyz_init_vals.hex",xyz_array);
        pixels[6] = 24'hAA0000;
        pixels[5] = 24'h00BB00;
        pixels[4] = 24'h0000CC;
        pixels[3] = 24'h555555;
        pixels[2] = 0;
        pixels[1] = 24'hFFFFFF;
        pixels[0] = 24'h123456;
        delayed = 1;

#0.888 //random delay start of stream so it doesn't match clock
        delayed = 0;
        for (ipix = 0; ipix < `NUM_PIXELS; ipix = ipix + 1)
        begin
            rgb = pixels[`NUM_PIXELS-1 - ipix];
            for (ibit = 0; ibit < 24; ibit = ibit + 1)
            begin
//#0.625
                ws281x = 1;
#0.25
                ws281x = rgb[24-1 - ibit];
#0.375
                ws281x = 0;
#0.625
                ws281x = 0; //kludge: need a stmt here
            end
        end
#300 //latch signal at end; 7 * 30 usec + 50 usec = 260 usec
        $finish;
    end

/*
//show pixel + bit counter for easier debug:
//	always begin
    initial begin
        delayed = 1;
//delay to match bit stream:
#0.888
//#0.625
        delayed = 0;
        forever // (; 1 == 1;) //for ever; done this way in order to use initial delay above
        begin
#1.250 //WS281X bit time
            BitCount = BitCount + 1;
            if (BitCount >= 24)
            begin
                BitCount = 0;
                PixelCount = PixelCount + 1;
            end
        end
	end
*/


`else
	$err("nothing to test?");
`endif


//reset and free-running clock signals:
	reg clk = 0; //Clock;
	reg clear = 1; //Reset;
	reg [12-1:0] cycles = 0; //10'b0000000000;

	initial begin
// Initialize regs to known state
//		clk = 0;
//		clear = 0;
//		clear = 1;
//		cycles = 10'b0000000000;
//		$monitor($time, " reset: %b, cycle: %d", clear, cycles);
		$write("[%0t] %s %d %s", $time, `__FILE__, `__LINE__, "msg");

#0.095 //wait ~ 100 nsec for global reset to finish; test clock edge override by making it a little less
		clear = 0;
//#0.010
//        clear = 0;
	end

	always begin
#0.010 //every 10 nsec
//always #0.010 clk = ~clk;
		clk = !clk; //50 MHz free-running
		if (clk == 0) cycles[9:0] = cycles[9:0] + 1; //for debug/test
	end

endmodule