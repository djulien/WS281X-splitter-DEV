# WS281X-Splitter Overview
WS281X-Splitter has 2 main purposes:
1. ![Splitter diagram](splitter.svg)
Split one long string of WS281X pixels into multiple (up to 4) shorter strings.  This can be used as an alternative to daisy-chaining multiple WS281X strips/strings and/or to avoid the need for null pixels between strings.
2. ![Breakout diagram](breakout.svg)
Show the last WS281X pixel value (24 bits) as a breakout (for debug).  Also shows FPS (8 bits) for controller debugging.
This firmware is written specifically for the Microchip PIC16F15313, but can be adapted to some other PICs.  The firmware runs at 8 MIPS and uses Timers 0-2, MSSP, PWM, and CLC peripherals.  The CLC is required in order to receive or send WS281X data signals on an 8 MIPS PIC.
# Usage
## As Splitter
Connect WS281X-splitter as follows to use the splitter function:
![Connection diagram](connections.svg)
In the sequencing software, the splitter will be represented by 1 WS281X pixel followed by another string of WS281X pixels which will be split into 1-4 segments.
1. Download WS281X-splitter.hex and flash to a PIC16F15313**
2. In your sequencing software, insert 1 extra pixel immediately ahead of the pixels to be split.  Set its 24-bit value to the quad-length** of the (first, second, third) segments to be split.  Any additional pixel values will be sent to the fourth segment.
3. Connect the splitter to a controller port and connect up to 4 strings to the splitter outputs.

## As Breakout
Connect WS281X-splitter as follows to use the break-out function:
![Connection diagram](connections.svg)
The first 24 pixels connected to the Breakout channel will show the first pixel value received.  The next 8 pixels will display the FPS.

1. Download WS281X-splitter.hex and flash to a PIC16F15313**
2. Add one extra pixel onto a port in your sequencing software
3. Connect the splitter to the end of a WS281X pixel strip/string and connect 24 or 32 WS281X pixels to the Breakout channel

# Current Status
under development

# Build Instructions

1. Install Microchip MPLABX 5.35 (this was the last version that supported MPASM rather than MPASMX)
2. Clone the repo
3. Build the project
4. Flash the .hex file into a PIC16F15313**

** PIC16F15313 is a newer device supported by PicKit3, however it can be programmed using a PICKit2 and the very useful PICKitPlus software available at http://anobium.co.uk.  Example command line:
sudo ./pkcmd-lx-x86_64.AppImage -w -p16f15313DEV -fWS281X-splitter.hex -mpc -zv

# Version History

Version 0.21.9 9/30/21 switched to 8-bit PIC with CLC. basic split and breakout functions working for PIC16F15313
Version 0.15.0 ?/?/16 started working on a Xilinx XC9572XL CPLD (72 macrocells) on a Guzunty board

# Reference Docs
AN1606
https://github.com/Anobium/PICKitPlus
https://github.com/Anobium/PICKitPlus/wiki/pkcmd_lx_introduction


### eof
