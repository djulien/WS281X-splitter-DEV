RES_VECT  CODE    0x0000            ; processor reset vector
;    GOTO    START                   ; go to beginning of program
    goto init

; TODO ADD INTERRUPTS HERE IF USED

MAIN_PROG CODE                      ; let linker place main program

init:
;START

    GOTO $                          ; loop forever

    END