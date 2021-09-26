    title  "WS281X-Splitter - WS281X channel splitter/debug/breakout using Microchip PIC16F15313"
;WS281X splitter/debugger 0.21
;(c)2021 djulien@thejuliens.net
; ================================================================================
; File:     wssplitter.asm
; Device:   PIC16F15313 (Microchip PIC, 8 MIPS, CLC, 8-pin) or equivalent
; Author:   djulien@thejuliens.net
; Date:     8/11/2021
; Compiler: mpasmx(v5.35)
; IDE:      MPLABX v5.35 (last one to include mpasm)
; Description:
;   WS281X splitter/debugger can be used for the following purposes:
;   1. split s single WS281X data stream into up to 4 separate streams; 
;     creates a virtual daisy chain of LED strings instead of using null pixels
;   2. debugger or signal integrity checker; show 24-bit node data at end of string
;   3. timing checker; display frame rate (FPS received); color is used as heartbeat
; Build instructions:
;no   ?Add this line in the project properties box, pic-as Global Options -> Additional options:
;no   -Wa,-a -Wl,-pPor_Vec=0h,-pIsr_Vec=4h
;   - use PicKit or equivalent programmer
; Wiring:
;  RA0 = debug output (32 px WS281X):
;        - first 24 px shows channel 1/2/3 quad px length (0 = 1K)
;        - next 8 px = FPS (255 max), msb first
;  RA1 = output channel 1
;  RA2 = output channel 2
;  RA3 = WS281X input stream
;        - first/second/third byte = channel 1/2/3 quad node length
;	 - first channel data follows immediately
;  RA4 = output channel 4; receives anything after channel 1/2/3
;  RA5 = output channel 3
; TODO:
;  - use PPS to set RA3 as channel 3 out and RA5 as WS input?
;  - uart bootloader; ground channel 0 out to enable? auto-baud detect; verify
;  - custom node dup/skip, enforce max brightness limit?
; ================================================================================
    NOLIST

;#ifndef WANT_HOIST
;    messg "hello 1"
    LIST n = 60, c = 200, t = on, n = 0  ;line (page) size, column size, truncate, no paging
;	LIST r=hex  ;radix; NOTE: this affects interpretation of literals, as well as output listing; ALWAYS use D'' with literals > 8
    LIST R = DEC
    LIST mm = on  ;memory map
    LIST st = on  ;symbol table
;    PAGEWIDTH   132
;    RADIX       DEC

#ifdef __16F15313
    LIST p = 16F15313
    PROCESSOR 16F15313  ;688 ;16F877A
;#include "P16F15313.INC"
 #include <p16f15313.inc>
    NOLIST; .inc file turned it on again
#else
    error [ERROR] Which device?
#endif
;pic-as not mpasm: #include <xc.inc>

;config options:
;#define BITBANG; dev/test only
;#define WANT_DEBUG; dev/test only
#define WSBIT_FREQ  (800 KHz); WS281X "high" speed


;clock macros:
#define mhz(freq)  rdiv(freq, 1000000)
#define khz(freq)  rdiv(freq, 1000)
#define scale(freq, prescaler)  ((freq) / BIT(prescaler))
;readabililty macros:
;CAUTION: usage might require parens
#define MHz  * 1000000
#define KHz  * 1000
;#define Hz  * 1
#define PLL  * 2; PLL on int osc is 2, ext clk is 4
#define MIPS  * 4 MHz ;4 clock cycles per instr


;HFFRQ values:
;(these should be in p16f15313.inc)
    CONSTANT HFFRQ#v(32 MHz) = b'110'
    CONSTANT HFFRQ#v(16 MHz) = b'101'
    CONSTANT HFFRQ#v(12 MHz) = b'100'
    CONSTANT HFFRQ#v(8 MHz) = b'011'
    CONSTANT HFFRQ#v(4 MHz) = b'010'
    CONSTANT HFFRQ#v(2 MHz) = b'001'
    CONSTANT HFFRQ#v(1 MHz) = b'000'


;memory banks:
;#define COMMON_START  0
#define COMMON_END  0xC
#define GPR_START  0x20
#define GPR_END  0x70
;    CONSTANT GPR_LEN = GPR_END - GPR_START;
#define BANKLEN  0x80
;    CONSTANT NONBANKED_LEN = BANKLEN - GPR_END;
;line too long    CONSTANT BANKLEN = 0X80;
#define BANK_UNKN  -1 ;non-banked or unknown
;line too long    CONSTANT BANK_UNKN = -1; non-banked or unknown
#define BANKOFS(reg)  ((reg) % BANKLEN)
#define ISBANKED(reg)  ((BANKOFS(reg) >= COMMON_END) && (BANKOFS(reg) < GPR_END))
;    MESSG "TODO: check !banked reg also"
#define BANKOF(reg)  IIF(ISBANKED(reg), REG2ADDR(reg) / BANKLEN, BANK_UNKN)


;code pages:
;special code addresses:
#define RESET_VECTOR  0
#define ISR_VECTOR  4
;get page# of a code address:
;#define PAGELEN  0x400
#define REG_PAGELEN  0x100  ;code at this address or above is paged and needs page select bits (8 bit address)
#define LIT_PAGELEN  0x800  ;code at this address or above is paged and needs page select bits (11 bit address)
;line too long    CONSTANT PAGELEN = 0X400;
;#define BANKOFS(reg)  ((reg) % BANKLEN)
#define LITPAGEOF(addr)  ((addr) / LIT_PAGELEN)  ;used for direct addressing (thru opcode)
#define REGPAGEOF(addr)  ((addr) / REG_PAGELEN)  ;used for indirect addressing (thru register)


;bool macros:
#define TRUE  1
#define FALSE  0
#define BOOL2INT(val)  ((val) != 0)
;ternary operator (like C/C++ "?:" operator):
;line too long: #define IIF(TF, tval, fval)  (BOOL2INT(TF) * (tval) + (!BOOL2INT(TF)) * (fval))
#define IIF(TF, tval, fval)  (BOOL2INT(TF) * ((tval) - (fval)) + (fval)) ;favors short fval

#ifdef WANT_DEBUG
 #define IIFDEBUG(tval, ignored)  tval
#else
 #define IIFDEBUG(ignored, fval)  fval
#endif


;misc arithmetic helpers:
#define rdiv(num, den)  (((num)+(den)/2)/(den))  ;rounded divide (at compile-time)
;#define divup(num, den)  (((num)+(den)-1)/(den))  ;round-up divide
;#define err_rate(ideal, actual)  ((d'100'*(ideal)-d'100'*(actual))/(ideal))  ;%error
;#define mhz(freq)  #v((freq)/ONE_SECOND)MHz  ;used for text messages
;#define kbaud(freq)  #v((freq)/1000)kb  ;used for text messages
;#define sgn(x)  IIF((x) < 0, -1, (x) != 0)  ;-1/0/+1
;#define abs(x)  IIF((x) < 0, -(x), x)  ;absolute value
#define MIN(x, y)  IIF((x) < (y), x, y)  ;use upper case so it won't match text within ERRIF/WARNIF messages
#define MAX(x, y)  IIF((x) > (y), x, y)  ;use upper case so it won't match text within ERRIF/WARNIF messages


;restore current macro expand directive:
;kludge: fwd ref problem; put this one first
    VARIABLE MEXPAND_STACK = 1  ;default is ON
EXPAND_RESTORE MACRO
    NOEXPAND  ;first turn it off to hide clutter in here
    if !(MEXPAND_STACK & 1) ;leave listing off
	EXITM
    endif
    EXPAND  ;turn listing back on again
    ENDM


;error/debug assertion message macros:
;******************************************************************************
;show error message if condition is true:
;params:
; assert = condition that must (not) be true
; message = message to display if condition is true (values can be embedded using #v)
ERRIF MACRO assert, message, args
    NOEXPAND  ;hide clutter
    if assert
	error message, args
    endif
    EXPAND_RESTORE
    ENDM


;show warning message if condition is true:
;params:
; assert = condition that must (not) be true
; message = message to display if condition is true (values can be embedded using #v)
WARNIF MACRO assert, message, args
    NOEXPAND  ;hide clutter
    if assert
	messg message, args
    endif
    EXPAND_RESTORE
    ENDM


;add lookup for non-power of 2:
;find_log2 macro val
;    LOCAL bit = 0;
;    while BIT(bit)
;	if BIT(bit) > 0
;    messg #v(asmpower2), #v(oscpower2), #v(prescpower2), #v(asmbit)
;	    CONSTANT log2(asmpower2) = asmbit
;	endif
;ASM_MSB set asmpower2  ;remember MSB; assembler uses 32-bit values
;asmpower2 *= 2
;    endm

;log2 function:
;converts value -> bit mask at compile time; CAUTION: assumes value is exact power of 2
;usage: LOG2_#v(bit#) = power of 2
;NOTE: only works for exact powers of 2
;equivalent to the following definitions:
;#define LOG2_65536  d'16'
; ...
;#define LOG2_4  2
;#define LOG2_2  1
;#define LOG2_1  0
;#define LOG2_0  0
#define log2(n)  LOG2_#v(n)
;#define osclog2(freq)  OSCLOG2_#v(freq)
;#define osclog2(freq)  log2((freq) / 250 * 256); kludge: convert clock freq to power of 2
    CONSTANT log2(0) = 0 ;special case
;    CONSTANT osc_log2(0) = 0;
    VARIABLE asmbit = 0, asmpower2 = 1;, oscpower2 = 1, prescpower2 = 1;
    while asmpower2 ;asmbit <= d'16'  ;-1, 0, 1, 2, ..., 16
;	CONSTANT BIT_#v(IIF(bit < 0, 0, 1<<bit)) = IIF(bit < 0, 0, bit)
	if asmpower2 > 0
;    messg #v(asmpower2), #v(oscpower2), #v(prescpower2), #v(asmbit)
	    CONSTANT log2(asmpower2) = asmbit
;	    CONSTANT osclog2(oscpower2) = asmbit
;	    CONSTANT log2(oscpower2) = asmbit
;	    CONSTANT log2(prescpower2) = asmbit
	endif
ASM_MSB set asmpower2  ;remember MSB; assembler uses 32-bit values
asmpower2 *= 2
;oscpower2 *= 2
;	if oscpower2 == 128
;oscpower = 125
;	endif
;oscpower2 = IIF(asmpower2 != 128, IIF(asmpower2 != 32768, 2 * oscpower2, 31250), 125); adjust to powers of 10 for clock freqs
;prescpower2 = IIF(asmpower2 != 128, IIF(asmpower2 != 32768, 2 * prescpower2, 31250), 122); adjust to powers of 10 for prescalars
asmbit += 1
    endw
    ERRIF log2(1) | log2(0), [ERROR] LOG2_ constants are bad: log2(1) = #v(log2(1)) and log2(0) = #v(log2(0)), should be 0  ;paranoid self-check
    ERRIF log2(1024) != 10, [ERROR] LOG2_ constants are bad: log2(1024) = #v(log2(1024)), should be #v(10)  ;paranoid self-check
;    ERRIF (log2(1 KHz) != 10) | (log2(1 MHz) != 20), [ERROR] OSCLOG2_ constants are bad: log2(1 KHz) = #v(log2(1 KHz)) and log2(1 MHz) = #v(log2(1 MHz)), should be 10 and 20 ;paranoid self-check
;ASM_MSB set 0x80000000  ;assembler uses 32-bit values
    ERRIF (ASM_MSB << 1) || !ASM_MSB, [ERROR] ASM_MSB incorrect value: #v(ASM_MSB << 1), #v(ASM_MSB)  ;paranoid check


;#define WANT_HOIST
;#define __FILE__ "wssplitter.asm" ;kludge: not a built-in MPASM def
;#include __FILE__
;    messg "hello 1.5"
;#include "wssplitter.asm"
;    messg "hello 1.6"
;#undef WANT_HOIST
;#ifndef WANT_HOIST
;    messg "hello 3"


;; config ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Configuration bits: selected in the GUI (MCC)
;#if EXT_CLK_FREQ  ;ext clock might be present
;MY_CONFIG &= _EC_OSC  ;I/O on RA4, CLKIN on RA5; external clock (18.432 MHz); if not present, int osc will be used
;MY_CONFIG &= _FCMEN_ON  ;turn on fail-safe clock monitor in case external clock is not connected or fails (page 33); RA5 will still be configured as input, though
;#else  ;EXT_CLK_FREQ
;MY_CONFIG &= _INTRC_OSC_NOCLKOUT  ;I/O on RA4+5; internal clock (default 4 MHz, later bumped up to 8 MHz)
;MY_CONFIG &= _FCMEN_OFF  ;disable fail-safe clock monitor; NOTE: this bit must explicitly be turned off since MY_CONFIG started with all bits ON
;#endif  ;EXTCLK_FREQ
;MY_CONFIG &= _IESO_OFF  ;internal/external switchover not needed; turn on to use optional external clock?  disabled when EC mode is on (page 31); TODO: turn on for battery-backup or RTC
;MY_CONFIG &= _BOR_OFF  ;brown-out disabled; TODO: turn this on when battery-backup clock is implemented?
;MY_CONFIG &= _CPD_OFF  ;data memory (EEPROM) NOT protected; TODO: CPD on or off? (EEPROM cleared)
;MY_CONFIG &= _CP_OFF  ;program code memory NOT protected (maybe it should be?)
;MY_CONFIG &= _MCLRE_OFF  ;use MCLR pin as INPUT pin (required for Renard); no external reset needed anyway
;MY_CONFIG &= _PWRTE_ON  ;hold PIC in reset for 64 msec after power up until signals stabilize; seems like a good idea since MCLR is not used
;MY_CONFIG &= _WDT_ON  ;use WDT to restart if software crashes (paranoid); WDT has 8-bit pre- (shared) and 16-bit post-scalars (page 125)
;	__config MY_CONFIG

    VARIABLE MY_CONFIG1 = -1  ;start with all Oscillator bits on, then EXPLICITLY turn them off below
MY_CONFIG1 &= _FCMEN_OFF  ; Fail-Safe Clock Monitor Enable bit->FSCM timer disabled
MY_CONFIG1 &= _CSWEN_OFF ;unneeded    ; Clock Switch Enable bit->Writing to NOSC and NDIV is allowed
MY_CONFIG1 &= _CLKOUTEN_OFF  ; Clock Out Enable bit->CLKOUT function is disabled; i/o or oscillator function on OSC2
;#define WANT_PLL  TRUE
;#ifdef WANT_PLL
; MY_CONFIG1 &= _RSTOSC_HFINTPLL  ;Power-up default value for COSC bits->HFINTOSC with 2x PLL, with OSCFRQ = 16 MHz and CDIV = 1:1 (FOSC = 32 MHz)
;#else
;set initial osc freq (will be overridden during startup):
MY_CONFIG1 &= _RSTOSC_HFINT32 ;HFINTOSC with OSCFRQ= 32 MHz and CDIV = 1:1
;#endif
;MY_CONFIG1 &= _RSTOSC_HFINT1  ;Power-up default value for COSC bits->HFINTOSC (1MHz)
    messg [TODO] use RSTOSC HFINT 1MHz?
;#define OSCFRQ_CFG  (16 MHz)
;#define FOSC_CFG  (32 MHz) ;(16 MHz PLL) ;(OSCFRQ_CFG PLL); HFINTOSC freq 16 MHz with 2x PLL and 1:1 div gives 32 MHz (8 MIPS)
MY_CONFIG1 &= _FEXTOSC_OFF  ;External Oscillator mode selection bits->Oscillator not enabled
    VARIABLE MY_CONFIG2 = -1  ;start with all Supervisor bits on, then EXPLICITLY turn them off below
MY_CONFIG2 &= _STVREN_ON  ; Stack Overflow/Underflow Reset Enable bit->Stack Overflow or Underflow will cause a reset
MY_CONFIG2 &= _PPS1WAY_ON ; Peripheral Pin Select one-way control->The PPSLOCK bit can be cleared and set only once in software
MY_CONFIG2 &= _ZCD_OFF   ; Zero-cross detect disable->Zero-cross detect circuit is disabled at POR.
MY_CONFIG2 &= _BORV_LO   ; Brown-out Reset Voltage Selection->Brown-out Reset Voltage (VBOR) set to 1.9V on LF, and 2.45V on F Devices
MY_CONFIG2 &= _BOREN_ON  ; Brown-out reset enable bits->Brown-out Reset Enabled, SBOREN bit is ignored
MY_CONFIG2 &= _LPBOREN_OFF   ; Low-Power BOR enable bit->ULPBOR disabled
MY_CONFIG2 &= _PWRTE_OFF  ; Power-up Timer Enable bit->PWRT disabled
MY_CONFIG2 &= _MCLRE_OFF  ; Master Clear Enable bit->MCLR pin function is port defined function
    VARIABLE MY_CONFIG3 = -1  ;start with all WIndowed Watchdog bits on, then EXPLICITLY turn them off below
; config WDTCPS = WDTCPS_31    ; WDT Period Select bits->Divider ratio 1:65536; software control of WDTPS
MY_CONFIG3 &= _WDTE_OFF  ; WDT operating mode->WDT Disabled, SWDTEN is ignored
; config WDTCWS = WDTCWS_7    ; WDT Window Select bits->window always open (100%); software control; keyed access not required
; config WDTCCS = SC    ; WDT input clock selector->Software Control
    VARIABLE MY_CONFIG4 = -1  ;start with all Memory bits on, then EXPLICITLY turn them off below
    MESSG [TODO] boot loader?
MY_CONFIG4 &= _LVP_OFF ;ON?  ; Low Voltage Programming Enable bit->High Voltage on MCLR/Vpp must be used for programming
MY_CONFIG4 &= _WRTSAF_OFF  ; Storage Area Flash Write Protection bit->SAF not write protected
MY_CONFIG4 &= _WRTC_OFF  ; Configuration Register Write Protection bit->Configuration Register not write protected
MY_CONFIG4 &= _WRTB_OFF  ; Boot Block Write Protection bit->Boot Block not write protected
MY_CONFIG4 &= _WRTAPP_OFF  ; Application Block Write Protection bit->Application Block not write protected
MY_CONFIG4 &= _SAFEN_OFF  ; SAF Enable bit->SAF disabled
MY_CONFIG4 &= _BBEN_OFF  ; Boot Block Enable bit->Boot Block disabled
MY_CONFIG4 &= _BBSIZE_BB512  ; Boot Block Size Selection bits->512 words boot block size
    VARIABLE MY_CONFIG5 = -1  ;start with all Code Protection bits on, then EXPLICITLY turn them off below
MY_CONFIG5 &= _CP_OFF  ; UserNVM Program memory code protection bit->UserNVM code protection disabled
    LIST
    __config _CONFIG1, MY_CONFIG1
    __config _CONFIG2, MY_CONFIG2
    __config _CONFIG3, MY_CONFIG3
    __config _CONFIG4, MY_CONFIG4
    __config _CONFIG5, MY_CONFIG5
    NOLIST
;config
; config FOSC = HS        ; Oscillator Selection bits (HS oscillator)
; config WDTE = OFF       ; Watchdog Timer Enable bit (WDT disabled)
; config PWRTE = OFF      ; Power-up Timer Enable bit (PWRT disabled)
; config BOREN = OFF      ; Brown-out Reset Enable bit (BOR disabled)
; config LVP = OFF        ; Low-Voltage (Single-Supply) In-Circuit Serial Programming Enable bit (RB3 is digital I/O, HV on MCLR must be used for programming)
; config CPD = OFF        ; Data EEPROM Memory Code Protection bit (Data EEPROM code protection off)
; config WRT = OFF        ; Flash Program Memory Write Enable bits (Write protection off; all program memory may be written to by EECON control)
; config CP = OFF         ; Flash Program Memory Code Protection bit (Code protection off)


;macros to control expansion of other macros:
;this allows some clutter to be removed from the .LST file
;use this if more than 32 levels needed:
;    VARIABLE MEXPAND_STACKLO = 1, MEXPAND_STACKHI = 0  ;default is ON (for caller, set at eof in this file)
;    VARIABLE MEXPAND_STACK = 1  ;default is ON (for caller, set at eof in this file)
    VARIABLE MEXPAND_DEPTH = 0, MEXPAND_DEEPEST = 0
;push current macro expand directive, then set new one (max 31 nested levels):
;params:
; onoff = whether to turn macro expansion on or off
EXPAND_PUSH MACRO onoff
    NOEXPAND  ;first turn it off to hide clutter in here
    ERRIF MEXPAND_STACK & ASM_MSB, [ERROR] macro expand stack too deep: #v(MEXPAND_DEPTH),
    NOEXPAND  ;hide clutter in here
MEXPAND_STACK *= 2  ;push current value (shift left)
MEXPAND_STACK += BOOL2INT(onoff)
;	if MEXPAND_DEPTH > MEXPAND_DEEPEST
;MEXPAND_DEEPEST = MEXPAND_DEPTH  ;keep track of high-water mark
;	endif
MEXPAND_DEPTH += 1  ;keep track of current nesting level
MEXPAND_DEEPEST = MAX(MEXPAND_DEEPEST, MEXPAND_DEPTH) ;keep track of high-water mark
;use this if more than 32 levels needed:
;MEXPAND_STACKHI *= 2
;	if MEXPAND_STACKLO & ASM_MSB
;MEXPAND_STACKHI += 1
;MEXPAND_STACKLO &= ~ASM_MSB
;	endif
;    if !(onoff) ;leave it off
;    if !(MEXPAND_STACK & 1) ;leave it off
;	EXITM
;    endif
;    EXPAND  ;turn listing on
    EXPAND_RESTORE
    ENDM


;restore previous macro expand directive:
;params:
; dummy = dummy parameter (needed in order to force MPASM to allow optional params for this macro)
; expected_nesting = expected nesting level after pop (optional); must have a trailing "&" if passed
EXPAND_POP MACRO ;dummy ;, nesting
    NOEXPAND  ;first turn it off to hide clutter in here
;    LOCAL EXP_NEST = nesting -1  ;optional param; defaults to -1 if not passed
MEXPAND_STACK /= 2  ;pop previous value (shift right)
MEXPAND_DEPTH -= 1  ;keep track of current nesting level
;only needed if reach 16 levels:
;	if MEXPAND_STACKLO & ASM_MSB  ;< 0
;MEXPAND_STACKLO &= ~ASM_MSB  ;1-MEXPAND_STACKLO  ;make correction for assembler sign-extend
;	endif
;use this if more than 32 levels needed:
;	if MEXPAND_STACKHI & 1
;MEXPAND_STACKLO += ASM_MSB
;	endif
;MEXPAND_STACKHI /= 2
;errif does this:
;	if !(MEXPAND_STACKLO & 1)  ;pop, leave off
;		EXITM
;	endif
    ERRIF MEXPAND_DEPTH < 0, [ERROR] macro expand stack underflow,
;    EXPAND  ;listing back on again
;    ERRIF (EXP_NEST != -1) && (MEXPAND_DEPTH != EXP_NEST), [ERROR] Mismatched macro expanders: nesting is #v(MEXPAND_DEPTH) but should be #v(EXP_NEST)
    ENDM


;repeat a statement the specified number of times:
;stmt can refer to "repeater" for iteration-specific behavior
;stmt cannot use more than 1 parameter (MPASM gets confused by commas; doesn't know which macro gets the params)
;params:
; count = #times to repeat stmt
; stmt = statement to be repeated
REPEAT MACRO count, stmt, arg
    NOEXPAND  ;hide clutter
;?    EXPAND_PUSH FALSE
    WARNIF !(count), [WARNING] no repeat?,
    LOCAL repeater = 0 ;count UP to allow stmt to use repeater value
    LOCAL COUNT = count
    while repeater < COUNT  ;0, 1, ..., count-1
;	if arg == NOARG
;	    EXPAND_RESTORE  ;show generated code
;    stmt
;	    NOEXPAND  ;hide clutter
;	else
	EXPAND_RESTORE  ;show generated code
    stmt, arg
	NOEXPAND  ;hide clutter
;	endif
repeater += 1
	if repeater > d'1000'  ;paranoid; prevent run-away code expansion
	    ERRIF TRUE, [ERROR] Code generator loop too big: #v(repeater) of #v(COUNT)
	    EXITM
	endif
    endw
    EXPAND_RESTORE ;_POP
    ENDM
;REPEAT macro count, stmt
;    NOEXPAND  ;hide clutter
;    REPEAT2 count, stmt,
;    endm


;; opcode helpers ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;operand types:
;allows pseudo-opcodes to accept either literal or register values
;NOTE: assembler uses 32-bit constants internally; use msb to distinguish literal values from register addresses since it is not usually needed for code generation (which is only 8 or 14 bits)
;literal value operands:
#define BIT(n)  YNBIT(1, n); //(1 << (n))
#define NOBIT(n)  0; //YNBIT(0, n); (0 << (n))
#define YNBIT(yesno, n)  ((yesno) << (n))
#define XBIT(n)  NOBIT(n); don't care (safer to turn off?)
#define LITBIT(n)  LITERAL(BIT(n))
#define LITERAL(n)  (ASM_MSB | (n))  ;prepend this to any 8-, 16- or 24-bit literal values used as pseudo-opcode parameters, to distinguish them from register addresses (which are only 1 byte)
#define ISLIT(val)  ((val) & ASM_MSB) ;((addr) & ASM_MSB) ;&& !ISPSEUDO(thing))  ;check for a literal
#define LIT2VAL(n)  ((n) & ~ASM_MSB)  ;convert from literal to number (strips _LITERAL tag)
;register operands:
#define REGISTER(a)  (a) ;address as-is
#define REG2ADDR(a)  (a)


;optimized bank select:
;only generates bank selects if needed
    VARIABLE BANK_TRACKER = BANK_UNKN; ;currently selected bank
    VARIABLE BANKSEL_KEEP = 0, BANKSEL_DROP = 0; ;perf stats
BANKCHK MACRO reg; ;, fixit, undef_ok
    NOEXPAND  ;reduce clutter in LST file
;    MESSG reg
    LOCAL REG = reg ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
;    MESSG reg, #v(REG)
;    messg "bankof reg, nobank", #v(BANKOF(REG)), #v(BANK_UNKN) ;debug
    if !ISBANKED(REG) ;BANKOF(REG) == BANK_UNKN
;BANKSEL_DROP += 1  ;count saved instructions (macro perf)
;NO BANK_TRACKER = reg  ;remember where latest value came from (in case never set)
;	messg "bankof reg == nobank"
	EXPAND_RESTORE
	exitm
    endif
    LOCAL REGBANK = BANKOF(REG) ;kludge: expanded line too long for MPASM
;    messg BANKOF(REG); #v(REGBANK);
    if REGBANK == BANKOF(BANK_TRACKER)  ;don't need to set RP0/RP1
;PREVBANK = REG  ;update last-used reg anyway (helpful for debug)
BANKSEL_DROP += 1  ;count saved instructions (macro perf)
;;--NESTED_BANKCHK
;	messg "bankof reg == bankof cur"
	EXPAND_RESTORE
	exitm
    endif
;    messg "banksel bankof reg"
;    movlb BANKOF(REG) ;bank sel
BANKSEL_KEEP += 1
BANK_TRACKER = reg  ;remember where latest value came from (in case never set)
    EXPAND_RESTORE
    banksel reg;
    endm

DROP_BANK macro
    NOEXPAND
BANK_TRACKER = BANK_UNKN  ;forget where latest value came from (used for jump targets)
    EXPAND_RESTORE
    endm

;avoid warnings when bank is known to be selected
;#define NOARG  -1; dummy arg (MPASM doesn't like missing/optional args)
#if 0
BANKSAFE macro stmt, arg
    NOEXPAND
    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
;    if arg == NOARG
;        EXPAND_RESTORE
;	stmt
;	NOEXPAND
;    else
    messg stmt
    messg arg
        EXPAND_RESTORE
	stmt, arg
	NOEXPAND
;    endif
    errorlevel +302 ;kludge: Enable bank switch warning
    EXPAND_RESTORE
    endm
#endif
;BANKSAFE2 macro stmt, arg
;    NOEXPAND
;    errorlevel -302 ;kludge: Disable bank switch warning
;    EXPAND_RESTORE
;    stmt, arg
;    NOEXPAND
;    errorlevel +302 ;kludge: Enable bank switch warning
;    EXPAND_RESTORE
;    endm
 

;jump target:
;set BSR and WREG unknown
DROP_CONTEXT MACRO
    DROP_BANK
    DROP_WREG
    endm


;convenience wrappers for SAFE_ALLOC macro:
;#define BDCL(name)  ALLOC_GPR name, TRUE; banked alloc
;#define NBDCL(name)  ALLOC_GPR name, FALSE; non-banked alloc
#define BDCL  ALLOC_GPR 0, ; bank 0 alloc
#define NBDCL  ALLOC_GPR NOBANK, ; non-banked alloc
;allocate a banked/non-banked/reallocated variable:
;checks for address overflow on allocated variables
;also saves banked or non-banked RAM address for continuation in a later CBLOCK
    CONSTANT NOBANK = 9999; can't use -1 due to #v()
;    CONSTANT RAM_START#v(TRUE) = GPR_START, RAM_START#v(FALSE) = GPR_END;
;    CONSTANT MAX_RAM#v(TRUE) = GPR_END, MAX_RAM#v(FALSE) = BANKLEN;
;    CONSTANT RAM_LEN#v(TRUE) = MAX_RAM#v(TRUE) - RAM_START#v(TRUE), RAM_LEN#v(FALSE) = MAX_RAM#v(FALSE) - RAM_START#v(FALSE)
    CONSTANT RAM_START#v(0) = GPR_START, MAX_RAM#v(0) = GPR_END, RAM_LEN#v(0) = MAX_RAM#v(0) - RAM_START#v(0)
    CONSTANT RAM_START#v(1) = BANKLEN + GPR_START, MAX_RAM#v(1) = BANKLEN + GPR_END, RAM_LEN#v(1) = MAX_RAM#v(1) - RAM_START#v(1)
    CONSTANT RAM_START#v(NOBANK) = GPR_END, MAX_RAM#v(NOBANK) = BANKLEN, RAM_LEN#v(NOBANK) = MAX_RAM#v(NOBANK) - RAM_START#v(NOBANK)
;    VARIABLE NEXT_RAM#v(TRUE) = RAM_START#v(TRUE), NEXT_RAM#v(FALSE) = RAM_START#v(FALSE);
;    VARIABLE RAM_USED#v(TRUE) = 0, RAM_USED#v(FALSE) = 0;
    VARIABLE NEXT_RAM#v(0) = RAM_START#v(0), RAM_USED#v(0) = 0;
    VARIABLE NEXT_RAM#v(1) = RAM_START#v(1), RAM_USED#v(1) = 0;
    VARIABLE NEXT_RAM#v(NOBANK) = RAM_START#v(NOBANK), RAM_USED#v(NOBANK) = 0;
#define SIZEOF(name)  name#v(0)size; use #v(0) in lieu of token pasting
#define ENDOF(name)  (name + SIZEOF(name))
;params:
; name = variable name to allocate
; banked = flag controlling where it is allocated; TRUE/FALSE == yes/no, MAYBE == reallocate from caller-specified pool of reusable space
    VARIABLE RAM_BLOCK = 0; unique name for each block
ALLOC_GPR MACRO bank, name, numbytes
    NOEXPAND  ;reduce clutter
;    EXPAND_PUSH TRUE  ;show RAM allocations in LST
    EXPAND ;show RAM allocations in LST
    CBLOCK NEXT_RAM#v(bank); BOOL2INT(banked))  ;continue where we left off last time
	name numbytes
    ENDC  ;can't span macros
;    EXPAND_PUSH FALSE
RAM_BLOCK += 1  ;need a unique symbol name so assembler doesn't complain; LOCAL won't work inside CBLOCK
    EXPAND_RESTORE; NOEXPAND
    CBLOCK
	LATEST_RAM#v(RAM_BLOCK):0  ;get address of last alloc; need additional CBLOCK because macros cannot span CBLOCKS
    ENDC
    NOEXPAND
NEXT_RAM#v(bank) = LATEST_RAM#v(RAM_BLOCK)  ;update pointer to next available RAM location
RAM_USED#v(bank) = NEXT_RAM#v(bank) - RAM_START#v(bank); BOOL2INT(banked))
    CONSTANT SIZEOF(name) = LATEST_RAM#v(RAM_BLOCK) - name;
    ERRIF NEXT_RAM#v(bank) > MAX_RAM#v(bank), [ERROR] ALLOC_GPR: RAM overflow #v(LATEST_RAM#v(RAM_BLOCK)) > max #v(MAX_RAM#v(bank)),; BOOL2INT(banked))),
;    ERRIF LAST_RAM_ADDRESS_#v(RAM_BLOCK) > RAM_END#v(BOOL2INT(banked)), [ERROR] SAFE_ALLOC: RAM overflow #v(LAST_RAM_ADDRESS_#v(RAM_BLOCK)) > end #v(RAM_END#v(BOOL2INT(banked)))
;    ERRIF LAST_RAM_ADDRESS_#v(RAM_BLOCK) <= RAM_START#v(BOOL2INT(banked)), [ERROR] SAFE_ALLOC: RAM overflow #v(LAST_RAM_ADDRESS_#v(RAM_BLOCK)) <= start #v(RAM_START#v(BOOL2INT(banked)))
;    EXPAND_POP,
;    EXPAND_POP,
    ENDM


;; misc pseudo opcodes ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    VARIABLE PAGESEL_KEEP = 0, PAGESEL_DROP = 0; ;perf stats
#define call  safe_call; override default opcode for PCH checking and BSR, WREG tracking
call macro dest
    NOEXPAND; hide clutter
    ERRIF LITPAGEOF(dest), [ERROR] dest !on page 0: #v(LITPAGEOF(dest)),
PAGESEL_DROP += 1
;    LOCAL WREG_SAVE = WREG_TRACKER
    EXPAND_RESTORE; NOEXPAND
    da 0x2000 + dest; call dest
    NOEXPAND
    if (dest == nop#v(4)) || (dest == nop#v(8)); these don't alter BSR or WREG
	exitm
    endif
    DROP_CONTEXT; BSR and WREG unknown here
    if dest == choose_next_color
WREG_TRACKER = color; kludge: avoid unknown contents warning
    endif
#ifdef BITBANG
    if dest == bitbang_wreg
BANK_TRACKER = LATA; preserve caller context to improve timing
    endif
#endif
    endm

#define goto  safe_goto; override default opcode for PCH checking
goto macro dest
    ERRIF LITPAGEOF(dest), [ERROR] dest !on page 0: #v(LITPAGEOF(dest)),
PAGESEL_DROP += 1
    EXPAND_RESTORE; NOEXPAND
    da 0x2800 + dest; goto dest
    NOEXPAND
;not needed: fall-thru would be handled by earlier code    DROP_CONTEXT; BSR and WREG unknown here if dest falls through
    endm


#define nop  multi_nop; override default opcode for PCH checking and BSR, WREG tracking
nop macro count, dummy; dummy arg for usage with REPEAT
    NOEXPAND; hide clutter
    LOCAL COUNT = count
    WARNIF !COUNT, [WARNING] no nop?,
    if COUNT & 1
        EXPAND_RESTORE; NOEXPAND
	da 0; nop
	NOEXPAND
COUNT -= 1
    endif
    if COUNT & 2
        EXPAND_RESTORE; NOEXPAND
        goto $+1; 1 instr, 2 cycles (saves space)
	NOEXPAND
COUNT -= 2
    endif
;multiples of 4:
;    if count >= 4
    if COUNT
        EXPAND_RESTORE; NOEXPAND
	call nop#v(COUNT);
	NOEXPAND
    endif
    endm


;nop2if macro want_nop
;    if want_nop
;	nop2
;    endif
;    endm

nop4if macro want_nop
    if want_nop
	nop 4,
    endif
    endm


;; 8-bit pseudo opcodes ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
;pseudo-reg:
;these have special meaning for mov8
    CONSTANT INDF1_special = 0x10000;
    CONSTANT INDF1_preinc = (INDF1_special + 0); moviw ++INDF1
    CONSTANT INDF1_predec = (INDF1_special + 1); moviw --INDF1
    CONSTANT INDF1_postinc = (INDF1_special + 2); moviw INDF1++
    CONSTANT INDF1_postdec = (INDF1_special + 3); moviw INDF1--
    CONSTANT INDF0_special = 0x20000;
    CONSTANT INDF0_preinc = (INDF0_special + 0); moviw ++INDF0
    CONSTANT INDF0_predec = (INDF0_special + 1); moviw --INDF0
    CONSTANT INDF0_postinc = (INDF0_special + 2); moviw INDF0++
    CONSTANT INDF0_postdec = (INDF0_special + 3); moviw INDF0--
#define MOVIW_opc(fsr, mode)  da 0x10 | ((fsr) == FSR1) << 2 | ((mode) & 3)
#define MOVWI_opc(fsr, mode)  da 0x18 | ((fsr) == FSR1) << 2 | ((mode) & 3)


;move (copy) reg or value to reg:
;    messg "TODO: optimize mov8 to avoid redundant loads"
;#define UNKNOWN  -1 ;non-banked or unknown
    CONSTANT WREG_UNKN = -1;
    VARIABLE WREG_TRACKER = WREG_UNKN ;unknown at start
mov8 macro dest, src
    NOEXPAND  ;reduce clutter
;    if (SRC == DEST) && ((srcbytes) == (destbytes)) && !(reverse)  ;nothing to do
    LOCAL SRC = src ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    LOCAL DEST = dest ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
;    messg "mov8", #v(DEST), #v(SRC), #v(ISLIT(SRC)), #v(LIT2VAL(SRC))
;    messg src, dest;
    if ISLIT(SRC)  ;unpack SRC bytes
; messg dest, #v(!LIT2VAL(SRC)), #v(DEST != WREG), #v(!(DEST & INDF0_special)), #v(!(DEST & INDF1_special))
	if !LIT2VAL(SRC) && (DEST != WREG) && !(DEST & INDF0_special) && !(DEST & INDF1_special)
	    BANKCHK dest;
;	    BANKSAFE 
	    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
	    EXPAND_RESTORE; NOEXPAND
	    clrf dest ;NOARG; REG2ADDR(DEST); ;special case
	    NOEXPAND
	    errorlevel +302 ;kludge: Enable bank switch warning
	    exitm
	endif
	if WREG_TRACKER != src
	    EXPAND_RESTORE ;show generated opcodes
	    movlw LIT2VAL(src)
	    NOEXPAND
WREG_TRACKER = src
	endif
    else ;register
;special pseudo-reg:
	if src & INDF0_special
	    EXPAND_RESTORE; NOEXPAND
	    MOVIW_opc(FSR0, SRC);
	    NOEXPAND  ;reduce clutter
	else
	    if src & INDF1_special
	        EXPAND_RESTORE; NOEXPAND
		MOVIW_opc(FSR1, SRC);
		NOEXPAND  ;reduce clutter
	    else
		if (SRC != WREG) && (SRC != WREG_TRACKER)
		    BANKCHK src;
;        errorlevel -302 ;kludge: Disable bank switch warning
		    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
;		    BANKSAFE 
		    EXPAND_RESTORE; NOEXPAND
		    movf src, W; REG2ADDR(SRC), W
		    NOEXPAND
		    errorlevel +302 ;kludge: Enable bank switch warning
;	errorlevel +302 ;kludge: Enable bank switch warning
;		    NOEXPAND  ;reduce clutter
WREG_TRACKER = src
		else
		    if (SRC == WREG) && (WREG_TRACKER == WREG_UNKN)
			messg [WARNING] WREG contents unknown here
		    endif
		endif
	    endif
	endif
    endif
    if dest & INDF0_special
       EXPAND_RESTORE; NOEXPAND
	MOVWI_opc(FSR0, dest);
	NOEXPAND  ;reduce clutter
    else
	if dest & INDF1_special
	    EXPAND_RESTORE; NOEXPAND
	    MOVWI_opc(FSR1, dest);
	    NOEXPAND  ;reduce clutter
	else
	    if dest != WREG
		BANKCHK dest;
;    errorlevel -302 ;kludge: Disable bank switch warning
	        errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
;		BANKSAFE 
	        EXPAND_RESTORE; NOEXPAND
		movwf dest ;NOARG; REG2ADDR(DEST)
		NOEXPAND  ;reduce clutter
	        errorlevel +302 ;kludge: Enable bank switch warning
;    errorlevel +302 ;kludge: Enable bank switch warning
	    endif
        endif
    endif
    EXPAND_RESTORE
    endm

DROP_WREG macro
    NOEXPAND
WREG_TRACKER = WREG_UNKN  ;forget latest value
    EXPAND_RESTORE
    endm


#define clrw  clrw_tracker; override default opcode for WREG tracking
;WREG tracking:
clrw macro
    mov8 WREG, LITERAL(0);
    endm

;#define moviw  moviw_tracker; override default opcode for WREG tracking
;moviw macro arg
;    moviw arg
;    DROP_WREG
;    endm

#define andlw  andlw_tracker; override default opcode for WREG tracking
andlw macro arg
;    andlw arg
    ERRIF (arg) & ~0xFF, [ERROR] extra AND bits ignored: #v((arg) & ~0xFF),
    EXPAND_RESTORE; NOEXPAND
    da 0x3900 + arg
    NOEXPAND; reduce clutter
;don't do this: (doesn't handle STATUS)
;    if WREG_TRACKER != WREG_UNKN
;WREG_TRACKER = IIF(ISLIT(WREG_TRACKER), LITERAL(WREG_TRACKER & (arg)), WREG_UNKN)
;    endif
    DROP_WREG
    endm

#define addlw  addlw_tracker; override default opcode for WREG tracking
addlw macro arg
;    addlw arg
    ERRIF (arg) & ~0xFF, [ERROR] extra ADD bits ignored: #v((arg) & ~0xFF),
    EXPAND_RESTORE; NOEXPAND
    da 0x3E00 + arg
    NOEXPAND; reduce clutter
;don't do this: (doesn't handle STATUS)
;    if WREG_TRACKER != WREG_UNKN
;WREG_TRACKER = IIF(ISLIT(WREG_TRACKER), LITERAL(WREG_TRACKER + (arg)), WREG_UNKN)
;    endif
    DROP_WREG
    endm


;; 1-bit pseudo opcodes: ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;set/clear bit:
setbit macro dest, bit, bitval
    NOEXPAND  ;reduce clutter
;    if (SRC == DEST) && ((srcbytes) == (destbytes)) && !(reverse)  ;nothing to do
;    LOCAL BIT = bit ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    LOCAL DEST = dest ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
;    messg "mov8", #v(DEST), #v(SRC), #v(ISLIT(SRC)), #v(LIT2VAL(SRC))
;    messg src, dest;
    BANKCHK dest;
    NOEXPAND  ;reduce clutter
    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
    if BOOL2INT(bitval)
;        BANKSAFE 
	EXPAND_RESTORE; NOEXPAND
	bsf dest, bit;
        NOEXPAND  ;reduce clutter
    else
;	BANKSAFE 
	EXPAND_RESTORE; NOEXPAND
	bcf dest, bit;
        NOEXPAND  ;reduce clutter
    endif
    errorlevel +302 ;kludge: Enable bank switch warning
    if dest == WREG
	if ISLIT(WREG_TRACKER)
	    if BOOL2INT(bitval)
WREG_TRACKER |= BIT(bit)
	    else
WREG_TRACKER &= ~BIT(bit)
	    endif
	else
WREG_TRACKER = WREG_UNK
	endif
    endif
    EXPAND_RESTORE
    endm


;pseudo bit reg:
#define STATUS_EQUALS  STATUS, Z

;check reg bit:
;stmt must be 1 opcode (due to btfxx instr)
;    VARIABLE STMT_COUNTER = 0
ifbit macro reg, bitnum, bitval, stmt
    NOEXPAND  ;reduce clutter
;    if (SRC == DEST) && ((srcbytes) == (destbytes)) && !(reverse)  ;nothing to do
;    LOCAL BIT = bit ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    LOCAL REG = reg ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
;    messg "mov8", #v(DEST), #v(SRC), #v(ISLIT(SRC)), #v(LIT2VAL(SRC))
;    messg src, dest;
    BANKCHK reg;
    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
    if BOOL2INT(bitval)
;        BANKSAFE 
	EXPAND_RESTORE; NOEXPAND
	btfsc reg, bitnum;
	NOEXPAND  ;reduce clutter
    else
;	BANKSAFE 
	EXPAND_RESTORE; NOEXPAND
	btfss reg, bitnum;
        NOEXPAND  ;reduce clutter
    endif
    errorlevel +302 ;kludge: Enable bank switch warning
;    LOCAL BEFORE_STMT = $
;STMT_ADDR#v(STMT_COUNTER) = 0-$
    LOCAL STMT_ADDR
STMT_ADDR = 0 - $
    LOCAL SVWREG = WREG_TRACKER
    EXPAND_RESTORE
    stmt
    NOEXPAND  ;reduce clutter
    if WREG_TRACKER != SVWREG
	DROP_WREG
	messg WREG unknown here, conditional stmt might have changed it
    endif
;STMT_ADDR#v(STMT_COUNTER) += $
STMT_ADDR += $
    LOCAL STMT_INSTR = STMT_ADDR; #v(STMT_COUNTER)
;STMT_COUNTER += 1
;    LOCAL AFTER_STMT = 0; $ - (BEFORE_STMT + 1)
    WARNIF STMT_INSTR != 1, [ERROR] if-ed stmt !1 opcode: #v(STMT_INSTR),; use warn to allow compile
    endm

;; multi-byte pseudo opcodes (little endian): ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;    messg #v(PWM3DC), #v(PWM3DCL), #v(PWM3DCH)
#define mov16  mov_mb 16,
#define mov24  mov_mb 24,
mov_mb macro len, dest, src
    NOEXPAND  ;reduce clutter
;    if (SRC == DEST) && ((srcbytes) == (destbytes)) && !(reverse)  ;nothing to do
;    LOCAL SRC = src ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
;    LOCAL DEST = dest ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    LOCAL LODEST = LO(dest);
;    messg "check HI " dest
    LOCAL HIDEST = HI(dest);
    if len > 16
;        messg "check MID " dest
	LOCAL MIDDEST = MID(dest);
        ERRIF (HIDEST != MIDDEST+1) || (MIDDEST != LODEST+1), [ERROR] dest is not 24-bit little endian, lo@#v(LODEST) mid@#v(MIDDEST) hi@#v(HIDEST)
    else
;	messg #v(len), #v(LODEST), #v(LO(dest)), #v(HIDEST), #v(HI(dest))
	ERRIF HIDEST != LODEST+1, [ERROR] dest is not 16-bit little endian: lo@#v(LODEST), hi@#v(HIDEST)
    endif
    LOCAL SRC = src ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    if ISLIT(SRC)  ;unpack SRC bytes
	mov8 LO(dest), LITERAL(SRC & 0xFF)
	if len > 16
	    mov8 MID(dest), LITERAL(SRC >> 8 & 0xFF)
	    mov8 HI(dest), LITERAL(SRC >> 16 & 0xFF)
	else
	    mov8 HI(dest), LITERAL(SRC >> 8 & 0xFF)
	endif
    else ;register
	LOCAL LOSRC = LO(src);
;        messg "get HI " src
	LOCAL HISRC = HI(src);
	mov8 LO(dest), LO(src)
	if len > 16
	    LOCAL MIDSRC = MID(src);
	    ERRIF (HISRC != MIDSRC+1) || (MIDSRC != LOSRC+1), [ERROR] src is not 24-bit little endian, lo@#v(LOSRC) mid@#v(MIDSRC) hi@#v(HISRC)
;	    messg "get MID " src
	    mov8 MID(dest), MID(src)
	else
;	    messg #v(len), #v(LOSRC), #v(LO(src)), #v(HISRC), #v(HI(src))
	    ERRIF HISRC != LOSRC+1, [ERROR] src is not 16-bit little endian: lo@#v(LOSRC), hi@#v(HISRC)
	endif
	mov8 HI(dest), HI(src)
    endif
    EXPAND_RESTORE
    endm

;kludge: need inner macro level to force arg expansion:
;#define CONCAT(lhs, rhs)  lhs#v(0)rhs

;kludge: MPASM token-pasting only occurs around #v():
#define HI(name)  name#v(0)hi ;CONCAT(name, H)
#define LO(name)  name ;leave LSB as-is to use as generic name ref ;CONCAT(name, L)
    CONSTANT HI(PWM3DC) = PWM3DCH; shim
BDCL16 macro name
    BDCL LO(name),:2
;    BDCL HI(name),
    CONSTANT HI(name) = LO(name) + 1;
;    CONSTANT name = LO(name); kludge: allow generic reference to both bytes
    endm

NBDCL16 macro name
    NBDCL LO(name),:2
;    NBDCL HI(name),
    CONSTANT HI(name) = LO(name) + 1;
;    CONSTANT name = LO(name); kludge: allow generic reference to both bytes
    endm

#define MID(name)  name#v(0)mid ;CONCAT(name, M)
BDCL24 macro name
    BDCL LO(name),:3
;    BDCL MID(name),
;    BDCL HI(name),
    CONSTANT MID(name) = LO(name) + 1;
    CONSTANT HI(name) = LO(name) + 2;
;    CONSTANT name = LO(name); kludge: allow generic reference to all 3 bytes
    endm

NBDCL24 macro name
    NBDCL LO(name),:3
;    NBDCL MID(name),
;    NBDCL HI(name),
    CONSTANT MID(name) = LO(name) + 1;
    CONSTANT HI(name) = LO(name) + 2;
;    CONSTANT name = LO(name); kludge: allow generic reference to all 3 bytes
    endm


;#endif; //WANT_HOIST
;    messg "hello 2"

    LIST
;; initialization ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;#define SPI_TEST

;pic-as, not mpasm: PSECT   code
    DROP_CONTEXT ;DROP_BANK
    ORG RESET_VECTOR
    nop 1,; reserve space for ICE debugger?
    goto init ;main
    REPEAT ISR_VECTOR - $, nop 1,; fill in empty space (avoids additional programming data block?)
;    PSECT resetVec, class="CODE", abs
;instead use  e.g. -Wl,-presetVec=0h
;    PSECT   MainCode, global, class = CODE, delta = 2

;interrupt handler:
;Timer 0 is used as a high res watchdog timer
;50 usec is a long time, so timing jitter doesn't matter (okay to use interrupt)
;NOTE: jumps to new frame handler rather than returning to interrupted code
    DROP_CONTEXT; DROP_BANK
    ORG ISR_VECTOR
;    goto ws_timeout;
;reset state for next frame:
;ws_timeout: DROP_BANK
    BANKCHK STKPTR;
    errorlevel -302  ;this is a useless/annoying message because the assembler doesn't handle it well (always generates warning when accessing registers in bank 1, even if you've set the bank select bits correctly)
;    BANKSAFE 
    decf STKPTR, F; not going to RETFIE; adjust stack manually
    errorlevel +302 ;kludge: Enable bank switch warning
;MAIN_PROG CODE                      ; let linker place main program
    goto rcv_frame
;    NOLIST

;    LIST
;busy-wait functions:
;CAUTION: use only for small delays
;use Timer-based functions for longer delays (those allow cooperative multi-tasking)
;nop7_func: nop;
;nop6_func: nop;
;nop5_func: nop;
;each level uses another stack level
;CAUTION: each level falls thru to next
nop#v(16): call nop#v(8)
nop#v(8): call nop#v(4); 1 usec @8 MIPS
nop#v(4): return; 1 usec @4 MIPS
    NOLIST


;pin assignments:
;- RA0 is WS debug output stream
;- RA1, 2, 5, 4 are WS output channels
;- RA3 is WS input stream
;peripherals used as follows:
;- Timer 0 generates interrupt for next frame after 50 usec WS idle time
;- Timer 1 gate mode measures WS input pulse width for decoding WS signal
;- Timer 2 used as PWM clock to generate first part of WS debug output stream
;- MSSP used to generate remaining part of WS debug output stream
;- CLC1-3 redirects WS input to other pins (channels)
;- CLC4 combines PWM and MSSP into WS debug output stream
;- to Timer1 gate to decode WS input data
#define WSINCH  RA3
#define DEBOUT  RA0
#define CH1OUT  RA1
#define CH2OUT  RA2
#define CH3OUT  RA5 ;TODO: use PPS to put channel 3 on RA3? (RA3 might be hard-wired for input-only)
#define CH4OUT  RA4

    CONSTANT PPS_#v(DEBOUT) = RA0PPS;
    CONSTANT PPS_#v(CH1OUT) = RA1PPS;
    CONSTANT PPS_#v(CH2OUT) = RA2PPS;
    CONSTANT PPS_#v(CH3OUT) = RA5PPS;
    CONSTANT PPS_#v(CH4OUT) = RA4PPS;


;initialize I/O pins:
;#define NO_PPS  0
iopin_init macro
    mov8 ANSELA, LITERAL(0); //all digital; CAUTION: do this before pin I/O
    mov8 WPUA, LITBIT(WSINCH); ;0x08; //weak pull-up on input pins in case not connected (ignored if MCLRE configured)
#if 0
    messg are these needed?
    mov8 ODCONA, LITERAL(0); push-pull outputs
    mov8 INLVLA, LITERAL(~0 & 0xff); shmitt trigger input levels;  = 0x3F;
    mov8 SLRCONA, LITERAL(~BIT(WSINCH) & 0xff); on = 25 nsec slew, off = 5 nsec slew; = 0x37;
#endif
    mov8 LATA, LITERAL(0); //start low to prevent junk on line
    mov8 TRISA, LITBIT(WSINCH); //0x00); //all pins are output exc RA3
;?    REPEAT RA5 - RA0 + 1, mov8 RA0PPS + repeater, LITERAL(NO_PPS); reset to LATA; is this needed? (datasheet says undefined at startup)
#if 0
    messg REMOVE THIS
    setbit LATA, CH2OUT, TRUE
;    mov8 WREG, LITERAL(1 << 4);
;    BANKSAFE xorwf LATA, F
    goto $-1
#endif
;    mov8 TRISA, LITERAL(0);
    endm


;set clock freq:
;    CONSTANT CLKDIV = (FOSC_CFG / PWM_FREQ); CLK_FREQ / HFINTOSC_FREQ);
;#define HFINTOSC_NOSC  b'110' ;use OSCFRQ; 0; no change (use cfg); should be in p16f15313.inc
#define USE_HFFRQ  b'110'; should be in p16f15313.inc
;#define PWM_FREQ  (16 MHz); (FOSC_CFG / 2); need PWM freq 16 MHz because max speed is Timer2 / 2 and Timer2 max speed is FOSC/4
;#define FOSC_FREQ  PWM_FREQ; FOSC needs to run at least as fast as needed by PWM
#define FOSC_FREQ  (32 MHz); (16 MHz); FOSC needs to be a multiple of WS half-bit time; use 4 MIPS to allow bit-banging (DEBUG ONLY)
;    CONSTANT MY_OSCCON = USE_HFFRQ << NOSC0 | 0 << NDIV0; (log2(CLKDIV) << NDIV0 | HFINTOSC_NOSC << NOSC0);
;    messg [INFO] FOSC #v(FOSC_CFG), PWM freq #v(PWM_FREQ);, CLK DIV #v(CLKDIV) => my OSCCON #v(MY_OSCCON)
;    messg [INFO], Fosc #v(FOSC_FREQ) == 4 MIPS? #v(FOSC_FREQ == 4 MIPS), WS bit freq #v(WSBIT_FREQ), #instr/wsbit #v(FOSC_FREQ/4 / WSBIT_FREQ)
clk_init macro
;    mov8 OSCCON1, LITERAL(b'110' << NOSC0 | b'0000' << NDIV0
;RSTOSC in CONFIG1 tells HFFRQ to default to 32 MHz, use 2:1 div for 16 MHz:
    setbit OSCCON3, CSWHOLD, FALSE; use new clock as soon as stable (should be immediate if HFFRQ !changed)
    mov8 OSCCON1, LITERAL(USE_HFFRQ << NOSC0 | 0 << NDIV0); MY_OSCCON); 1:1
    mov8 OSCFRQ, LITERAL(HFFRQ#v(FOSC_FREQ));
;    ERRIF CLK_FREQ != 32 MHz, [ERROR] need to set OSCCON1, clk freq #v(CLK_FREQ) != 32 MHz
;CAUTION: assume osc freq !change, just divider, so new oscillator is ready immediately
;;    ifbit PIR1, CSWIF, FALSE, goto $-1; wait for clock switch to complete
;    ifbit OSCCON3, ORDY, FALSE, goto $-1; wait for clock switch to complete
#if 0; check timing: toggle R2 @1Hz
 #define WANT_BUSYWAIT
    messg REMOVE THIS
hbloop: DROP_CONTEXT; DROP_BANK
    setbit LATA, CH2OUT, TRUE;
    call wait_1sec
    setbit LATA, CH2OUT, FALSE;
    call wait_1sec;
    goto hbloop
#endif
    endm


;#ifdef WANT_BUSYWAIT
#if 0
    messg REMOVE busy wait 1 sec
    LIST
;busy-wait (for dev/test ONLY):
;CAUTION: stack depth grows with longer delay period
wait_64usec: call wait_32usec; 16 instr; fall thru + return second time
wait_32usec: call wait_16usec; 16 instr; fall thru + return second time
wait_16usec: call wait_8usec; 16 instr; fall thru + return second time
wait_8usec: call wait_4usec; 16 instr; fall thru + return second time
wait_4usec: call wait_2usec; 16 instr; fall thru + return second time
wait_2usec: call wait_1usec; 8 instr; fall thru + return second time
wait_1usec:
#if FOSC_FREQ == 8 MIPS ;need one extra level for 8 MIPS
    call wait_500nsec;
wait_500nsec:
#else
    ERRIF FOSC_FREQ != 4 MIPS, [TODO] unhandled FOSC: #v(FOSC_FREQ), use 4 or 8 MIPS
#endif
    return; 4 instr call+return @4 MIPS == 1 usec
;    BDCL idleL
wait_1msec: DROP_CONTEXT; DROP_BANK
    nop;
    mov8 WREG, LITERAL(1000/4 - 1);
    goto loop_4usec+1
loop_4usec: DROP_CONTEXT; DROP_BANK
    call wait_1usec;
    call wait_2usec;
    nop;
;    BANKSAFE 
    decfsz WREG, F
    goto loop_4usec
    return
    NOLIST

;kludge: eat dummy arg
;(MPASM doesn't allow optional args)
wrapper1 macro stmt, ignore
    stmt
    endm

;    NBDCL onesec,
;wait_halfsec: DROP_CONTEXT;
;    mov8 onesec, LITERAL(500 / 2);
;loop_halfsec: DROP_CONTEXT; DROP_BANK
;    REPEAT 2, wrapper1 call wait_1msec, NOARG;
;    decfsz onesec, F
;    goto loop_halfsec;
;    return;
;    NOLIST
;
;wait_qtrsec: DROP_CONTEXT;
;    mov8 onesec, LITERAL(250);
;loop_1sec: DROP_CONTEXT; DROP_BANK
;    call wait_1msec;
;    decfsz onesec, F
;    goto loop_1sec;
;    return;
;    NOLIST
;
;wait_1sec: DROP_CONTEXT; DROP_BANK
;    mov8 onesec, LITERAL(1000 / 4);
;loop_1sec: DROP_CONTEXT; DROP_BANK
;    REPEAT 4, wrapper1 call wait_1msec, NOARG;
;    decfsz onesec, F
;    goto loop_1sec;
;    return;
#endif; WANT_BUSYWAIT


;disable unused peripherals:
;saves a little power, helps prevent accidental interactions
#define ENABLED(n)  NOBIT(n); all peripherals are ON by default
#define DISABLED(n)  BIT(n)
pmd_init macro
;?    mov8 ODCONA, LITERAL(0); //all push-pull out (default), no open drain
;?    mov8 SLRCONA, LITERAL(~BIT(RA3)); //0x37); //limit slew rate, all output pins 25 ns vs 5 ns
;?    mov8 INLVLA, LITERAL(~BIT(RA3)); //0x3F); //TTL input levels on all input pins
;??    mov8 RA4PPS, LITERAL(0x01);   ;RA4->CLC1:CLC1OUT;    
;??    mov8 RA5PPS, LITERAL(0x01);   ;RA5->CLC1:CLC1OUT;    
;??    mov8 RA1PPS, LITERAL(0x01);   ;RA1->CLC1:CLC1OUT;    
;??    mov8 RA2PPS, LITERAL(0x01);   ;RA2->CLC1:CLC1OUT;    
;??    mov8 RA0PPS, LITERAL(0x16);   ;RA0->MSSP1:SDO1;    
;    setbit PMD0, FVRMD, DISABLED;
;    setbit PMD0, NVMMD, DISABLED;
;    setbit PMD0, CLKRMD, DISABLED;
;    setbit PMD0, IOCMD, DISABLED;
    mov8 PMD0, LITERAL(ENABLED(SYSCMD) | DISABLED(FVRMD) | DISABLED(NVMMD) | DISABLED(CLKRMD) | DISABLED(IOCMD)); keep sys clock, disable FVR, NVM, CLKR, IOC
;    setbit PMD1, NCOMD, DISABLED;
    mov8 PMD1, LITERAL(DISABLED(NCOMD) | ENABLED(TMR2MD) | ENABLED(TMR1MD) | ENABLED(TMR0MD)); disable NCO, enabled Timer 0 - 2
;    setbit PMD2, DAC1MD, DISABLED;
;    setbit PMD2, ADCMD, DISABLED;
;    setbit PMD2, CMP1MD, DISABLED;
;    setbit PMD2, ZCDMD, DISABLED;
    mov8 PMD2, LITERAL(DISABLED(DAC1MD) | DISABLED(ADCMD) | DISABLED(CMP1MD) | DISABLED(ZCDMD)); disable DAC1, ADC, CMP1, ZCD
;    setbit PMD3, PWM6MD, DISABLED;
;    setbit PMD3, PWM5MD, DISABLED;
;    setbit PMD3, PWM4MD, DISABLED;
;    setbit PMD3, CCP2MD, DISABLED;
;    setbit PMD3, CCP1MD, DISABLED;
    mov8 PMD3, LITERAL(DISABLED(PWM6MD) | DISABLED(PWM5MD) | DISABLED(PWM4MD) | ENABLED(PWM3MD) | DISABLED(CCP2MD) | DISABLED(CCP1MD)); enable PWM 3, disable PWM 4 - 6, CCP 1 - 2
;    setbit PMD4, UART1MD, DISABLED;
;    setbit PMD4, CWG1MD, DISABLED;
    mov8 PMD4, LITERAL(DISABLED(UART1MD) | ENABLED(MSSP1MD) | DISABLED(CWG1MD)); disable EUSART1, CWG1, enable MSSP1
;    setbit PMD5, CLC4MD, DISABLED; IIFDEBUG(ENABLED, DISABLED);
;    setbit PMD5, CLC3MD, DISABLED;
;    mov8 PMD5, LITERAL(DISABLED(CLC4MD) | DISABLED(CLC3MD) | ENABLED(CLC2MD) | ENABLED(CLC1MD)); disable CLC 3, 4, enable CLC 1, 2
    mov8 PMD5, LITERAL(ENABLED(CLC4MD) | ENABLED(CLC3MD) | ENABLED(CLC2MD) | ENABLED(CLC1MD)); disable CLC 3, 4, enable CLC 1, 2
    endm


;redirect WS input stream to another output pin:
;;;kludge: RA3 not directly available to Timer 1, route via CLC1-3 out:
;;;need to redirect RA3 to output channels 1 - 4 anyway
#define LC1MODE_4AND  b'010'; should be in p16f15313.inc
#define LCIN3PPS  3; should be in p16f15313.inc
#define LCIN_TMR0  12; should be in p16f15313.inc
#define PPS_PWM3OUT  H'0B'; should be in p16f15313.inc
;#define LCINFOSC  4; sim/test only
#define PPS_CLC1OUT  1; should be in p16f15313.inc
#define PPS_CLC2OUT  2; should be in p16f15313.inc
#define PPS_CLC3OUT  3; should be in p16f15313.inc
#define INVERT(n)  BIT(n)
#define NONINVERT(n)  NOBIT(n)
;NOTE: control bits are the same for each CLC; only need to use #v(clc) when they are different (register names)
chout_init macro clc
    if clc == 1
        mov8 CLCIN3PPS, LITERAL(WSINCH); CAUTION: CLCIN0PPS not available to CLCxSELy? use CLCIN3PPS instead
    endif
;CLCIN0 defaults to RA3?; leave it as-is
;    messg ^^^ is this needed?
;3 CLCs are used so WS signal can be directed onto 3 separate output channels:
    mov8 CLC#v(clc)CON, LITERAL(NOBIT(LC1EN) | NOBIT(LC1INTP) | NOBIT(LC1INTN) | LC1MODE_4AND << LC1MODE0); disable during config, no int, 4-way AND
;    setbit CLC1CON, LC1EN, FALSE; datasheet says to disable CLC during setup
;??is this default?    mov8 CLCIN0PPS, LITERAL(WSINCH); CAUTION: CLCIN0PPS not available to CLCxSELy? (datasheet omission might be incorrect though)
;CLC4 pass-thru example from AN1451 (data 2 in gate 2 -> RC4):
;    CLC4GLS0 = 0; CLC4GLS1 = 8; CLC4GLS2 = 0; CLC4GLS3 = 0;
;    CLC4SEL0 = 0; CLC4SEL1 = 0;
;    CLC4POL = 0xD;
;    CLC4CON = 0xC2;
;    REPEAT 4, mov8 CLC4SEL0 + repeater, LITERAL(NO_PPS); set later
;don't care?    REPEAT 3, mov8 CLC1SEL0 + repeater, LITERAL(NO_PPS);
;CAUTION: CLCIN0PPS not available to CLCxSELy?  use CLCIN3 instead
    mov8 CLC#v(clc)SEL0, LITERAL(LCIN3PPS); LCIN_TMR0); LCIN_FOSC); input selection
;    REPEAT 4, mov8 CLC#v(clc)SEL0 + repeater, LITERAL(LCIN3PPS); LCIN_TMR0); LCIN_FOSC); input selection
;    mov8 CLC1SEL0, LITERAL(LCIN_TMR0); LCINFOSC); (WSINCH);
;    messg REMOVE ^^^
;    REPEAT 4, mov8 CLC4GLS0 + repeater, LITERAL(0xAA); all data gated, !inverted
;    mov8 CLC1GLS0, LITERAL(BIT(LC1G1D4T)); Gate 4 Data 4 True (!inverted) routed into CLC1 Gate 4
;    REPEAT 3, mov8 CLC1GLS1 + repeater, LITERAL(0); gate 0 - 3 data !routed
;    mov8 CLC1POL, LITERAL(NOBIT(LC1POL) | BIT(LC1G4POL) | BIT(LC1G3POL) | BIT(LC1G2POL) | NOBIT(LC1G1POL)); !inverted output, unused inputs inverted
;do unused inputs need to be set?  for safety, set them all the same:
;NOTE: data gating !defined @startup; need to set all 4 data sel reg here?
;    REPEAT 4, mov8 CLC1GLS0 + repeater, LITERAL(0); no inputs routed => constant 0
;    mov8 CLC1GLS0, LITERAL(BIT(LC1G1D4T)); CLCIN3 routed to gate 0 data 1
;#if 1
    REPEAT 4, mov8 CLC#v(clc)GLS0 + repeater, LITERAL(IIF(repeater, 0, BIT(LC1G1D1T))); no inputs routed => constant 0; CLCIN3 routed to gate 0 data 1
    mov8 CLC#v(clc)POL, LITERAL(NONINVERT(LC1POL) | INVERT(LC1G4POL) | INVERT(LC1G3POL) | INVERT(LC1G2POL) | NONINVERT(LC1G1POL)); !inverted output, unused inputs inverted
;#else
;    REPEAT 4, mov8 CLC#v(clc)GLS0 + repeater, LITERAL(BIT(LC1G1D1T)); no inputs routed => constant 0; CLCIN3 routed to gate 0 data 1
;    mov8 CLC#v(clc)POL, LITERAL(NONINVERT(LC1POL) | NONINVERT(LC1G4POL) | NONINVERT(LC1G3POL) | NONINVERT(LC1G2POL) | NONINVERT(LC1G1POL)); !inverted output, unused inputs inverted
;    messg REINSTATE
;#endif
    setbit CLC#v(clc)CON, LC1EN, TRUE;
;#ifdef WANT_DEBUG
;    messg [DEBUG] sending CLC1 out (WS in) to RA2
;    mov8 RA2PPS, LITERAL(PPS_CLC1OUT);
;    messg sending PWM3 to RA5
;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT);
;#endif
    endm


;Timer 0:
;used to detect 50 usec WS281X reset pulse
;WDT period is not short enough, so use T0 as pseudo-WDT; ISR handles timeout
#define T0SRC_FOSC4  b'010'; FOSC / 4; should be in p16f15313.inc
#define T0_prescaler(freq)  log2(FOSC_FREQ / 4 / (freq)); (1 MHz)); set pre-scalar for 1 usec ticks
#define T0_prescfreq(prescaler)  (FOSC_FREQ / 4 / BIT(prescaler)); (1 MHz)); set pre-scalar for 1 usec ticks
;    messg ^^ REINSTATE
#define T0_postscale  log2(1); 1-to-1 post-scalar
    CONSTANT MAX_T0PRESCALER = 15;
#define T0_ROLLOVER  50; 50 ticks @1 usec = 50 usec; WS281X latch time = 50 usec
;    messg [DEBUG] T0 prescaler = #v(T0_prescale), should be 2 (1:4)
ws_clrwdt macro int_occurred
    mov8 TMR0L, LITERAL(0); restart 50 usec count-down; caller should restart whenever data received
    if int_occurred
        setbit PIR0, TMR0IF, FALSE; clear previous interrupt
        setbit INTCON, GIE, TRUE; (re-)enable interrupts
    endif
    endm
#define MY_T0CON1(tick_freq)  (T0SRC_FOSC4 << T0CS0 | NOBIT(T0ASYNC) | T0_prescaler(tick_freq) << T0CKPS0); FOSC / 4, sync, pre-scalar TBD (1:1 for now)
tmr0_init macro
    mov8 T0CON0, LITERAL(NOBIT(T0EN) | NOBIT(T016BIT) | T0_postscale << T0OUTPS0); Timer 0 disabled during config, 8 bit mode, 1:1 post-scalar
;    mov8 T0CON1, LITERAL(MY_T0CON1(1 MHz)); T0SRC_FOSC4 << T0CS0 | NOBIT(T0ASYNC) | T0_prescale << T0CKPS0); FOSC / 4, sync, 8:1 pre-scalar
;    mov8 TMR0H, LITERAL(T0_ROLLOVER); int takes 1 extra tick but this accounts for a few instr at start of ISR
;;    mov8 TMR0L, LITERAL(0)
;later    ws_clrwdt FALSE; prevent premature interrupt; ensure first WS reset occurs at correct time
;    setbit T0CON0, T0EN, TRUE;
    wait_usec 50, ORG $-1; goto tmr0_init_done; setup but don't wait
;tmr0_init_done: DROP_CONTEXT
    setbit PIE0, TMR0IE, TRUE;
    endm


;general purpose delay routines:
;use idler for cooperative multi-tasking
wait_sec macro sec, idler
    wait_msec sec * 1000, idler
    endm

wait_msec macro msec, idler
    wait_usec msec * 1000, idler
    endm

;CAUTION: these are mainly for debug/test/animation; they assume WS input stream !active
    VARIABLE WAIT_COUNT = 1; generate unique labels
;    CONSTANT MAX_ACCURACY = 1 << 20; 1 MHz; max accuracy to give caller; use nop for < 1 usec delays
wait_usec macro interval_usec, idler
    LOCAL USEC = interval_usec;
;    setbit INTCON, GIE, FALSE; disable interrupts (in case waiting for 50 usec WS latch signal)
;    if usec == 1
;    movlw ~(b'1111' << T0CKPS0) & 0xFF; prescaler bits
;    BANKCHK T0CON1
;    andwf T0CON1, F; strip previous prescaler
    setbit T0CON0, T0EN, FALSE;
    mov8 TMR0L, LITERAL(0); restart count-down with new limit
;    LOCAL ACCURACY = MAX_ACCURACY; 1 MHz; max accuracy to give caller; use nop for < 1 usec delays
    LOCAL PRESCALER = 3;
    LOCAL T0tick, LIMIT, ROLLOVER;
    LOCAL FREQ_FIXUP; = FOSC_FREQ / 4 / BIT(PRESCALER);
;    while ACCURACY >= 1 << 7; 125 Hz
    while PRESCALER <= MAX_T0PRESCALER; use smallest prescaler for best accuracy
;T0FREQ = FOSC_FREQ / 4 / BIT(PRESCALER); T0_prescfreq(PRESCALER);
T0tick = BIT(PRESCALER) KHz / (FOSC_FREQ / (4 KHz)); split 1M factor to avoid arith overflow; BIT(PRESCALER - 3); usec
;presc 1<<3, freq 1 MHz, period 1 usec, max delay 256 * usec
;presc 1<<5, freq 250 KHz, period 4 usec, max delay 256 * 4 usec ~= 1 msec
;presc 1<<8, freq 31250 Hz, period 32 usec, max delay 256 * 32 usec ~= 8 msec
;presc 1<<13, freq 976.6 Hz, period 1.024 msec, max delay 256 * 1.024 msec ~= .25 sec
;presc 1<<15, freq 244.1 Hz, period 4.096 msec, max delay 256 * 4.096 msec ~= 1 sec
LIMIT = 256 * T0tick; (1 MHz / T0FREQ); BIT(PRESCALER - 3); 32 MHz / (FOSC_FREQ / 4); MAX_ACCURACY / ACCURACY
;	messg [DEBUG] wait #v(interval_usec) usec: prescaler #v(PRESCALER) => limit #v(LIMIT)
;        messg tick #v(T0tick), presc #v(PRESCALER), max delay #v(LIMIT) usec
	if interval_usec <= LIMIT; this prescaler allows interval to be reached
ROLLOVER = rdiv(interval_usec, T0tick); 1 MHz / T0FREQ); / BIT(PRESCALER - 3)
	    messg [DEBUG] wait #v(interval_usec) usec: prescaler #v(PRESCALER), t0tick #v(T0tick), max #v(LIMIT), actual #v(ROLLOVER * T0tick), rollover #v(ROLLOVER)
;    messg log 2: #v(FOSC_FREQ / 4) / #v(FOSC_FREQ / 4 / BIT(PRESCALER)) = #v(FOSC_FREQ / 4 / (FOSC_FREQ / 4 / BIT(PRESCALER))); (1 MHz)); set pre-scalar for 1 usec ticks
FREQ_FIXUP = 1 MHz / T0tick; T0FREQ;
;	    if T0FREQ * BIT(PRESCALER) != FOSC_FREQ / 4; account for rounding errors
	    if T0tick * FREQ_FIXUP != 1 MHz; account for rounding errors
;	        messg freq fixup: equate #v(FOSC_FREQ / 4 / MAX(FREQ_FIXUP, 1)) to #v(BIT(PRESCALER)) for t0freq #v(FREQ_FIXUP) fixup
		CONSTANT log2(FOSC_FREQ / 4 / MAX(FREQ_FIXUP, 1)) = PRESCALER; kludge: apply prescaler to effective freq
	    endif
	    mov8 T0CON1, LITERAL(MY_T0CON1(MAX(FREQ_FIXUP, 1))); FREQ_FIXUP)); FOSC_FREQ / 4 / BIT(PRESCALER)));
	    mov8 TMR0H, LITERAL(ROLLOVER - 1); (usec) / (MAX_ACCURACY / ACCURACY) - 1);
	    setbit T0CON0, T0EN, TRUE;
	    setbit PIR0, TMR0IF, FALSE; clear previous interrupt
wait_loop#v(WAIT_COUNT):
WAIT_COUNT += 1
	    idler;
	    if $ < wait_loop#v(WAIT_COUNT - 1); reg setup only; caller doesn't want to wait
		ORG wait_loop#v(WAIT_COUNT - 1)
		exitm
	    endif
;assume idler handles BSR + WREG tracking; not needed:
;	    if $ > wait_loop#v(WAIT_COUNT - 1)
;		DROP_CONTEXT; TODO: idler hints; for now assume idler changed BSR or WREG
;	    endif
	    ifbit PIR0, TMR0IF, FALSE, goto wait_loop#v(WAIT_COUNT - 1); wait for timer roll-over
;ACCURACY = 1 KHz; break out of loop	    exitwhile
;    if usec >= 256
;	movlw ~(b'1111' << T0CKPS0) & 0xFF; prescaler bits
;	BANKCHK T0CON1
;	andwf T0CON1, F; strip temp prescaler
;	iorwf T0CON1, T0_prescale << T0CKPS0; restore original 8:1 pre-scalar used for WS input timeout
;    endif
;    mov8 TMR0H, LITERAL(T0_ROLLOVER); restoreint takes 1 extra tick but this accounts for a few instr at start of ISR
	    exitm
	endif
PRESCALER += 1
;FREQ_FIXUP = IIF(FREQ_FIXUP == 31250, 16000, FREQ_FIXUP / 2);
    endw
    error [ERROR] wait #v(interval_usec) usec exceeds max #v(LIMIT), suitable prescaler !found
;    if usec <= 256
;;	iorwf T0CON1, T0_prescale << T0CKPS0; restore original 8:1 pre-scalar used for WS input timeout
;        mov8 T0CON1, LITERAL(MY_T0CON1(1 MHz));
;        mov8 TMR0H, LITERAL(usec - 1);
;    else
;	if usec <= 1 M; 1 sec
;            mov8 T0CON1, LITERAL(MY_T0CON1(250 Hz));
;	    mov8 TMR0H, LITERAL((usec) / (1 KHz) - 1);
;	else
;	    if usec <= 256 K
;		mov8 T0CON1, LITERAL(MY_T0CON1(1 KHz));
;		mov8 TMR0H, LITERAL((usec) / (1 KHz) - 1);
;	    else
;	    endif
;	endif
;    endif
    endm


;start acq:
tmr1_acq macro
    setbit T1GCON, T1GGO, TRUE;
    ifbit PIR5, TMR1GIF, FALSE, goto $-1
    endm
;Timer 1 gate init (used to capture WS281X input bit):
;see AN1473 for details about Single-Pulse mode
#define T1SRC_FOSC  b'10'; should be in p16f15313.inc
#define T1_prescale  log2(1) ;(0 << T1CKPS0); 1-to-1 pre-scalar
;#define T1GSS_LC1OUT  (b'01101' << T1GSS0); kludge: RA3 not directly available, route via CLC1 out
#define WSBIT_THRESHOLD  8; 16 osc ticks @16 MHz = 0.5 usec
;#define LC1MODE_4AND  (b'010' << LC1MODE0)
;#define T1GPPS_PPS  0; should be in p16f15313.inc
#define T1GATE_LC1OUT  b'01101'; LC1_out should be in p16f15313.inc
;#define LCIN_FOSC  4
;#define LCIN_TMR0  12
;#define LCIN3PPS  3
;#define PPSOUT_CLC1OUT  1
tmr1_init macro
;    bsf T1CON, TMR1ON;
;    mov8 T1GPPS, LITERAL(WSINCH); T1GSS_LC1OUT);
    mov8 T1CON, LITERAL(NOBIT(TMR1ON) | T1_prescale << T1CKPS0 | XBIT(T1SYNC) | BIT(T1RD16)); Timer 1 disabled during config, 1:1 prescalar, 16 bit read, sync ignored
    mov8 T1GCON, LITERAL(BIT(T1GE) | BIT(T1GSPM) | BIT(T1GPOL) | NOBIT(T1GTM) | NOBIT(T1GGO)); Gate Single-Pulse mode, active high, no toggle, don't acquire yet
    mov8 T1CLK, LITERAL(T1SRC_FOSC); 32 MHz (32 nsec reslution)
    mov8 T1GATE, LITERAL(T1GATE_LC1OUT); RA3 goes in to CLC1 so use it here; T1GPPS_PPS); =T1GPPS;
    setbit T1CON, TMR1ON, TRUE;
#if 1
;kludge: RA3 not directly available to Timer 1, route via CLC1 out:
;need to redirect RA3 to output channels 1 - 4 anyway
    mov8 CLCIN3PPS, LITERAL(WSINCH); CAUTION: CLCIN0PPS not available to CLCxSEL0?
;CLC4 pass-thru example from AN1451 (data 2 in gate 2 -> RC4):
;    CLC4GLS0 = 0; CLC4GLS1 = 8; CLC4GLS2 = 0; CLC4GLS3 = 0;
;    CLC4SEL0 = 0; CLC4SEL1 = 0;
;    CLC4POL = 0xD;
;    CLC4CON = 0xC2;
;    REPEAT 4, mov8 CLC4SEL0 + repeater, LITERAL(NO_PPS); set later
;    REPEAT 3, mov8 CLC1SEL0 + repeater, LITERAL(0); NO_PPS);
;    mov8 CLC1SEL3, LITERAL(LCIN_TMR0); LCIN_FOSC); (LCIN3PPS); input selection
    mov8 CLC1SEL3, LITERAL(LCIN3PPS); input selection
;    messg REINSTATE ^^^
;    REPEAT 4, mov8 CLC4GLS0 + repeater, LITERAL(0xAA); all data gated, !inverted
;    REPEAT 3, mov8 CLC1GLS0 + repeater, LITERAL(0); gate 0 - 3 data !routed
;    mov8 CLC1GLS3, LITERAL(BIT(LC1G4D4T)); Gate 4 Data 4 True (!inverted) routed into CLC1 Gate 4
    REPEAT 4, mov8 CLC1GLS0 + repeater, LITERAL(IIF(repeater == 3, BIT(LC1G4D4T), 0)); gate 0 - 3 data !routed
    mov8 CLC1POL, LITERAL(NOBIT(LC1POL) | NOBIT(LC1G4POL) | BIT(LC1G3POL) | BIT(LC1G2POL) | BIT(LC1G1POL)); !inverted output, unused inputs inverted
    mov8 CLC1CON, LITERAL(BIT(LC1EN) | NOBIT(LC1INTP) | NOBIT(LC1INTN) | LC1MODE_4AND); enable, no int, 4-way AND
;#ifdef WANT_DEBUG
;    messg sending CLC1 out (WS in) to RA4
;    mov8 RA4PPS, LITERAL(PPS_CLC1OUT);
;#endif
#endif
    endm


;set up Timer2 to run at 2x WS freq (SPI sync uses T2/2):
;see https://microchipdeveloper.com/8bit:10bitpwm
#define T2SRC_FOSC4  b'001'; FOSC / 4 (required by PWM); should be in p16f15313.inc
;#define T2SRC_FOSC  b'0010'; run Timer2 at same speed as Fosc (16 MHz)
#define T2_prescale  log2(1) ;(0 << T2CKPS0); 1-to-1 pre-scalar
#define T2_postscale  log2(1) ;(0 << T2OUTPS0); 1-to-1 post-scalar
#define T2_FREERUNNING  0; should be in p16f15313.inc
;#define PWM_FREQ  (16 MHz); (FOSC_CFG / 2); need PWM freq 16 MHz because max speed is Timer2 / 2 and Timer2 max speed is FOSC
#define PR2VAL  (FOSC_FREQ / 4 / WSBIT_FREQ); 8 MIPS / 800 KHz == 10; 4 MIPS / 800 KHz == 5
#define PR2VAL_2x  (PR2VAL / 2); run T2 @ 2x SPI freq (only option for SPI sync with T2+PWM)
;#define DUTY  (4 * PR2VAL * 3/16); 3/16 of 1.25 usec =~ 0.25 usec; NO: 3/10 of 1.25 usec == .375 usec ~= 6/16 pwm duty
;    messg [INFO] TMR2 period #v(PR2VAL - 1) = PR2VAL - 1, PWM3 duty #v(DUTY) = DUTY
    messg [INFO] Fosc = #v(mhz(FOSC_FREQ)) M Hz, 4 MIPS? #v(FOSC_FREQ == 4 MIPS), 8 MIPS? #v(FOSC_FREQ == 8 MIPS)
    messg [INFO] WS bit freq = #v(khz(WSBIT_FREQ)) K Hz, #instr/wsbit bit-bang = #v(FOSC_FREQ/4 / WSBIT_FREQ)
    messg [INFO] TMR2 prval 2x = #v(PR2VAL_2x), pr2val 1x = #v(PR2VAL) = PR2VAL
tmr2_init macro
;    mov8 PWM3CON, LITERAL(NOBIT(PWM3EN) | NOBIT(PWM3POL)); disabled during config, active high
;;    mov8 PWM3DCH, LITERAL(DUTY >> 2); 8 msb
;;    mov8 PWM3DCL, LITERAL((DUTY & 3) << 6); 2 lsb
;    mov16 PWM3DC, LITERAL(DUTY << 6); 10 msb of 16-bit value
;    setbit PWM3CON, PWM3EN, TRUE;
    mov8 T2CON, LITERAL(NOBIT(T2ON) | T2_prescale << T2CKPS0 | T2_postscale << T2OUTPS0); disable Timer 2 during config, 1:1 pre- and post- scalars
    mov8 T2PR, LITERAL(PR2VAL_2x - 1); 8 MIPS / 10 = 800 KHz; gives 4 bits res?
    mov8 T2CLKCON, LITERAL(T2SRC_FOSC4 << T2CS0); 16 MHz/4 = 4 MHz
;#define T2MODE  (b'00' << T2MODE0)
    mov8 T2HLT, LITERAL(BIT(PSYNC) | NOBIT(CKPOL) | BIT(CKSYNC) | T2_FREERUNNING << T2MODE0); sync to FOSC/4, rising edge, ON sync, free-running
;    mov8 T2RST, LITERAL(0); no need to reset???
    mov8 TMR2, LITERAL(0); start with clean cycle
    setbit T2CON, T2ON, TRUE;
    endm


;generate WS debout output via SPI using Timer 2, PWM, MSSP, using CLC to combine them:
;see AN1606 for details about custom SPI peripheral using CLC + Timer2 + PWM + MSSP (CAUTION: AN1606 is half-speed)
;see https://deepbluembedded.com/spi-tutorial-with-pic-microcontrollers/
;don't see https://ww1.microchip.com/downloads/en/Appnotes/TB3192-Using-the-SPI-Module-on-8-Bit-PIC-MCUs-90003192A.pdf
;NO #define SPI_FOSC4  0; use FOSC/4 (8 MHz); should be in p16f15313.inc
#define SPI_T2HALF  b'0011'; use TMR2/2 (SPI must be synced to PWM on T2); should be in p16f15313.inc
;#define CLC1OUT  1; should be in p16f15313.inc
#define PPS_CLC4OUT  4; should be in p16f15313.inc
#define LC4MODE_ANDOR  0; should be in p16f15313.inc
;#define LCIN3PPS  3; should be in p16f15313.inc
#define LCIN_PWM3  b'010001'; should be in p16f15313.inc
#define LCIN_SDO  b'100010'; should be in p16f15313.inc
#define LCIN_SCK  b'100011'; should be in p16f15313.inc
;#define PPS_PWM3OUT  H'0B'; should be in p16f15313.inc
;;#define LCINFOSC  4; sim/test only
;#define PPSOUT_CLC1OUT  1; should be in p16f15313.inc
#define DUTY  (4 * PR2VAL_2x * 1/3); (PRVAL/2 * 1/4); rdiv(PRVAL * 3, 2 * 16); (PR2VAL/2 * 3/16); 3/16 of 1.25 usec =~ 0.25 usec; NO: 3/10 of 1.25 usec == .375 usec ~= 6/16 pwm duty
;    messg [INFO] TMR2 period #v(PR2VAL - 1) = PR2VAL - 1, PWM3 duty #v(DUTY) = DUTY
    messg [INFO] PWM3 duty #v(DUTY) = DUTY
;    messg [INFO], Fosc #v(FOSC_FREQ) == 4 MIPS? #v(FOSC_FREQ == 4 MIPS), WS bit freq #v(WSBIT_FREQ), #instr/wsbit #v(FOSC_FREQ/4 / WSBIT_FREQ), TMR2 period #v(PR2VAL - 1) = PR2VAL - 1
spi_init macro
    tmr2_init;
    mov8 PWM3CON, LITERAL(NOBIT(PWM3EN) | NOBIT(PWM3POL)); disabled during config, active high
;    mov8 PWM3DCH, LITERAL(DUTY >> 2); 8 msb
;    mov8 PWM3DCL, LITERAL((DUTY & 3) << 6); 2 lsb
    mov16 PWM3DC, LITERAL(DUTY << 6); 10 msb of 16-bit value
    setbit PWM3CON, PWM3EN, TRUE;
;MSSP used for SPI out of WS data (debug):
;not used    mov8 SSP1CLKPPS, LITERAL(16);
    setbit PIR3, SSP1IF, TRUE; kludge: pretend last byte was sent so send won't wait
    mov8 SSP1CON1, LITERAL(NOBIT(SSPEN) | NOBIT(WCOL) | NOBIT(SSPOV) | NOBIT(CKP) | SPI_T2HALF << SSPM0); MSSP disable during config, no collision, no overflow, clock active high, SPI master @ T2/2 (needs to be synced with PWM)
    mov8 SSP1STAT, LITERAL(NOBIT(SMP) | BIT(CKE)); SPI master mode, xmit on rising clock edge, sample at middle
    messg [TODO] CKE? need SDO stable when SCK is active/high
;#define SPI_TMR2_half  (b'0011' << SSPM0); use Timer2/2
    mov8 SSP1ADD, LITERAL(PR2VAL_2x - 1); SPI baud rate: 800KHz (1.25 usec) with 16MHz osc (4 MIPS, 0.25 usec) = 5
;    mov8, RA0PPS
;    mov8 CLCIN0PPS, LITERAL(RA3); //0x03);   ;RA3->CLC1:CLCIN0;
    setbit SSP1CON1, SSPEN, TRUE;
;use CLC4 to combine start + data bit parts into complete WS signal:
    mov8 PPS_#v(DEBOUT), LITERAL(PPS_CLC4OUT); send WS signal to channel 0 (RA0)
    mov8 CLC4CON, LITERAL(NOBIT(LC4EN) | NOBIT(LC1INTP) | NOBIT(LC2INTN) | LC4MODE_ANDOR << LC4MODE0); disable during config, no int, AND-OR
    mov8 CLC4SEL0, LITERAL(LCIN_SCK);
    mov8 CLC4SEL1, LITERAL(LCIN_SDO);
 ;messg are ^^^ these correct?
    mov8 CLC4SEL2, LITERAL(LCIN_PWM3);
;    mov8 CLC2SEL3, LITERAL(0);
    mov8 CLC4GLS0, LITERAL(BIT(LC4G1D1T)); SCK; | BIT(LC2G1D2T)); SCK & SDO
    mov8 CLC4GLS1, LITERAL(BIT(LC4G2D2T)); SDO; | BIT(LC2G2D2N) | BIT(LC2G2D3T)); SCK & !SDO & PWM3
    mov8 CLC4GLS2, LITERAL(BIT(LC4G3D1T)); SCK; | BIT(LC2G1D2T)); SCK & SDO
    mov8 CLC4GLS3, LITERAL(BIT(LC4G4D2T) | BIT(LC4G4D3N)); SDO + !PWM3; | BIT(LC2G2D3T)); SCK & !SDO & PWM3
;#define INVERT(n)  BIT(n)
;#define NONINV(n)  NOBIT(n)
    mov8 CLC4POL, LITERAL(NONINVERT(LC4POL) | NONINVERT(LC4G1POL) | NONINVERT(LC4G2POL) | NONINVERT(LC4G3POL) | INVERT(LC4G4POL)); combine parts into complete WS signal
    setbit CLC4CON, LC4EN, TRUE;
    endm

;wait for previous byte to finish sending (to avoid collision):
;spi_wait_byte macro
;    ifbit SSP1STAT, BF, FALSE, goto $-1; avoid collision; wait for previous byte to finish
;    endm
;send 8 bits of data (WREG) via SPI:
;send_spi_byte: DROP_BANK
spi_waitif macro want_wait
;        ifbit SSP1STAT, BF, FALSE, goto $-1; avoid collision; wait for previous byte to finish
    if want_wait
        ifbit PIR3, SSP1IF, FALSE, goto $-1; wait for SPI xmit complete
	setbit PIR3, SSP1IF, FALSE;
    endif
    endm

;use custom SPI peripheral to send next byte of WS281X data:
;optional wait before/after each byte
;synchronous send takes 10 usec, async is 1-2 instr (0.25-0.5 usec)
#ifdef BITBANG
    messg [INFO] SPI using bit-bang with busy-wait, DEV/DEBUG ONLY!
;kludge: parameterless wrappers (for use with ifbit):
spitbit_#v(0) macro
; messg [DEBUG] bsr @spitbit_0: #v(BANK_TRACKER)
    setbit LATA, RA5, 0
    endm
spitbit_#v(1) macro
; messg [DEBUG] bsr @spitbit_1: #v(BANK_TRACKER)
    setbit LATA, RA5, 1
    endm
;bitbang next WS byte:
    LIST
bitbang_wreg: DROP_CONTEXT
BANK_TRACKER = LATA; preserve caller context to improve timing
    ERRIF FOSC_FREQ != 8 MIPS, [TODO] not 8 mips: #v(mhz(FOSC_FREQ)) m hz,
    LOCAL bit = 7
 messg [DEBUG] bsr @st of bitbang_wreg: #v(BANK_TRACKER), LATA #v(LATA)
    while BIT(bit)
        spitbit_#v(1); setbit LATA, RA5, 1; NOTE: 1 extra instr (banksel) precedes first bit
;	nop
;	setbit LATA, RA5, data
        ifbit WREG, bit, FALSE, spitbit_#v(0); bitlow ;goto onbit#v(bit)
	nop 2,
	spitbit_#v(0); setbit LATA, RA5, 0
	nop4if bit; !needed on lst bit: return+call takes 4 instr cycle
bit -= 1
    endw
    return;
    NOLIST
#else
    messg [INFO] SPI using CLC+MSSP+PWM+TMR2
#endif
spi_send_byte macro byte, want_wait
;    BANKCHK SSP1STAT
;    BANKSAFE btfss SSP1STAT, BF; wait for (previous) byte to be sent
#ifdef BITBANG
;WS "0" = 10000 (1+4), "1" = 11100 (3+2) @4MIPS
    WARNIF want_wait <= 0, [WARNING] bit-bang is synchronous, wait want_wait ignored
;    LOCAL BYTE = byte
;    if !ISLIT(BYTE)
;	messg [INFO] WS timing not exact here
;    endif
;    LOCAL bit = 0x80
;    while bit
;        if ISLIT(BYTE)
;#if FOSC_FREQ == 8 MIPS
;	    setbit LATA, RA5, 1
;	    if (byte) & bit
;	        nop4
;	        setbit LATA, RA5, 0
;	        nop4
;	    else
;	        nop
;	        setbit LATA, RA5, 0
;	        nop7
;	    endif
;#else
;	    ERRIF FOSC_FREQ != 4 MIPS, [TODO] not 4 mips: #v(FOSC_FREQ)
;	    setbit LATA, RA5, 1
;	    nop2if (byte) & bit
;	    setbit LATA, RA5, 0
;	    nop2if !((byte) & bit)
;	    nop
;#endif
;	else; isreg
;;	    error [TODO] run-time bit-banging
;	    ifbit byte, bit, TRUE, goto onbit
;	    setbit LATA, RA5, 1
;	    setbit LATA, RA5, 0
;	    nop
;	    goto nextbit
;onbit:
;	    setbit LATA, RA5, 1
;	    nop2
;	    setbit LATA, RA5, 0
;	    nop
;nextbit:
;	endif
;bit /= 2
;    endw
    mov8 WREG, byte; NOTE: this strecthes active low trailer 1-2 instr cycle
    BANKCHK LATA
    call bitbang_wreg;
;BANK_TRACKER = LATA
#else
    spi_waitif want_wait < 0; wait BEFORE send
    mov8 SSP1BUF, byte;
    spi_waitif (want_wait > 0); || (want_wait == ASM_MSB); wait AFTER send
#endif
;?    mov8 WREG, SSP1BUF; read dummy byte to clear buf status and avoid collision flag
;    return
    endm

;ZCD initialization for phase-angle dimming:
zcd_init macro
    messg TODO: add ZCD for AC phase angle dimming ~pixel2things
    endm


#if 0
#define CLCIN_FOSC  4; should be in p16f15313.inc
#define PPSOUT_TMR0  12; should be in p16f15313.inc
#define PPSOUT_CLC4OUT  4; should be in p16f15313.inc
devtest_init macro
#ifdef WANT_DEBUG; show TMR0IF on RA0, RA4
    mov8 CLC4SEL0, LITERAL(CLCIN_FOSC); input selection
    mov8 RA0PPS, LITERAL(PPSOUT_TMR0);
    mov8 RA4PPS, LITERAL(PPSOUT_CLC4OUT);
    messg CLC0 routed straight through for analyer debug
;#define CLC4OUT  4; missing from .inc
#define LC4MODE_ANDOR  (b'000' << LC4MODE0)
;CLC4 routed straight thru (for analyer debug)
    REPEAT 4, mov8 CLC4SEL0 + repeater, LITERAL(0); NO_PPS); set later
    REPEAT 4, mov8 CLC4GLS0 + repeater, LITERAL(0xAA); all data gated, !inverted
    mov8 CLC4POL, LITERAL(0); NOBIT(LC4POL) | NOBIT(LC4G4POL) | NOBIT(LC4G3POL) | NOBIT(LC4G2POL) | NOBIT(LC4G1POL)); !inverted output or inputs
    mov8 CLC4CON, LITERAL(BIT(LC4EN) | NOBIT(LC4INTP) | NOBIT(LC4INTN) | LC4MODE_ANDOR); enable, no int, AND-OR
#endif
   endm
#endif


#if 0; default is unlocked
pps_lock macro
;requires next 5 instructions in sequence:
    mov8 PPSLOCK, LITERAL(0x55);
    mov8 PPSLOCK, LITERAL(0xAA);
;    mov8 PPSLOCK, LITERAL(0); allow CLC1 output to be redirected to RA1/2/5/4
    setbit PPSLOCK, PPSLOCKED, FALSE; allow output pins to be reassigned
    endm
#endif    


;initialize run-time stats:
    NBDCL numfr,;
stats_init macro
    mov8 numfr, LITERAL(0)
;numfr2 EQU  H'0077'
;    mov8 numfr2, LITERAL(0)
    endm


#if 0
#define LC1G1D1T  1; should be in p16f15313.inc
#define LC1D1S_LCIN3PPS  3; should be in p16f15313.inc
debug_init macro
    setbit CLC1CON, LC1EN, FALSE; datasheet says to disable CLC during setup
    mov8 CLCIN3PPS, LITERAL(WSINCH); RA3; CAUTION: CLCIN0PPS not available to CLCxSELy?
    mov8 CLC1SEL0, LITERAL(LC1D1S_LCIN3PPS); RA3 via CLCIN3PPS
    REPEAT 4, mov8 CLC1GLS0 + repeater, LITERAL(0); no inputs routed => constant 0
    mov8 CLC1GLS0, LITERAL(BIT(LC1G1D1T)); CLCIN3 routed to gate 0 data 1
    mov8 CLC1POL, LITERAL(NOBIT(LC1POL) | BIT(LC1G4POL) | BIT(LC1G3POL) | BIT(LC1G2POL) | NOBIT(LC1G1POL)); !inverted output, unused inputs (0) inverted for input to 4-AND
    mov8 CLC1CON, LITERAL(BIT(LC1EN) | NOBIT(LC1INTP) | NOBIT(LC1INTN) | LC1MODE_4AND); enable, no int, 4-way AND
    mov8 RA4PPS, LITERAL(PPSOUT_CLC1OUT);
debloop
    setbit LATA, 0, TRUE;
    setbit LATA, 0, FALSE
    goto debloop
;#ifdef WANT_DEBUG
;    messg sending CLC1 out (WS in) to RA4
;    mov8 RA4PPS, LITERAL(PPSOUT_CLC1OUT);
;    messg sending PWM3 to RA5
;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT);
;#endif
    endm
#endif

    LIST
init: DROP_CONTEXT; DROP_BANK ;Start:
;    messg #v(BANKOF(ANSELA)), #v(BANKOFS(ANSELA))
    iopin_init;
    clk_init;
;    debug_init;
    pmd_init;
    tmr0_init;
    tmr1_init;
    spi_init; includes tmr2_init and pwm_init
;    zcd_init;
;set up 3 CLC to allow 3-way output interleave:
    chout_init 1;
;    chout_init 2;
;    chout_init 3;
;    devtest_init;
;    pps_lock; default is unlocked; ;NOTE: it would be preferable to lock PPS but WS input redir would use 4 CLC, leaving none for SPI debug output
    stats_init;
;#ifdef WANT_DEBUG
#if 0
    messg [DEBUG] sending SPI data to RA5
    mov8 RA5PPS, LITERAL(PPS_CLC4OUT);
;show internal signals:
;    mov8 CLCIN2PPS, LITERAL(14); T2 ovfl
;    mov8 CLCIN1PPS, LITERAL(13); T1 ovfl
;    mov8 CLCIN0PPS, LITERAL(12); T0 ovfl
;    LITERAL(5); HFINTOSC
;    LITERAL(4); FOSC
;    mov8 CLCIN3PPS, LITERAL(WSINCH); CAUTION: CLCIN0PPS not available to CLCxSELy? use CLCIN3PPS instead
;    mov8 RA2PPS, LITERAL(PPS_CLC1OUT);
;send SPI out:
;    spi_send_byte LITERAL(0), +1;
;    spi_send_byte LITERAL(0xff), +1;
;    spi_send_byte LITERAL(0x55), +1;
;    spi_send_byte LITERAL(0), +1;
;    spi_send_byte LITERAL(10), +1;
;    spi_send_byte LITERAL(0), +1;
    wsnode_send LITERAL(0x00ff55), +1;
    wsnode_send LITERAL(0x000a00), +1;
;    goto $-1
#endif
    goto rcv_frame-1; a little more init before starting main loop


;; misc helpers ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;busy-wait (for short intervals ONLY):
;CAUTION: stack depth grows with longer delay period
;wait_64usec: call wait_32usec; 16 instr; fall thru + return second time
;wait_32usec: call wait_16usec; 16 instr; fall thru + return second time
;wait_16usec: call wait_8usec; 16 instr; fall thru + return second time
;wait_8usec: call wait_4usec; 16 instr; fall thru + return second time
wait_4usec: call wait_2usec; 16 instr; fall thru + return second time
wait_2usec: call wait_1usec; 8 instr; fall thru + return second time
wait_1usec:
#if FOSC_FREQ == 8 MIPS ;need one extra level for 8 MIPS
    call wait_500nsec;
wait_500nsec:
#else
    ERRIF FOSC_FREQ != 4 MIPS, [TODO] unhandled FOSC: #v(FOSC_FREQ), use 4 or 8 MIPS
#endif
    return; 4 instr call+return @4 MIPS == 1 usec


;; color rendering for WS281X nodes: ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;send 24 bit color code to WS281X node:
;#define LOBYTE(val)  IIF(ISLIT(val), LITERAL((val) & 0xFF), LO(val))
;#define MIDBYTE(val)  IIF(ISLIT(val), LITERAL((val) >> 8 & 0xFF), MID(val))
;#define HIBYTE(val)  IIF(ISLIT(val), LITERAL((val) >> 16 & 0xFF), HI(val))
wsnode_send macro rgb, want_wait
    LOCAL RGB = rgb ;kludge; force eval (avoids "missing operand" and "missing argument" errors/MPASM bugs); also helps avoid "line too long" messages (MPASM limit 200)
    if ISLIT(RGB)  ;unpack RGB bytes
	spi_send_byte LITERAL(RGB >> 16 & 0xFF), want_wait; 10 usec synchronous
	spi_send_byte LITERAL(RGB >> 8 & 0xFF), want_wait; 10 usec synchronous
	spi_send_byte LITERAL(RGB & 0xFF), want_wait; 10 usec synchronous
    else; register
	spi_send_byte HI(rgb), want_wait; 10 usec synchronous
	spi_send_byte MID(rgb), want_wait; 10 usec synchronous
	spi_send_byte LO(rgb), want_wait; 10 usec synchronous
    endif
;    LOCAL LOBYTE = IIF(ISLIT(RGB), LITERAL(RGB & 0xFF), LO(rgb))
;    LOCAL MIDBYTE = IIF(ISLIT(RGB), LITERAL(RGB >> 8 & 0xFF), MID(rgb))
;    LOCAL HIBYTE = IIF(ISLIT(RGB), LITERAL(RGB >> 16 & 0xFF), HI(rgb))
;    spi_send_byte HIBYTE, want_wait; 10 usec synchronous
;    spi_send_byte MIDBYTE, want_wait; 10 usec synchronous
;    spi_send_byte LOBYTE, want_wait; 10 usec synchronous
    endm


;set next ws node to a primary RGB color:
;CAUTION: busy-waits until SPI buf empty; do other processing before calling
wsnode_off: DROP_CONTEXT; "black"
    wsnode_send LITERAL(0), -1;
    retlw 1;
wsnode_red_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x00FF00), -1;
    retlw 1;
wsnode_green_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0xFF0000), -1;
    retlw 1;
wsnode_blue_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x0000FF), -1;
    retlw 1;
wsnode_yellow_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x808000), -1; try to keep consistent brightness with single colors
    retlw 1;
wsnode_cyan_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x800080), -1; try to keep consistent brightness with single colors
    retlw 1;
wsnode_magenta_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x008080), -1; try to keep consistent brightness with single colors
    retlw 1;
wsnode_white_bright: DROP_CONTEXT;
    wsnode_send LITERAL(0x555555), -1; try to keep consistent brightness with single colors
    retlw 1;
;dim variants (to make it easier on the eyes):
wsnode_red_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x000200), -1;
    retlw 1;
wsnode_green_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x020000), -1;
    retlw 1;
wsnode_blue_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x000002), -1;
    retlw 1;
wsnode_yellow_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x010100), -1;
    retlw 1;
wsnode_cyan_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x010001), -1;
    retlw 1;
wsnode_magenta_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x000101), -1;
    retlw 1;
wsnode_white_dim: DROP_CONTEXT;
    wsnode_send LITERAL(0x010101), -1;
    retlw 1;


;RGB color indexes:
;bottom 3 bits control R/G/B on/off (for easier color combinations/debug), 4th bit is brightness
#define RED_RGBINX  4
#define GREEN_RGBINX  2
#define BLUE_RGBINX  1
#define BRIGHT(rgb)  ((rgb) + 8); brighter variant
#define YELLOW_RGBINX  (RED_RGBINX | GREEN_RGBINX)
#define CYAN_RGBINX  (GREEN_RGBINX | BLUE_RGBINX)
#define MAGENTA_RGBINX  (RED_RGBINX | BLUE_RGBINX)
#define PINK_RGBINX  MAGENTA_RGBINX; easier to spell :P
#define WHITE_RGBINX  (RED_RGBINX | GREEN_RGBINX | BLUE_RGBINX)
#define OFF_RGBINX  0; "black"


;display buffer:
;#define NUMPX  #v(24 + 8); 24 px for first wsnode received + 8 px for fps
;    BDCL wsnodes:#v(NUMPX/2); 1 nibble per node (color indexed); FSR# handles banking
    BDCL wsnodes,:24+8-16; 1 byte per node (color indexed): 24px for first rcv node + 8 px for fps; FSR# handles banking
#define END_DETECT  16;0X40; BIT(5)
;    CONSTANT wseof = ENDOF(wsnodes); line too long
    messg [INFO] #wsnodes #v(SIZEOF(wsnodes)) @#v(wsnodes), eof@ #v(ENDOF(wsnodes)), detect& #v(END_DETECT)
    ERRIF (ENDOF(wsnodes) - 1) & END_DETECT == ENDOF(wsnodes) & END_DETECT, [ERROR] nodebuf end detect broken, !span #v(END_DETECT): #v(wsnodes)
    CONSTANT HI(FSR0) = FSR0H; mov16 shim
    CONSTANT HI(FSR1) = FSR1H; mov16 shim
;start rendering:
wsnodes_start: DROP_CONTEXT;
    mov16 FSR0, LITERAL(wsnodes); 0x2000 + NUMPX); linear addressing
;fall thru
;check whether to render next WS281X node:
;CAUTION: assumes FSR0 is already set
wsnodes_next: DROP_CONTEXT;
    ifbit FSR0L, log2(END_DETECT), ENDOF(wsnodes) & END_DETECT, retlw 0; eof
    moviw FSR0++; get next color index
;    retlw 1;
;    messg [DEBUG] ^^^^ REMOVE THIS
;fall thru
;render next WS281X node:
wsnodes_send1: DROP_CONTEXT;
;    moviw 0[FSR1]
;    lsrf FSR1; nibble -> byte address
;    swapf INDF1, W; get upper (even) nibble
;    ifbit FSR1H, 1, TRUE, moviw FSR1++; get lower (odd) nibble
    andlw 0x0F; only 4 lsb are used
    brw;
    CONSTANT jumptbl = $
;#define oncase(val, dest)  
;primary colors (dim):
    ORG jumptbl + RED_RGBINX
    goto wsnode_red_dim;
    ORG jumptbl + GREEN_RGBINX
    goto wsnode_green_dim;
    ORG jumptbl + YELLOW_RGBINX;
    goto wsnode_yellow_dim;
    ORG jumptbl + BLUE_RGBINX;
    goto wsnode_blue_dim;
    ORG jumptbl + MAGENTA_RGBINX;
    goto wsnode_magenta_dim;
    ORG jumptbl + CYAN_RGBINX;
    goto wsnode_cyan_dim;
    ORG jumptbl + WHITE_RGBINX;
    goto wsnode_white_dim;
    ORG jumptbl + OFF_RGBINX;
    goto wsnode_off;
;primary colors (bright):
    ORG jumptbl + BRIGHT(RED_RGBINX);
    goto wsnode_red_dim;
    ORG jumptbl + BRIGHT(GREEN_RGBINX);
    goto wsnode_green_dim;
    ORG jumptbl + BRIGHT(YELLOW_RGBINX);
    goto wsnode_yellow_dim;
    ORG jumptbl + BRIGHT(BLUE_RGBINX);
    goto wsnode_blue_dim;
    ORG jumptbl + BRIGHT(MAGENTA_RGBINX);
    goto wsnode_magenta_dim;
    ORG jumptbl + BRIGHT(CYAN_RGBINX);
    goto wsnode_cyan_dim;
    ORG jumptbl + BRIGHT(WHITE_RGBINX);
    goto wsnode_white_dim;
    ORG jumptbl + BRIGHT(OFF_RGBINX);
    goto wsnode_off; redundant; could be used for something else
;NOTE: above subroutines return to caller
    ORG jumptbl + 16

;render all nodes:
wsnodes_all: DROP_CONTEXT;
#if 1
    messg [DEBUG] vvv REMOVE THIS!
    mov8 WREG, LITERAL(BIT(RA2));
    BANKCHK LATA
    xorwf LATA, F;
;    return; bypass render logic
#endif
    call wsnodes_start;
wsnodes_more: DROP_CONTEXT;
;    iorlw 0;
;    ifbit STATUS, EQUALS, TRUE, return; continue until eof
    decfsz WREG, F;
    return; eof
    call wsnodes_next;
    goto wsnodes_more;

wsnodes_clear: DROP_CONTEXT;
;    ERRIF (wsnodes & 0xFF) != GPR_START, [ERROR] wsnodes is not at start of linear RAM
;    ERRIF OFF_RGBINX, [ERROR] black should be index 0: #v(OFF_RGBINX)
;    mov16 FSR0, LITERAL(0x2000 + NUMPX); linear addressing
;    mov8 WREG, LITERAL(OFF_RGBINX);
;    movwi FSR0++;
;    mov8 WREG, FSR0L;
;    xorlw LITERAL((wsnodes + NUMPX) & 0xFF);
;    movwi FSR0;
    mov16 FSR0, LITERAL(wsnodes); 0x2000 + NUMPX); linear addressing
    mov8 WREG, LITERAL(OFF_RGBINX);
init_loop: DROP_CONTEXT;
;    clrf INDF0;
;    movwi 0[FSR0]
;    incfsz FSR0L, F
    movwi FSR0++;
;    messg end detect: #v(END_DETECT), #v(log2(END_DETECT)), #v(wsnodes), #v(wsnodes & END_DETECT)
    ifbit FSR0L, log2(END_DETECT), ENDOF(wsnodes) & END_DETECT, return;
    goto init_loop;


;; WS281X decode ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;wait for WS input line to go high then low:
;wait_wsbit macro ;want_high, want_timing
;    BANKCHK WSIN
;    if want_high
;        btfss WSIN
;	goto $-1
;    else
;	btfsc WSIN
;	goto $-1
;    endif
;    if want_timing
;	messg TODO
;    endif
;    endm

;capture + decode next WS data bit:
;see AN1473 for details on how pulse capture works
wsbit_capture macro
    mov8 TMR1L, LITERAL(0);
;?    mov8 TMR1H, LITERAL(0);
;    setbit T1GCON, T1GGO, TRUE; start capture of single pulse
    tmr1_acq; start capture of single pulse
;    BANKCHK PIR5
;    BANKSAFE btfss PIR5, TMR1GIF; wait for pulse to go high then low
;    ifbit PIR5, TMR1GIF, FALSE, goto $-1
    ws_clrwdt FALSE;
    mov8 WREG, TMR1L; get pulse width
    setbit PIR5, TMR1GIF, FALSE ;disable capture
    endm


    NBDCL24 chqlen; hi = ch1, mid = ch2, lo = ch3
;    NBDCL ch2qlen
;    NBDCL ch3qlen
;save next bit of WS281X input stream bits:
save_bit macro dummy1_arg, dummy2_arg
    wsbit_capture
;    sub8 LITERAL(WSBIT_THRESHOLD), WREG
    addlw -WSBIT_THRESHOLD & 0xFF; Borrow => WS "0" bit received, Carry => WS "1" bit received
;    lslf ch1qlen
;    BANKCHK LO(chqlen);
;shift new bit into lsb:
    rlf LO(chqlen), F
    rlf MID(chqlen), F
    rlf HI(chqlen), F
    endm


;send next bit of WS281X data:
;pass_node macro
;CLC will pass through WS281X data faster than bit-banging, but need count to control debout output
;    wait_wsbit 1, FALSE
;    wait wsbit 0, FALSE
;    REPEAT 24, wsbit_capture; don't need to capture value, but caller needs to count bits
;    messg "TODO: pass_node"
;    endm

;redirect 4 WS281X nodes to current output channel:
    NBDCL wsbits,
pass_quadnode: DROP_CONTEXT; DROP_BANK
;    REPEAT 4, pass_node
    mov8 wsbits, LITERAL(4 * 24)
wait_wsbit: DROP_CONTEXT;
    wsbit_capture; don't need to capture value, just count bits for caller
    decfsz wsbits, F
    goto wait_wsbit;
    return


;; main logic ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;prepare debout data for display:
    NBDCL debout_count,
    NBDCL24 debout_chlen
    NBDCL debout_fps,
;    NBDCL debout_2
;    NBDCL debout_3
debout_prepare macro
;    mov8 debout_0, ch1qlen
;    mov8 debout_1, ch2qlen
;    mov8 debout_2, ch3qlen
    mov24 debout_chlen, chqlen
    mov8 debout_fps, LITERAL(0xFF); TODO: FPS
    mov8 debout_count, LITERAL(24+8); set debout length (#WS281X bits)
    endm
;render debout data:
debout_render macro
    decfsz debout_count, F
    goto debout_complete
#if 1
    messg TODO: debout logic using SPI
#endif
    endm

;show_debug macro
;;    mov8 RA5PPS, LITERAL(0);
;    setbit LATA, RA2, 0;
;;    call wait_16usec; make it easier to see on analyser; DEBUG ONLY
;;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT);
;    setbit LATA, RA2, 1;
;    setbit LATA, RA2, 0;
;    setbit LATA, RA2, 1;
;    endm

#ifdef WANT_DEBUG
wait_qtrsec: DROP_CONTEXT
    wait_msec 250,
    return;

wait_halfsec: DROP_CONTEXT
    wait_msec 500,
    return;

wait_1sec: DROP_CONTEXT
    wait_sec 1,
    return;
#endif

;blink2: DROP_CONTEXT
;    setbit LATA, RA2, 1;
;    call wait_qtrsec
;    setbit LATA, RA2, 0;
;    call wait_halfsec
;    setbit LATA, RA2, 1;
;    call wait_qtrsec
;    setbit LATA, RA2, 0;
;    call wait_halfsec
;    return;

more_init:
;    call blink2;
    call wsnodes_clear;
;    call wait_1sec;
;    call blink2;
    return;

;reset state and wait for next frame:
;ws_timeout: DROP_BANK
;    BANKCHK STKPTR;
;    BANKSAFE decf STKPTR, F; not going to RETFIE; adjust stack manually
;    DROP_BANK
    call more_init
;    nop
rcv_frame: DROP_CONTEXT; DROP_BANK; DROP_WREG
;    mov8 RA1PPS, LITERAL(CLC1OUT); , LITERAL(RA1); redirect WS input to channel 1
;    goto $-1;
;enable 50 usec timeout to detect end of frame:
;WDT minimum time 2 msec is too long for WS281X reset time of 50 usec; use Timer 0 instead
;use interrupt to avoid polling for timeout; if timeout occurs, nothing else is happening anyway
;#ifdef WANT_DEBUG; show TMR0IF on RA0, RA4
#if 0; 1
    setbit LATA, RA2, 1;
    call wait_1sec
    setbit LATA, RA2, 0;
    call wait_1sec
    goto rcv_frame;
#endif
#if 1
#ifndef BITBANG
;#define PPS_SDO1  0x16; should be in p16f15313.inc
;#define PPS_SCK1  0x15; should be in p16f15313.inc
    messg [DEBUG] sending SPI data to RA5
    mov8 RA5PPS, LITERAL(PPS_CLC4OUT);
;    messg [DEBUG] sending SDO1 to RA5
;    mov8 RA5PPS, LITERAL(PPS_SCK1); looks good: 1.25 usec each pulse (1x ws bit speed)
;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT); looks good: 0.625 usec each pulse (2x ws bit speed)
#endif
;    goto rcv_frame2;
;ani_start: DROP_CONTEXT;
    NBDCL color,;
    mov8 color, LITERAL(RED_RGBINX);
    mov16 FSR1, LITERAL(wsnodes);
ani_loop: DROP_CONTEXT;
;    call blink2;
    mov8 INDF1, color;
    call wsnodes_all;
;    call wait_1sec;
    wait_msec 100,; animation speed
;    call wsnodes_clear;
    mov8 INDF1_postinc, LITERAL(OFF_RGBINX); turn it off again before moving to next node (more efficient than clearing entire node buf each time)
    ifbit FSR1L, log2(END_DETECT), !(ENDOF(wsnodes) & END_DETECT), goto ani_loop; !eof
    mov8 FSR1, LITERAL(wsnodes); rewind
;    xorlw OFF_RGBINX;
;    ifbit STATUS_EQUALS, FALSE, goto ani_loop;
;    incf color, F;
    mov8 WREG, color;
    call choose_next_color;
    mov8 color, WREG;
    goto ani_loop;

choose_next_color: DROP_CONTEXT;
    andlw 0x0F; only 4 lsb are used
    brw
    CONSTANT nexttbl = $
    ORG nexttbl + RED_RGBINX
    retlw GREEN_RGBINX;
    ORG nexttbl + GREEN_RGBINX
    retlw YELLOW_RGBINX;
    ORG nexttbl + YELLOW_RGBINX;
    retlw BLUE_RGBINX
    ORG nexttbl + BLUE_RGBINX;
    retlw MAGENTA_RGBINX
    ORG nexttbl + MAGENTA_RGBINX;
    retlw CYAN_RGBINX
    ORG nexttbl + CYAN_RGBINX;
    retlw WHITE_RGBINX;
    ORG nexttbl + WHITE_RGBINX;
    retlw OFF_RGBINX;
    ORG nexttbl + OFF_RGBINX;
;    goto rcv_frame; repeat
    retlw RED_RGBINX;
    ORG nexttbl + 8
#endif
#if 0
rcv_frame2: DROP_CONTEXT; DROP_BANK
    setbit LATA, RA2, 1;
    wsnode_send LITERAL(0x030000), +1; 0x70101), +1; 30 usec synchronous
;    call wait_8usec
    wsnode_send LITERAL(0x000300), +1; 0x70101), +1; 30 usec synchronous
;    call wait_8usec
    wsnode_send LITERAL(0x000003), +1; 0x70101), +1; 30 usec synchronous
;    call wait_8usec
    wsnode_send LITERAL(0x010100), +1; 0x70101), +1; 30 usec synchronous
;    call wait_8usec
    wsnode_send LITERAL(0x010001), +1; 0x70101), +1; 30 usec synchronous
;    call wait_8usec
    wsnode_send LITERAL(0x000101), +1; 0x70101), +1; 30 usec synchronous
    setbit LATA, RA2, 0;
    call wait_1sec
    REPEAT 6, wsnode_send LITERAL(0), +1; 0x70101), +1; 30 usec synchronous
    call wait_1sec
    goto rcv_frame2;
    
;    setbit LATA, RA2, 0;
;    setbit LATA, RA2, 1;
;    show_debug;
;    spi_send_byte LITERAL(0x3a), +1; 10 usec synchronous
;    setbit LATA, RA2, 0
;    call wait_32usec
;    goto rcv_frame
;on, off, on, off, on:
;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT);
    wsnode_send LITERAL(0x030101), +1; 0x70101), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0x010301), +1; 0x10701), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0x010103), +1; 0x10107), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
;    mov8 RA5PPS, LITERAL(0);
;    setbit LATA, RA2, 0;
    call wait_1sec
;    call wait_1sec
;    call wait_1sec
    ;off, on, off, on, off:
    setbit LATA, RA2, 0;
;    setbit LATA, RA2, 1;
;    setbit LATA, RA2, 0;
;    mov8 RA5PPS, LITERAL(PPS_PWM3OUT);
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0x020201), +1; 0x030301), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0x010202), +1; 0x010303), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0), +1; 30 usec synchronous
;    show_debug
    wsnode_send LITERAL(0x020102), +1; 0x030103), +1; 30 usec synchronous
;    mov8 RA5PPS, LITERAL(0);
;    setbit LATA, RA2, 1;
    call wait_1sec
;    call wait_1sec
;    call wait_1sec
    goto rcv_frame;

;red:
    wsnode_send LITERAL(0x040000), +1; 30 usec synchronous
    call wait_1sec
;green:
    wsnode_send LITERAL(0x000400), +1; 30 usec synchronous
    call wait_1sec
;blue:
    wsnode_send LITERAL(0x000004), +1; 30 usec synchronous
    call wait_1sec
    goto rcv_frame
#endif
#if 0
    messg HB debug @~1.6 Hz
;	setbit LATA, RA5, TRUE;
;	setbit LATA, RA5, FALSE;
;    BANKCHK LATA; do banksel < loop
;loop:
;    setbit LATA, RA2, FALSE
;    setbit LATA, RA2, TRUE
;    goto loop
    mov8 WREG, LITERAL(BIT(RA2));
    BANKCHK LATA
    xorwf LATA, F
#endif
#if 0
    messg r/g/b hb 1 hz on ra5
;    BANKCHK numfr;
    decfsz LO(counter16), F
    goto resume_rcvfr
    decfsz HI(counter16), F
    goto resume_rcvfr
    incf numfr, F
;20K * 50 usec == 1 sec
;    mov8 counterL, LITERAL(20000 & 0xFF);
;    mov8 counterH, LITERAL(20000 / 256 & 0xFF);
    mov16 counter16, LITERAL(20000);
    mov8 RA5PPS, LITERAL(PPS_CLC4OUT);
;send SPI out:
;    spi_send_byte LITERAL(0), +1;
;    spi_send_byte LITERAL(0xff), +1;
;    spi_send_byte LITERAL(0x55), +1;
    mov8 WREG, LITERAL(4);
    ifbit numfr, 2, FALSE, clrw
    spi_send_byte WREG, +1; 10 usec synchronous
    mov8 WREG, LITERAL(4);
    ifbit numfr, 1, FALSE, clrw
    spi_send_byte WREG, +1; 10 usec synchronous
    mov8 WREG, LITERAL(4);
    ifbit numfr, 0, FALSE, clrw
    spi_send_byte WREG, +1; 10 usec synchronous
resume_rcvfr: DROP_CONTEXT; DROP_BANK
#endif
    ws_clrwdt TRUE;
;    goto $-1
;    messg ^^^ RMEOVE
;    setbit PIR0, TMR0IF, FALSE; clear previous interrupt
;    setbit INTCON, GIE, TRUE; (re-)enable interrupts
;    messg ^^^ REINSTATE
;capture first WS input node:
;loop:
;    setbit PIR, SSP1IF, TRUE;
;    spi_send_byte LITERAL(0xF0), 0;
;    spi_send_byte LITERAL(0x0F), ~0;
;    goto loop;
    REPEAT 24, save_bit ,; NOARG, NOARG
    messg [TODO] check for special function codes (skip, dup, etc)
    messg [TODO] add special RGB value to write to EEPROM for config
    messg [TODO] add WS-to-PWM (AC phase angle) dimming ~Pixel2Thing
    debout_prepare
    mov8 RA4PPS, LITERAL(0); NO_PPS); turn off channel 4
    mov8 RA1PPS, LITERAL(PPS_CLC1OUT); , LITERAL(RA1); redirect WS input to channel 1
channel1: ;DROP_BANK
;    REPEAT 4, pass_node
    call pass_quadnode;
    decfsz LO(chqlen), F
    goto channel1
    mov8 RA1PPS, LITERAL(0); NO_PPS); turn off channel 1
    mov8 RA2PPS, LITERAL(PPS_CLC1OUT); , LITERAL(RA1); redirect WS input to channel 2
channel2: ;DROP_BANK
;    REPEAT 4, pass_node
    call pass_quadnode;
    decfsz MID(chqlen), F
    goto channel2
    mov8 RA2PPS, LITERAL(0); NO_PPS); turn off channel 2
    mov8 RA#v(3+2)PPS, LITERAL(PPS_CLC1OUT); , LITERAL(RA1); redirect WS input to channel 3
channel3: ;DROP_BANK
;    REPEAT 4, pass_node
    call pass_quadnode;
    decfsz HI(chqlen), F
    goto channel3
    mov8 RA#v(3+2)PPS, LITERAL(0); NO_PPS); turn off channel 3
    mov8 RA4PPS, LITERAL(PPS_CLC1OUT); , LITERAL(RA1); redirect WS input to channel 4
channel4: ;DROP_BANK
;    pass_node
    call pass_quadnode;
    goto channel4


    CONSTANT EOF_ADDR = $
#define pct(num, den)  rdiv(100 * (num), den)
eof: ;//sanity checks, perf stats
    messg [INFO] optimization stats:
    ERRIF MEXPAND_DEPTH, [ERROR] missing #v(MEXPAND_DEPTH) MEXPAND_POP(s),
    messg [INFO] bank sel: #v(BANKSEL_KEEP) (#v(pct(BANKSEL_KEEP, BANKSEL_KEEP + BANKSEL_DROP))%), dropped: #v(BANKSEL_DROP) (#v(pct(BANKSEL_DROP, BANKSEL_KEEP + BANKSEL_DROP))%); ;perf stats
    messg [INFO] bank0 used: #v(RAM_USED#v(0))/#v(RAM_LEN#v(0)) (#v(pct(RAM_USED#v(0), RAM_LEN#v(0)))%)
    MESSG [INFO] bank1 used: #v(RAM_USED#v(1))/#v(RAM_LEN#v(1)) (#v(pct(RAM_USED#v(1), RAM_LEN#v(1)))%)
    MESSG [INFO] non-banked used: #v(RAM_USED#v(NOBANK))/#v(RAM_LEN#v(NOBANK)) (#v(pct(RAM_USED#v(NOBANK), RAM_LEN#v(NOBANK)))%)
    messg [INFO] page sel: #v(PAGESEL_KEEP) (#v(pct(PAGESEL_KEEP, PAGESEL_KEEP + PAGESEL_DROP))%), dropped: #v(PAGESEL_DROP) (#v(pct(PAGESEL_DROP, PAGESEL_KEEP + PAGESEL_DROP))%); ;perf stats
    messg [INFO] page0 used: #v(EOF_ADDR)/#v(LIT_PAGELEN) (#v(pct(EOF_ADDR, LIT_PAGELEN))%)
;    MESSG "TODO: fix eof page check"
    ERRIF LITPAGEOF(EOF_ADDR), [ERROR] code page 0 overflow: eof @#v(EOF_ADDR) is past #v(LIT_PAGELEN), need page selects; need to add page selects
;    END
;#else //!WANT_HOIST
;#endif ;WANT_HOIST
;    messg "hello 5"
    END
;eof
