; ============================================================
; MC6400 / INS8070 - TEKTRONIX 2335 FAST ANALOG XY TORUS 1K
;
; True analog-scope version: project vertices, then stream a continuous
; Eulerian endpoint route many times at high repeat rate.  The analog CRT
; beam draws the straight segments between endpoints.  No keypad scan and no
; LED heartbeat.  Optional Z blanking writes hide projection pauses/restarts.
; Active image fits wholly in 0x1000..0x13FF.
; ============================================================
        ORG   0x1000
DAC     EQU   0xE000
NVERT   EQU   48
NROUTE  EQU   97
REPS    EQU   12
DAX     EQU   1
DAY     EQU   1
AX0     EQU   8
AY0     EQU   5

TMP16   EQU   0xFFC0
VSX     EQU   0xFFC2
VSY     EQU   0xFFC3
ECNT    EQU   0xFFC4
AX      EQU   0xFFC5
AY      EQU   0xFFC6
CAC     EQU   0xFFC7
SAC     EQU   0xFFC8
CBC     EQU   0xFFC9
SBC     EQU   0xFFCA
MA      EQU   0xFFCB
MS      EQU   0xFFCC
MTMP    EQU   0xFFCD
ACC     EQU   0xFFCF
Z1      EQU   0xFFD1
VX      EQU   0xFFD2
VY      EQU   0xFFD3
VZ      EQU   0xFFD4
VCNT    EQU   0xFFD5
RCNT    EQU   0xFFD6
STACK   EQU   0x13FF
LEDMASK EQU   0xFFE0          ; heartbeat F-LED bit (0x02/0x04/0x08)

START:  LD    SP,=STACK
        LD    A,=0x02
        ST    A,LEDMASK
        LD    A,=AX0
        ST    A,AX
        LD    A,=AY0
        ST    A,AY
        JSR   BLANK
FRAME:  JSR   PROJECT
        JSR   HEARTB
        LD    A,=REPS
        ST    A,RCNT
RPTLP:  JSR   DRAWROUTE
        DLD   A,RCNT
        BNZ   RPTLP
        JSR   BLANK
        LD    A,AX
        ADD   A,=DAX
        ST    A,AX
        LD    A,AY
        ADD   A,=DAY
        ST    A,AY
        BRA   FRAME

BLANK:  LD    P2,=DAC
        LD    A,=1
        ST    A,2(P2)
        RET

UNBLANK:LD    P2,=DAC
        LD    A,=0
        ST    A,2(P2)
        RET

; ------------------------------------------------------------
; HEARTB: march one lit LED F1->F2->F3 (INS8070 status flag outputs),
; one step per reprojection frame.  Runs while the beam is parked.
HEARTB: LD    A,LEDMASK
        SL    A
        AND   A,=0x0E
        BNZ   HBOK
        LD    A,=0x02
HBOK:   ST    A,LEDMASK
        LD    S,A
        RET


DRAWROUTE:
        LD    P3,=ROUTE
        LD    A,@1(P3)
        JSR   GETVERT
        LD    P2,=DAC
        LD    A,VSX
        ST    A,0(P2)
        LD    A,VSY
        ST    A,1(P2)         ; first point is blanked after projection
        JSR   UNBLANK
        LD    A,=NROUTE-1
        ST    A,ECNT
DRLP:   LD    A,@1(P3)
        JSR   GETVERT
        LD    P2,=DAC
        LD    A,VSX
        ST    A,0(P2)
        LD    A,VSY
        ST    A,1(P2)
        DLD   A,ECNT
        BNZ   DRLP
        LD    A,=1
        ST    A,3(P2)
        RET

PROJECT: LD   A,AY
        JSR   SINLK
        ST    A,SBC
        LD    A,AY
        ADD   A,=16
        JSR   SINLK
        ST    A,CBC
        LD    A,AX
        JSR   SINLK
        ST    A,SAC
        LD    A,AX
        ADD   A,=16
        JSR   SINLK
        ST    A,CAC
        LD    A,=NVERT
        ST    A,VCNT
        LD    P3,=VERTS
        LD    P2,=PCOORD
PVLOOP: JSR   PROJ1
        DLD   A,VCNT
        BNZ   PVLOOP
        RET

PROJ1:  LD    A,@1(P3)
        ST    A,VX
        LD    A,@1(P3)
        ST    A,VY
        LD    A,@1(P3)
        ST    A,VZ
        LD    A,VX
        ST    A,MA
        LD    A,CBC
        ST    A,MS
        JSR   MULFIX
        ST    EA,ACC
        LD    A,VZ
        ST    A,MA
        LD    A,SBC
        ST    A,MS
        JSR   MULFIX
        ADD   EA,ACC
        ADD   EA,=128
        ST    A,@1(P2)
        LD    A,VZ
        ST    A,MA
        LD    A,CBC
        ST    A,MS
        JSR   MULFIX
        ST    EA,ACC
        LD    A,VX
        ST    A,MA
        LD    A,SBC
        ST    A,MS
        JSR   MULFIX
        ST    EA,MTMP
        LD    EA,ACC
        SUB   EA,MTMP
        ST    A,Z1
        LD    A,VY
        ST    A,MA
        LD    A,CAC
        ST    A,MS
        JSR   MULFIX
        ST    EA,ACC
        LD    A,Z1
        ST    A,MA
        LD    A,SAC
        ST    A,MS
        JSR   MULFIX
        ST    EA,MTMP
        LD    EA,ACC
        SUB   EA,MTMP
        ADD   EA,=128
        ST    A,@1(P2)
        RET

MULFIX: LD    A,=0
        LD    E,A
        LD    A,MS
        BP    MK1
        LD    A,=0xFF
        LD    E,A
        LD    A,MS
MK1:    LD    T,EA
        LD    A,=0
        LD    E,A
        LD    A,MA
        BP    MK2
        LD    A,=0xFF
        LD    E,A
        LD    A,MA
MK2:    MPY   EA,T
        LD    EA,T
        ADD   EA,=0x8000
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SUB   EA,=0x200
        RET

SINLK:  AND   A,=0x3F
        ST    A,TMP16
        LD    A,=0
        ST    A,TMP16+1
        LD    EA,=SINE
        ADD   EA,TMP16
        LD    P2,EA
        LD    A,0(P2)
        RET

GETVERT: SL   A
        ST    A,TMP16
        LD    A,=0
        ST    A,TMP16+1
        LD    EA,=PCOORD
        ADD   EA,TMP16
        LD    P2,EA
        LD    A,0(P2)
        ST    A,VSX
        LD    A,1(P2)
        ST    A,VSY
        RET

SINE:
        DB    0x00, 0x06, 0x0C, 0x13, 0x18, 0x1E, 0x24, 0x29, 0x2D, 0x31, 0x35, 0x38, 0x3B, 0x3D, 0x3F, 0x40
        DB    0x40, 0x40, 0x3F, 0x3D, 0x3B, 0x38, 0x35, 0x31, 0x2D, 0x29, 0x24, 0x1E, 0x18, 0x13, 0x0C, 0x06
        DB    0x00, 0xFA, 0xF4, 0xED, 0xE8, 0xE2, 0xDC, 0xD7, 0xD3, 0xCF, 0xCB, 0xC8, 0xC5, 0xC3, 0xC1, 0xC0
        DB    0xC0, 0xC0, 0xC1, 0xC3, 0xC5, 0xC8, 0xCB, 0xCF, 0xD3, 0xD7, 0xDC, 0xE2, 0xE8, 0xED, 0xF4, 0xFA
VERTS:
        DB    0x32, 0x00, 0x00
        DB    0x29, 0x10, 0x00
        DB    0x17, 0x10, 0x00
        DB    0x0E, 0x00, 0x00
        DB    0x17, 0xF0, 0x00
        DB    0x29, 0xF0, 0x00
        DB    0x23, 0x00, 0x23
        DB    0x1D, 0x10, 0x1D
        DB    0x10, 0x10, 0x10
        DB    0x0A, 0x00, 0x0A
        DB    0x10, 0xF0, 0x10
        DB    0x1D, 0xF0, 0x1D
        DB    0x00, 0x00, 0x32
        DB    0x00, 0x10, 0x29
        DB    0x00, 0x10, 0x17
        DB    0x00, 0x00, 0x0E
        DB    0x00, 0xF0, 0x17
        DB    0x00, 0xF0, 0x29
        DB    0xDD, 0x00, 0x23
        DB    0xE3, 0x10, 0x1D
        DB    0xF0, 0x10, 0x10
        DB    0xF6, 0x00, 0x0A
        DB    0xF0, 0xF0, 0x10
        DB    0xE3, 0xF0, 0x1D
        DB    0xCE, 0x00, 0x00
        DB    0xD7, 0x10, 0x00
        DB    0xE9, 0x10, 0x00
        DB    0xF2, 0x00, 0x00
        DB    0xE9, 0xF0, 0x00
        DB    0xD7, 0xF0, 0x00
        DB    0xDD, 0x00, 0xDD
        DB    0xE3, 0x10, 0xE3
        DB    0xF0, 0x10, 0xF0
        DB    0xF6, 0x00, 0xF6
        DB    0xF0, 0xF0, 0xF0
        DB    0xE3, 0xF0, 0xE3
        DB    0x00, 0x00, 0xCE
        DB    0x00, 0x10, 0xD7
        DB    0x00, 0x10, 0xE9
        DB    0x00, 0x00, 0xF2
        DB    0x00, 0xF0, 0xE9
        DB    0x00, 0xF0, 0xD7
        DB    0x23, 0x00, 0xDD
        DB    0x1D, 0x10, 0xE3
        DB    0x10, 0x10, 0xF0
        DB    0x0A, 0x00, 0xF6
        DB    0x10, 0xF0, 0xF0
        DB    0x1D, 0xF0, 0xE3
ROUTE:
        DB    0x00, 0x2A, 0x2F, 0x2E, 0x2D, 0x2C, 0x2B, 0x2A, 0x24, 0x29, 0x28, 0x27, 0x26, 0x25, 0x24, 0x1E
        DB    0x23, 0x22, 0x21, 0x20, 0x1F, 0x1E, 0x18, 0x1D, 0x1C, 0x1B, 0x1A, 0x19, 0x18, 0x12, 0x17, 0x16
        DB    0x15, 0x14, 0x13, 0x12, 0x0C, 0x11, 0x10, 0x0F, 0x0E, 0x0D, 0x0C, 0x06, 0x0B, 0x11, 0x17, 0x1D
        DB    0x23, 0x29, 0x2F, 0x05, 0x0B, 0x0A, 0x10, 0x16, 0x1C, 0x22, 0x28, 0x2E, 0x04, 0x0A, 0x09, 0x0F
        DB    0x15, 0x1B, 0x21, 0x27, 0x2D, 0x03, 0x09, 0x08, 0x0E, 0x14, 0x1A, 0x20, 0x26, 0x2C, 0x02, 0x08
        DB    0x07, 0x0D, 0x13, 0x19, 0x1F, 0x25, 0x2B, 0x01, 0x07, 0x06, 0x00, 0x05, 0x04, 0x03, 0x02, 0x01
        DB    0x00
PCOORD: DS    NVERT+NVERT

