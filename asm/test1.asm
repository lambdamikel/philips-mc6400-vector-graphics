; minimal DAC smoke test
        ORG   0x1000
DACX    EQU   0xE000
start:  LD    P2,=DACX        ; P2 -> DAC base
        LD    A,=0x40
        ST    A,0(P2)         ; X = 0x40
        LD    A,=0xC0
        ST    A,1(P2)         ; Y = 0xC0
loop:   BRA   loop            ; spin
