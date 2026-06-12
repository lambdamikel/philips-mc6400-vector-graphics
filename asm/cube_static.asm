; ============================================================
;  MC6400 / INS8070  -  static wireframe cube (baked projection)
;  Drawing engine v2: fixed-step linear interpolation to X/Y DACs.
;  On an analog XY scope the beam draws straight lines between
;  output points, so a few points per edge suffice (STEPS+1 pts).
;  DAC: 0xE000=X 0xE001=Y 0xE002=Zblank 0xE003=frame marker.
; ============================================================
        ORG   0x1000

DAC     EQU   0xE000
STEPS   EQU   8               ; points per edge = STEPS+1; xstep = d<<(8-log2 STEPS)
SHIFT   EQU   5               ; = 8 - log2(STEPS)

; ---- fast internal-RAM vars (0xFFC0+, direct addressing) ----
X0      EQU   0xFFC0
Y0      EQU   0xFFC1
X1      EQU   0xFFC2
Y1      EQU   0xFFC3
XACC    EQU   0xFFC4          ; 2 bytes, 8.8 fixed
YACC    EQU   0xFFC6          ; 2 bytes
XSTP    EQU   0xFFC8          ; 2 bytes signed
YSTP    EQU   0xFFCA          ; 2 bytes signed
TMP16   EQU   0xFFCC          ; 2 bytes
VSX     EQU   0xFFCE
VSY     EQU   0xFFCF
CNT     EQU   0xFFD0
ECNT    EQU   0xFFD1
STACK   EQU   0x13FF

; ============================================================
START:  LD    SP,=STACK
FRAME:  LD    A,=12
        ST    A,ECNT
        LD    P3,=EDGES
EDGELP: LD    A,@1(P3)        ; v0
        JSR   GETVERT
        LD    A,VSX
        ST    A,X0
        LD    A,VSY
        ST    A,Y0
        LD    A,@1(P3)        ; v1
        JSR   GETVERT
        LD    A,VSX
        ST    A,X1
        LD    A,VSY
        ST    A,Y1
        JSR   DRAWLN
        DLD   A,ECNT
        BNZ   EDGELP
        LD    A,=1            ; frame marker (P2 = DAC)
        ST    A,3(P2)
        BRA   FRAME

; ---- GETVERT: A=vertex index -> VSX,VSY = PCOORD[index] ----
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

; ---- DRAWLN: interpolate (X0,Y0)->(X1,Y1), STEPS+1 points ----
DRAWLN: LD    P2,=DAC
        LD    A,=1            ; blank, jump to start
        ST    A,2(P2)
        LD    A,X0
        ST    A,0(P2)
        LD    A,Y0
        ST    A,1(P2)
        LD    A,=0
        ST    A,2(P2)
; XACC = X0<<8 ; YACC = Y0<<8
        LD    A,=0
        ST    A,XACC
        ST    A,YACC
        LD    A,X0
        ST    A,XACC+1
        LD    A,Y0
        ST    A,YACC+1
; XSTP = signext(X1-X0) << SHIFT
        LD    A,X1
        SUB   A,X0
        ST    A,XSTP
        BP    DLXP
        LD    A,=0xFF
        ST    A,XSTP+1
        BRA   DLXS
DLXP:   LD    A,=0
        ST    A,XSTP+1
DLXS:   LD    EA,XSTP
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        ST    EA,XSTP
; YSTP = signext(Y1-Y0) << SHIFT
        LD    A,Y1
        SUB   A,Y0
        ST    A,YSTP
        BP    DLYP
        LD    A,=0xFF
        ST    A,YSTP+1
        BRA   DLYS
DLYP:   LD    A,=0
        ST    A,YSTP+1
DLYS:   LD    EA,YSTP
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        SL    EA
        ST    EA,YSTP
; emit STEPS+1 points
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
; 12 edges (vertex index pairs)
EDGES:  DB    0x00, 0x01, 0x01, 0x03, 0x03, 0x02, 0x02, 0x00
        DB    0x00, 0x04, 0x04, 0x05, 0x05, 0x07, 0x07, 0x06
        DB    0x06, 0x04, 0x05, 0x01, 0x03, 0x07, 0x02, 0x06
; baked projected coords (sx,sy) for ax=10 ay=6
PCOORD: DB    0x3B, 0x6E, 0x8D, 0x9D, 0x3B, 0xA6, 0x8D, 0xD5
        DB    0x73, 0x2B, 0xC5, 0x5A, 0x73, 0x63, 0xC5, 0x92
