//`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    15:22:29 06/18/2016 
// Design Name: 
// Module Name:    NumBits 
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

//module NumBits(
//    );
//endmodule

/*
function integer NumBits;
//    input [31:0] value;
    input [15:0] value; //NOTE: don't use int here; it converts to a 1-bit value??
//    integer exp;
//    integer size;
    reg [15:0] size;

    begin
//        numbits = 0;
//        for (exp = 0; 2 ** exp > value; exp = exp + 1)
//            numbits = exp + 1;
        NumBits = 0;
/-*
        for (size = 0; 2**size > value; size = size + 1)
        begin
            NumBits = size; //NOTE: FOR loop needs a stmt here
            $display("NumBits: size %d, val %d", size, value);
        end
//        $display("%d => %d or %d @%s:%d\n", value, size, NumBits, `__FILE__, `__LINE__);
*-/
//kludge: can't get loop working, so just hard code a few values:
        if (value < 2**0)
            NumBits = 0;
        else if (value < 2**1)
            NumBits = 1;
        else if (value < 2**2)
            NumBits = 2;
        else if (value < 2**3)
            NumBits = 3;
        else if (value < 2**4)
            NumBits = 4;
        else if (value < 2**5)
            NumBits = 5;
        else if (value < 2**6)
            NumBits = 6;
        else if (value < 2**7)
            NumBits = 7;
        else if (value < 2**8)
            NumBits = 8;
//        $display("NumBits: %d => %d", value, NumBits);
    end
endfunction
*/

`define NumBits(value)  \
    (value < 2**0)? 0: \
    (value < 2**1)? 1: \
    (value < 2**2)? 2: \
    (value < 2**3)? 3: \
    (value < 2**4)? 4: \
    (value < 2**5)? 5: \
    (value < 2**6)? 6: \
    (value < 2**7)? 7: \
        8
