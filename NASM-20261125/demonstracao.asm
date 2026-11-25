; Programa carregado em ram.vhd, com inicio no endereco 0x00.
        ldi  Ra, 0x05
        ldi  Rb, 0x03
        add  Ra, Rb       ; Ra = 8, GT = 1
        push Ra           ; MEM[254] = 8, SP = 253
        sub  Rb, Ra       ; Rb = 251, N = OVF = SM = 1
        pop  Rc           ; Rc = 8, SP = 254, flags preservadas
        ldi  Rd, 0x0C     ; Endereco de destino: gravar
        bcs  Rd           ; Salta porque OVF = 1
        inc  Rc           ; Se executar, o LCD mostra 009 em vez de 008
gravar: st   Rc, 0xFF     ; LCD mostra MEM[255] = 008
        halt
