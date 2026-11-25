;            .global @start  ; jmp to memory start address
;            .byte 0xFE      ; stack pointer
            .equ valA, 0x0c ; variable ---> valA = 12
            .equ valB, 127  ; variable ---> valB = 127

;            .org 0x10
start:      ldi Ra, 0x14    ; Ra = 20
            ldi Rb, 0x0A    ; Rb = 10
            ldi Rc, @valA   ; Rc = 12
            ldi RD, @valB   ; Rd = 127

            add Rb, Rc      ; Rb = 22
            add Rb, Rd      ; Rb = 149
            sub Rb, Ra      ; Rb = 129
            sub RB, RD      ; Rb = 2

            not Ra          ; Ra = 235   (~20 = ~0b00010100 = 0b11101011)

            ldr Ra, [RB]    ; Ra = 0xFE
            str Ra, [RC]    ; MEM[12] = 0xFE
            jmp @start
