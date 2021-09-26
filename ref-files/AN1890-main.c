/*************************************************************************
 *  © 2015 Microchip Technology Inc.                                       
 *  
 *  Project Name:    Serial SRAM Buffer
 *  FileName:        main.c
 *  Dependencies:    none
 *  Processor:       See documentation for supported PIC® microcontrollers 
 *  Compiler:        MPLAB XC8 version 1.30 or later
 *  IDE:             MPLAB® X                        
 *  Hardware:         
 *  Company:         
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 *  Description:     Main routine
 *                   - Example implementation code required to implement
 *                     a SRAM buffer for a WS2811/WS2812 LED array
 *************************************************************************/ 
/*************************************************************************
 * MICROCHIP SOFTWARE NOTICE AND DISCLAIMER: You may use this software, and
 * any derivatives created by any person or entity by or on your behalf,
 * exclusively with Microchip's products in accordance with applicable
 * software license terms and conditions, a copy of which is provided for
 * your referencein accompanying documentation. Microchip and its licensors
 * retain all ownership and intellectual property rights in the
 * accompanying software and in all derivatives hereto.
 *
 * This software and any accompanying information is for suggestion only.
 * It does not modify Microchip's standard warranty for its products. You
 * agree that you are solely responsible for testing the software and
 * determining its suitability. Microchip has no obligation to modify,
 * test, certify, or support the software.
 *
 * THIS SOFTWARE IS SUPPLIED BY MICROCHIP "AS IS". NO WARRANTIES, WHETHER
 * EXPRESS, IMPLIED OR STATUTORY, INCLUDING, BUT NOT LIMITED TO, IMPLIED
 * WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY, AND FITNESS FOR A
 * PARTICULAR PURPOSE APPLY TO THIS SOFTWARE, ITS INTERACTION WITH
 * MICROCHIP'S PRODUCTS, COMBINATION WITH ANY OTHER PRODUCTS, OR USE IN ANY
 * APPLICATION.
 *
 * IN NO EVENT, WILL MICROCHIP BE LIABLE, WHETHER IN CONTRACT, WARRANTY,
 * TORT (INCLUDING NEGLIGENCE OR BREACH OF STATUTORY DUTY), STRICT
 * LIABILITY, INDEMNITY, CONTRIBUTION, OR OTHERWISE, FOR ANY INDIRECT,
 * SPECIAL, PUNITIVE, EXEMPLARY, INCIDENTAL OR CONSEQUENTIAL LOSS, DAMAGE,
 * FOR COST OR EXPENSE OF ANY KIND WHATSOEVER RELATED TO THE SOFTWARE,
 * HOWSOEVER CAUSED, EVEN IF MICROCHIP HAS BEEN ADVISED OF THE POSSIBILITY
 * OR THE DAMAGES ARE FORESEEABLE. TO THE FULLEST EXTENT ALLOWABLE BY LAW,
 * MICROCHIP'S TOTAL LIABILITY ON ALL CLAIMS IN ANY WAY RELATED TO THIS
 * SOFTWARE WILL NOT EXCEED THE AMOUNT OF FEES, IF ANY, THAT YOU HAVE PAID
 * DIRECTLY TO MICROCHIP FOR THIS SOFTWARE.
 *
 * MICROCHIP PROVIDES THIS SOFTWARE CONDITIONALLY UPON YOUR ACCEPTANCE OF
 * THESE TERMS.
 *************************************************************************/
// PIC16F1509 Configuration Bit Settings

// 'C' source line config statements

#include <xc.h>
#include <stdint.h>

// #pragma config statements should precede project file includes.
// Use project enums instead of #define for ON and OFF.

// CONFIG1
#pragma config FOSC = INTOSC    // Oscillator Selection Bits (INTOSC oscillator: I/O function on CLKIN pin)
#pragma config WDTE = OFF       // Watchdog Timer Enable (WDT disabled)
#pragma config PWRTE = OFF      // Power-up Timer Enable (PWRT disabled)
#pragma config MCLRE = ON       // MCLR Pin Function Select (MCLR/VPP pin function is MCLR)
#pragma config CP = OFF         // Flash Program Memory Code Protection (Program memory code protection is disabled)
#pragma config BOREN = ON       // Brown-out Reset Enable (Brown-out Reset enabled)
#pragma config CLKOUTEN = OFF   // Clock Out Enable (CLKOUT function is disabled. I/O or oscillator function on the CLKOUT pin)
#pragma config IESO = ON        // Internal/External Switchover Mode (Internal/External Switchover Mode is enabled)
#pragma config FCMEN = ON       // Fail-Safe Clock Monitor Enable (Fail-Safe Clock Monitor is enabled)

// CONFIG2
#pragma config WRT = OFF        // Flash Memory Self-Write Protection (Write protection off)
#pragma config STVREN = ON      // Stack Overflow/Underflow Reset Enable (Stack Overflow or Underflow will cause a Reset)
#pragma config BORV = LO        // Brown-out Reset Voltage Selection (Brown-out Reset Voltage (Vbor), low trip point selected.)
#pragma config LPBOR = OFF      // Low-Power Brown Out Reset (Low-Power BOR is disabled)
#pragma config LVP = OFF        // Low-Voltage Programming Enable (High-voltage on MCLR/VPP must be used for programming)

//----- Function Prototypes -----
void WS2811_Init(void);
void BufferToLEDs(uint16_t address, uint16_t count);
void LEDMode(void);
void SRAMMode(void);
void FillSRAMBuffer(void);
void SendSPI(uint8_t c);
void SRAMtoLED(void);
void WasteTime(void);

#define SRAM_CS_PIN  LATBbits.LATB7
#define SRAM_CS_TRIS TRISBbits.TRISB7

#define LEDS_IN_STRING 60       // Number of LEDs that you are driving

void main(void)
{
    uint8_t index;

    OSCCON = 0b01111000;        // set oscillator for 16MHz operation

    // set up SPI pins for external Serial SRAM
    SRAM_CS_PIN = 1;            // deselect the external SRAM
    SRAM_CS_TRIS = 0;
    TRISCbits.TRISC7 = 0;
    TRISBbits.TRISB6 = 0;
    ANSELCbits.ANSC7 = 0;

    WS2811_Init();

    SSP1IF = 1;                 // required for SPI functions

    FillSRAMBuffer();           // Fill buffer with example LED pattern

    while (1)                   // This loop scrolls the pattern across the LED strip 
                                // by simply starting at a different address in SRAM 
                                // at each iteration
    {
        for (index = 0; index < 126; index += 3)
        // 126 is the length of a full pattern, * 3 bytes per LED (42 * 3)
        {
            BufferToLEDs(index, LEDS_IN_STRING*3);
            WasteTime();
        }
    }
    
}   /* main */

void WasteTime(void)
{
    uint16_t index;

    // 20000 is an arbitrary amount of time.  Adjust to suit your application
    for (index = 0; index < 20000; ++index)
    {
        asm("nop");
    }
}   /* WasteTime */

/*---------------------------------------------------------------------------
 FillSRAMBuffer

  Places a test pattern in the external Serial SRAM buffer

  Pattern is groups of 6 LEDs, 7 different colors, 100% brightness
-----------------------------------------------------------------------------*/
void FillSRAMBuffer(void)
{
    uint8_t i = 0;
    uint8_t j;

    SRAMMode();
    PIR1bits.SSP1IF = 1;
    SRAM_CS_PIN = 0;
    SendSPI(0x02);      // WRITE command
    SendSPI(0x00);      // Write address MSB
    SendSPI(0x00);      // Write address LSB
    for (i = 0; i < LEDS_IN_STRING; ++i)
    {
        for (j = 0; j < 6; ++j)
        {
            SendSPI(0x00);  // Red, 100% brightness
            SendSPI(0xFF);
            SendSPI(0x00);
        }


        for (j = 0; j < 6; ++j)
        {
            SendSPI(0xFF);  // Green, 100% brightness
            SendSPI(0x00);
            SendSPI(0x00);
        }

        for (j = 0; j < 6; ++j)
        {
            SendSPI(0x00);  // Blue, 100% brightness
            SendSPI(0x00);
            SendSPI(0xFF);
        }

        for (j = 0; j < 6; ++j)
        {
            SendSPI(0xFF);  // Yellow, 100% brightness
            SendSPI(0xFF);
            SendSPI(0x00);
        }

        for (j = 0; j < 6; ++j)
        {
            SendSPI(0x00);  // Magenta, 100% brightness
            SendSPI(0xFF);
            SendSPI(0xFF);
        }

        for (j = 0; j < 6; ++j)
        {
            SendSPI(0xFF);  // Cyan, 100% brightness
            SendSPI(0x00);
            SendSPI(0xFF);
        }

        for (j = 0; j < 6; ++j)
        {
            SendSPI(0xFF);  // White, 100% brightness
            SendSPI(0xFF);
            SendSPI(0xFF);
        }

        ++i;
    }
    SRAM_CS_PIN = 1;
}   /* FillSRAMBuffer */


/*---------------------------------------------------------------------------
 SendSPI

  Sends a single byte out the SPI peripheral

  Special Note:  Because this uses the interrupt flag bit as an indication of
  when the transmission is complete, the SSP1IF flag MUST be set by software
  before the first time this function is called.

  Also, if any modes are changed (SPI mode, etc) after this function is called,
  the byte being transmitted must be allowed to complete before invoking any
  mode changes, otherwise, the byte may be lost.
-----------------------------------------------------------------------------*/
void SendSPI(uint8_t c)
{
    while (!PIR1bits.SSP1IF);
    PIR1bits.SSP1IF = 0;
    SSP1BUF = c;
}   /* SendSPI */

/*---------------------------------------------------------------------------
 SRAMtoLED

  Receives a byte from the SRAM via SPI at the same time that a byte is being
  transmitted to the LEDs.  The received byte is immediately transmitted.
  This results in a 1-byte lag between the SRAM and the LEDs.  Make sure you
  send a dummy byte to allow reception of the first SRAM byte before enabling
  transmission to the LEDs

  Special Note:  Because this uses the interrupt flag bit as an indication of
  when the transmission is complete, the SSP1IF flag MUST be set by software
  before the first time this function is called.

  Also, if any modes are changed (SPI mode, etc) after this function is called,
  the byte being transmitted must be allowed to complete before invoking any
  mode changes, otherwise, the byte may be lost.
-----------------------------------------------------------------------------*/
void SRAMtoLED(void)
{
    uint8_t c;

    while (!PIR1bits.SSP1IF);
    PIR1bits.SSP1IF = 0;
    c = SSP1BUF;            // receive byte from SRAM
    SSP1BUF = c;            // transmit byte to LEDs
}   /* SRAMtoLED */


/*---------------------------------------------------------------------------
  BufferToLEDs

  Reads the contents of the SRAM buffer starting at address and sends it
  directly to the LED array

  CLC4 is enabled, which allows SPI transmissions to be sent to the LED array
-----------------------------------------------------------------------------*/
void BufferToLEDs(uint16_t address, uint16_t count)
{
    SRAMMode();
    TRISCbits.TRISC7 = 0;
    TRISBbits.TRISB6 = 0;
    ANSELCbits.ANSC7 = 0;
    ANSELBbits.ANSB4 = 0;

    PIR1bits.SSP1IF = 1;
    SRAM_CS_PIN = 0;

    SendSPI(0x03);      // READ command
    SendSPI(address >> 8);
    SendSPI(address);

    SendSPI(0x00);      // this is a dummy send to allow the first SRAM byte to be received
    while (!PIR1bits.SSP1IF);   // wait for last byte to complete before changing modes

    LEDMode();          // This enables output to the LEDs
    PIR1bits.SSP1IF = 1;

    while (count > 0)
    {
        SRAMtoLED();
        --count;
    }
    SRAM_CS_PIN = 1;
}   /* BufferToLEDs */


/*---------------------------------------------------------------------------
  LEDMode
 
  Sets up the CLC to allow direct communication with the LED array
  
  CLC4 is enabled, which allows SPI transmissions to be sent to the LED array
-----------------------------------------------------------------------------*/
void LEDMode(void)
{
    CLC4CONbits.LC4EN = 1;
}   /* LEDMode */


/*---------------------------------------------------------------------------
  SRAMMode

  Sets up the CLC to allow traditional reads/writes to the serial SRAM via the
  on-board SPI module.

  Since the SPI is already directly connected to the SRAM, this setup simply
  disables CLC4 to prevent SRAM data from being transmitted to the LEDs
-----------------------------------------------------------------------------*/
void SRAMMode(void)
{
    CLC4CONbits.LC4EN = 0;
}   /* SRAMMode */


void WS2811_Init(void)
{
    // Initialize PIC16(L)F1509 CLC2, CLC4, Timer2, and MSSP
    // for WS2811 signal transmission protocol
    // Loading SSP1BUF register sends that data byte out the RC4/CLC4 pin
    // PWM1 routed straight through CLC2
    CLC2GLS0 = 0x20; //!inv G1 D3 => lcxg1
    CLC2GLS1 = 0x00;
    CLC2GLS2 = 0x00;
    CLC2GLS3 = 0x00;
    CLC2SEL0 = 0x00; //LCx_in[4] for lcxd2, LCx_in[0] for lcxd1
    CLC2SEL1 = 0x06; //LCx_in[12] for lcxd4, LCx_in[14] for lcxd3
    CLC2POL = 0x0E; //G2, 3, 4 inverted
    CLC2CON = 0x82; //enabled, output disabled, 4-AND

    // Register values as copied from CLC Designer Tool
    // PWM1 comes through CLC2
    CLC4GLS0  = 0x02; //!inv G1 D1 => lcxg1
    CLC4GLS1  = 0xA4; //!inv G2 D3+4 => lcxg2, inv G2 D2 => lcxg2
    CLC4GLS2  = 0x00;
    CLC4GLS3  = 0x90; //!inv G4 D3+4 => lxcg4
    CLC4SEL0  = 0x54; //LCx_in[9] for lcxd2, LCx_in[4] for lcxd1
    CLC4SEL1  = 0x05; //LCx_in[12] for lcxd4, LCx_in[13] for lcxd3 
    CLC4POL   = 0x0A; //G2, 4 inverted
    CLC4CON   = 0xC5; //enabled, output enabled, 2 inp D flop with R

    // Adjust Timer2 period for desired baud rate
    // One bit period is two Timer2 periods
    T2CON = 0x04; //T2 on, 1:1 pre- and post- scalars
    PR2 = 2; //period = (PR2 +1) * 4 / Fosc * prescalar = 12/16MHz = .75 usec
    // Adjust PWM1 duty cycle for desired "0" data-bit duty cycle
    // "1" data-bit duty cycle is automatically 50%
    PWM1CON = 0xE0;
    PWM1DCH = 1; //pulse width DCHL / Fosc * prescalar = 0b110 = 6 / 16 MHz * 1 = .375 usec
    PWM1DCL = 0x80;
    // MSSP configured for SPI master with Timer2_Period/2 clock, inverted clock
    SSP1CON1 = 0x33; //master, clock T2/2, enable, idle high
    // Output on RC4/CLC4
    TRISC &= 0xEF;
}