; ============================================================
; MC6400 / INS8070 - TEKTRONIX 2335 SLEW/ENDPOINTS ANALOG XY PERSPECTIVE CUBE 1K
;
; Perspective cube with small interpolated edge steps.  No keypad scan and no
; LED heartbeat.  Optional Z blanking writes hide projection pauses/restarts.
; Active image fits wholly in 0x1000..0x13FF.
; ============================================================
        ORG   0x1000
DAC     EQU   0xE000
STEPS   EQU   8
NROUTE  EQU   16
REPS    EQU   5
DAX     EQU   1
DAY     EQU   1
AX0     EQU   10
AY0     EQU   6
; --- endpoints-only ("slew") build: no per-edge interpolation; the RC low-pass
; --- on the DAC X/Y outputs draws each edge as a continuous ramp. Tune DWCNT so
; --- the beam just reaches each corner (edges rounded/short -> raise; bright
; --- corner dots -> lower).  Matched to ~14.7 nF, R=4.7k (tau ~69 us).
DWCNT   EQU   12
DWMEM   EQU   0xFFF0
LEDMASK EQU   0xFFF1          ; current F-LED bit (0x02/0x04/0x08)
HBDIV   EQU   0xFFF2          ; march countdown
HBRATE  EQU   40              ; frames per march step (bigger = slower)

X0      EQU   0xFFC0
Y0      EQU   0xFFC1
X1      EQU   0xFFC2
Y1      EQU   0xFFC3
XACC    EQU   0xFFC4
YACC    EQU   0xFFC6
XSTP    EQU   0xFFC8
YSTP    EQU   0xFFCA
TMP16   EQU   0xFFCC
VSX     EQU   0xFFCE
VSY     EQU   0xFFCF
CNT     EQU   0xFFD0
ECNT    EQU   0xFFD1
AX      EQU   0xFFD2
AY      EQU   0xFFD3
CAC     EQU   0xFFD4
SAC     EQU   0xFFD5
CBC     EQU   0xFFD6
SBC     EQU   0xFFD7
MA      EQU   0xFFD8
MS      EQU   0xFFD9
MSIGN   EQU   0xFFDA
MTMP    EQU   0xFFDB
ACC     EQU   0xFFDD
Z1      EQU   0xFFDF
VX      EQU   0xFFE0
VY      EQU   0xFFE1
VZ      EQU   0xFFE2
VCNT    EQU   0xFFE3
X2V     EQU   0xFFE4
Y2V     EQU   0xFFE6
ZC      EQU   0xFFE8
DNUM    EQU   0xFFEA
DSIGN   EQU   0xFFEC
RCNT    EQU   0xFFED
FDEP    EQU   0xFFEE
STACK   EQU   0x13FF

START:  LD    SP,=STACK
        LD    A,=AX0
        ST    A,AX
        LD    A,=AY0
        ST    A,AY
        LD    EA,=256
        ST    EA,FDEP
        LD    A,=HBRATE
        ST    A,HBDIV
        LD    A,=0x02
        ST    A,LEDMASK
        JSR   BLANK
FRAME:  JSR   PROJECT
        JSR   HEARTB
        LD    A,=REPS
        ST    A,RCNT
RPTLP:  JSR   DRAWCUBE
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

; ------------------------------------------------------------
; HEARTB: march one lit LED F1->F2->F3->F1.  Writes the whole INS8070
; status register (LD S,A) to light exactly one F-flag output each frame -
; no AND S needed.  Re-asserted every frame so it is always visibly lit.
HEARTB: LD    A,LEDMASK
        SL    A
        AND   A,=0x0E
        BNZ   HBOK
        LD    A,=0x02
HBOK:   ST    A,LEDMASK
        LD    S,A
        RET


DRAWCUBE:
        LD    P3,=ROUTE
        LD    A,=NROUTE
        ST    A,ECNT
EDGELP: LD    A,@1(P3)
        JSR   GETVERT
        LD    P2,=DAC
        LD    A,VSX
        ST    A,0(P2)
        LD    A,VSY
        ST    A,1(P2)
        JSR   DWELL
        DLD   A,ECNT
        BNZ   EDGELP
        LD    P2,=DAC
        LD    A,=1
        ST    A,3(P2)
        RET

DWELL:  LD    A,=DWCNT
        ST    A,DWMEM
DWLP:   DLD   A,DWMEM
        BNZ   DWLP
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
        LD    A,=8
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
        ST    EA,X2V
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
        ST    EA,Y2V
        LD    A,VY
        ST    A,MA
        LD    A,SAC
        ST    A,MS
        JSR   MULFIX
        ST    EA,ACC
        LD    A,Z1
        ST    A,MA
        LD    A,CAC
        ST    A,MS
        JSR   MULFIX
        ADD   EA,ACC
        ADD   EA,FDEP
        ST    EA,ZC
        LD    EA,X2V
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        JSR   SDIV
        ADD   EA,=128
        ST    A,@1(P2)
        LD    EA,Y2V
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        JSR   SDIV
        ADD   EA,=128
        ST    A,@1(P2)
        RET

SDIV:   ST    EA,DNUM
        LD    A,E
        BP    SDP
        LD    EA,=0
        SUB   EA,DNUM
        LD    A,=1
        ST    A,DSIGN
        BRA   SDD
SDP:    LD    EA,DNUM
        LD    A,=0
        ST    A,DSIGN
SDD:    LD    T,ZC
        DIV   EA,T
        ST    EA,DNUM
        LD    A,DSIGN
        BZ    SDDONE
        LD    EA,=0
        SUB   EA,DNUM
        RET
SDDONE: LD    EA,DNUM
        RET

; MULFIX (optimized): EA = (MA*MS)>>6 signed, via sign-extend + unsigned MPY.
MULFIX: LD    A,=0
        LD    E,A
        LD    A,MS
        BP    MK1
        LD    A,=0xFF
        LD    E,A
        LD    A,MS
MK1:    LD    T,EA            ; T = sign-extend(MS)
        LD    A,=0
        LD    E,A
        LD    A,MA
        BP    MK2
        LD    A,=0xFF
        LD    E,A
        LD    A,MA
MK2:    MPY   EA,T            ; signed product in T (low 16 bits)
        LD    EA,T
        ADD   EA,=0x8000      ; bias for arithmetic shift
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SUB   EA,=0x200       ; unbias  -> floor(product/64)
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

DRAWLN: LD    P2,=DAC
        LD    A,=1
        ST    A,2(P2)
        LD    A,X0
        ST    A,0(P2)
        LD    A,Y0
        ST    A,1(P2)
        LD    A,=0
        ST    A,2(P2)
        LD    A,=0
        ST    A,XACC
        ST    A,YACC
        LD    A,X0
        ST    A,XACC+1
        LD    A,Y0
        ST    A,YACC+1
        LD    A,=0
        LD    E,A
        LD    A,X1
        ST    EA,XSTP
        LD    A,=0
        LD    E,A
        LD    A,X0
        ST    EA,TMP16
        LD    EA,XSTP
        SUB   EA,TMP16
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        ST    EA,XSTP
        LD    A,=0
        LD    E,A
        LD    A,Y1
        ST    EA,YSTP
        LD    A,=0
        LD    E,A
        LD    A,Y0
        ST    EA,TMP16
        LD    EA,YSTP
        SUB   EA,TMP16
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        ST    EA,YSTP
        LD    A,=STEPS+1
        ST    A,CNT
DLLOOP: LD    A,XACC+1
        ST    A,0(P2)
        LD    A,YACC+1
        ST    A,1(P2)
        LD    EA,XACC
        ADD   EA,XSTP
        ST    EA,XACC
        LD    EA,YACC
        ADD   EA,YSTP
        ST    EA,YACC
        DLD   A,CNT
        BNZ   DLLOOP
        RET

; ============================================================
SINE:   DB    0x00, 0x06, 0x0C, 0x13, 0x18, 0x1E, 0x24, 0x29, 0x2D, 0x31, 0x35, 0x38, 0x3B, 0x3D, 0x3F, 0x40
        DB    0x40, 0x40, 0x3F, 0x3D, 0x3B, 0x38, 0x35, 0x31, 0x2D, 0x29, 0x24, 0x1E, 0x18, 0x13, 0x0C, 0x06
        DB    0x00, 0xFA, 0xF4, 0xED, 0xE8, 0xE2, 0xDC, 0xD7, 0xD3, 0xCF, 0xCB, 0xC8, 0xC5, 0xC3, 0xC1, 0xC0
        DB    0xC0, 0xC0, 0xC1, 0xC3, 0xC5, 0xC8, 0xCB, 0xCF, 0xD3, 0xD7, 0xDC, 0xE2, 0xE8, 0xED, 0xF4, 0xFA
VERTS:  DB    0xCE, 0xCE, 0xCE
        DB    0x32, 0xCE, 0xCE
        DB    0xCE, 0x32, 0xCE
        DB    0x32, 0x32, 0xCE
        DB    0xCE, 0xCE, 0x32
        DB    0x32, 0xCE, 0x32
        DB    0xCE, 0x32, 0x32
        DB    0x32, 0x32, 0x32
; continuous route: covers all 12 edges with 3 invisible retraces
;   0-1-3-2-0-4-5-7-6-4-5-1-3-7-6-2  (retraces 4-5, 1-3, 7-6)
ROUTE:  DB    0,1,3,2,0,4,5,7,6,4,5,1,3,7,6,2
PCOORD: DS    16

