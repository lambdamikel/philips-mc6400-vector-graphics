; ============================================================
;  MC6400 / INS8070  -  ROTATING wireframe cube, PERSPECTIVE
;  Rotate about Y then X, then perspective-divide:
;    x1 = mf(vx,cosB)+mf(vz,sinB)        (= x2)
;    z1 = mf(vz,cosB)-mf(vx,sinB)
;    y2 = mf(vy,cosA)-mf(z1,sinA)
;    z2 = mf(vy,sinA)+mf(z1,cosA)
;    zc = z2 + FDEPTH
;    sx = (x1*256)/zc + 128 ;  sy = (y2*256)/zc + 128   (signed divide)
;  mf() uses unsigned MPY; perspective uses unsigned DIV; signs by hand.
; ============================================================
        ORG   0x1000

DAC     EQU   0xE000
STEPS   EQU   8
DAX     EQU   1
DAY     EQU   2
AX0     EQU   10
AY0     EQU   6
FDEPTH  EQU   256             ; eye distance (perspective strength); 256 => center scale 1.0

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
X2V     EQU   0xFFE4          ; rotated x (=x1), 2 bytes
Y2V     EQU   0xFFE6          ; rotated y (=y2), 2 bytes
ZC      EQU   0xFFE8          ; z2 + FDEPTH, 2 bytes
DNUM    EQU   0xFFEA          ; SDIV scratch, 2 bytes
DSIGN   EQU   0xFFEC
SPIN    EQU   0xFFED          ; heartbeat segment pattern
HBDIV   EQU   0xFFEE          ; heartbeat frame divider (low duty)
STACK   EQU   0x13FF

; ============================================================
START:  LD    SP,=STACK
        LD    A,=AX0
        ST    A,AX
        LD    A,=AY0
        ST    A,AY
        LD    A,=0x01
        ST    A,SPIN
FRAME:  JSR   PROJECT
        LD    A,=12
        ST    A,ECNT
        LD    P3,=EDGES
EDGELP: LD    A,@1(P3)
        JSR   GETVERT
        LD    A,VSX
        ST    A,X0
        LD    A,VSY
        ST    A,Y0
        LD    A,@1(P3)
        JSR   GETVERT
        LD    A,VSX
        ST    A,X1
        LD    A,VSY
        ST    A,Y1
        JSR   DRAWLN
        DLD   A,ECNT
        BNZ   EDGELP
        LD    A,=1
        ST    A,3(P2)
        LD    A,AX
        ADD   A,=DAX
        ST    A,AX
        LD    A,AY
        ADD   A,=DAY
        ST    A,AY
        JSR   HEARTB
        BRA   FRAME

; HEARTB: low-duty "alive" indicator on display digit 0 — rotating segment lit
; only 1 frame in 4 (blanked otherwise) to keep LED duty low for long runs.
HEARTB: LD    P2,=0xFD00
        LD    A,=0x01
        ST    A,0(P2)
        ILD   A,HBDIV
        AND   A,=0x03
        BNZ   HBOFF
        LD    A,SPIN
        SL    A
        BNZ   HBSET
        LD    A,=0x01
HBSET:  ST    A,SPIN
        ST    A,16(P2)
        RET
HBOFF:  LD    A,=0
        ST    A,16(P2)
        RET

; ============================================================
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

; project one vertex with perspective
PROJ1:  LD    A,@1(P3)
        ST    A,VX
        LD    A,@1(P3)
        ST    A,VY
        LD    A,@1(P3)
        ST    A,VZ
; x1 = mf(vx,cosB)+mf(vz,sinB)
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
; z1 = mf(vz,cosB)-mf(vx,sinB)
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
; y2 = mf(vy,cosA)-mf(z1,sinA)
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
; z2 = mf(vy,sinA)+mf(z1,cosA)  ; zc = z2 + FDEPTH
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
        ADD   EA,=FDEPTH
        ST    EA,ZC
; sx = sdiv(x1<<8, zc) + 128
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
; sy = sdiv(y2<<8, zc) + 128
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

; SDIV: EA = signed( EA / ZC ),  ZC > 0.  (truncating)
SDIV:   ST    EA,DNUM
        LD    A,E
        BP    SDP
        LD    EA,=0
        SUB   EA,DNUM         ; EA = |num|
        LD    A,=1
        ST    A,DSIGN
        BRA   SDD
SDP:    LD    EA,DNUM
        LD    A,=0
        ST    A,DSIGN
SDD:    LD    T,ZC
        DIV   EA,T            ; EA = |num| / ZC
        ST    EA,DNUM
        LD    A,DSIGN
        BZ    SDDONE
        LD    EA,=0
        SUB   EA,DNUM         ; EA = -quotient
        RET
SDDONE: LD    EA,DNUM
        RET

; MULFIX: EA = signed( |MA|*|MS| >> 6 )
MULFIX: LD    A,=0
        ST    A,MSIGN
        LD    A,MA
        BP    MFA
        LD    A,=0
        SUB   A,MA
        ST    A,MA
        LD    A,=1
        ST    A,MSIGN
MFA:    LD    A,MS
        BP    MFB
        LD    A,=0
        SUB   A,MS
        ST    A,MS
        LD    A,MSIGN
        XOR   A,=1
        ST    A,MSIGN
MFB:    LD    A,=0
        LD    E,A
        LD    A,MS
        LD    T,EA
        LD    A,MA
        MPY   EA,T
        LD    EA,T
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        ST    EA,MTMP
        LD    A,MSIGN
        BZ    MFPOS
        LD    EA,=0
        SUB   EA,MTMP
        RET
MFPOS:  LD    EA,MTMP
        RET

; SINLK: A = SINE[A & 0x3F]
SINLK:  AND   A,=0x3F
        ST    A,TMP16
        LD    A,=0
        ST    A,TMP16+1
        LD    EA,=SINE
        ADD   EA,TMP16
        LD    P2,EA
        LD    A,0(P2)
        RET

; GETVERT: A=index -> VSX,VSY
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

; DRAWLN: interpolate (X0,Y0)->(X1,Y1)
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
; XSTP = (X1 - X0) << 5   (full signed 16-bit delta; edges can exceed +/-127)
        LD    A,=0
        LD    E,A
        LD    A,X1
        ST    EA,XSTP          ; 00X1
        LD    A,=0
        LD    E,A
        LD    A,X0
        ST    EA,TMP16         ; 00X0
        LD    EA,XSTP
        SUB   EA,TMP16         ; X1 - X0 (signed 16-bit)
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        ST    EA,XSTP
; YSTP = (Y1 - Y0) << 5
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
EDGES:  DB    0x00, 0x01, 0x01, 0x03, 0x03, 0x02, 0x02, 0x00
        DB    0x00, 0x04, 0x04, 0x05, 0x05, 0x07, 0x07, 0x06
        DB    0x06, 0x04, 0x05, 0x01, 0x03, 0x07, 0x02, 0x06
PCOORD: DS    16
