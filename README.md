# WS281X-Splitter Overview
![Connection diagram](connections.svg)
WS281X-Splitter has 2 main purposes:
1. Splitter.  Split one long string of WS281X pixels into multiple (up to 4) shorter strings.  This can be used as an alternative to daisy-chaining multiple WS281X strips/strings and/or to avoid the need for null pixels between groups of pixels.
2. Breakout. Show the next WS281X RGB data pattern (24 bits) at the current position within a group of WS 281X pixels, and FPS (8 bits).  This can be used to diagnose controller or communication problems.
This firmware is written specifically for the Microchip PIC16F15313, but can be adapted to some other PICs.  The firmware uses Timers 0-2, MSSP, PWM, and CLC peripherals.  The CLC allows WS281X signal data to be sent and received at full speed (800 KHz) using a low-power 8 MIPS 8-bit microcontroller.
## Usage as Splitter
![Splitter diagram](splitter.svg)
Connect WS281X-splitter as follows to use the splitter function:
In the sequencing software, the splitter will be represented by 1 WS281X pixel followed by another string of WS281X pixels which will be split into 1-4 segments.
2. In your sequencing software, insert 1 extra pixel immediately ahead of the pixels to be split.  Set its 24-bit value to the quad-length** of the (first, second, third) segments to be split.  Any additional pixel values will be sent to the fourth segment.
3. Connect the splitter to a controller port and connect up to 4 strings to the splitter outputs.

## Usage as Breakout
![Breakout diagram](breakout.svg)
3. Connect the splitter to the end of a WS281X pixel strip/string and connect 24 or 32 WS281X pixels to the Breakout channel
Connect a WS281X data source (controller or daisy-chained pixels) to RA3 and then connect 24 or 32 WS281X pixels to pin RA0 to use the breakout function.
The first 24 pixels on RA0 will show the 24-bit RGB pixel value received (msb first).  If more than 24 pixels are connected to RA0, then the next 8 pixels will display the FPS (msb first).  White represents an "on" bit and red/green/blue/cyan represents an "off" bit.  For example, a Breakout pattern of:
W W W W R R R R W W G G W W G G B W B W B W B W C C C W W W W C
means:
on on on on off off off off on on off off on on off off off on off on off on off on off off off on on on on off
which means:
WS281X pixel value 0xF0CC55 at 30 FPS.
In your sequencing software, the only change needed is to insert one WS281X pixel representing where the WS281X-Splitter is connected.

# Current Status
under development

# Build Instructions
To assemble the firmware use the following steps.  To use the pre-assembled .hex file, skip to step 4.
1. Clone this repo
2. Install Microchip MPLABX 5.35 or GPASM or equivalent tool chain.  Note that MPLABX was the last version that supported MPASM rather than MPASMX.
3. Build the project
4. Flash the dist/WS281X-splitter.hex file into a PIC16F15313**

** PIC16F15313 is a newer device supported by PICKit3.  However, it can be programmed using the older PICKit2 and the very useful PICKitPlus software available at https://anobium.co.uk.  Example command line (for Linux):
sudo ./pkcmd-lx-x86_64.AppImage -w -p16f15313 -fdist/WS281X-splitter.hex -mpc -zv

# Version History

Version 0.21.9 9/30/21 switched to 8-bit PIC with CLC. basic split and breakout functions working for PIC16F15313
Version 0.15.0 ?/?/16 started working on a Xilinx XC9572XL CPLD (72 macrocells) on a Guzunty board

# Reference Docs
AN1606
https://github.com/Anobium/PICKitPlus
https://github.com/Anobium/PICKitPlus/wiki/pkcmd_lx_introduction

### eof
