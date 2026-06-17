; ============================================================
;  MC6400 / INS8070  -  ROTATING cube, PERSPECTIVE + KEYPAD CONTROL
;  Velocity-based hex-pad control (object auto-spins; keys set speed):
;    4 / 6  yaw  -/+        2 / 8  pitch -/+
;    5      stop (freeze)   0      reset to default spin
;    A / B  perspective depth +/- (less / more perspective)
;  Keypad scanned at 0xFD0x; edge-detected so one press = one nudge.
; ============================================================
        ORG   0x1000

DAC     EQU   0xE000
KP      EQU   0xFD00          ; keypad / display matrix port
STEPS   EQU   8
NROUTE  EQU   16              ; continuous cube route length
DAX0    EQU   1
DAY0    EQU   2
AX0     EQU   10
AY0     EQU   6

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
DAXV    EQU   0xFFED          ; pitch speed (signed)
DAYV    EQU   0xFFEE          ; yaw speed (signed)
KEY     EQU   0xFFEF
LASTKEY EQU   0xFFF0
KROW    EQU   0xFFF1
KMASK   EQU   0xFFF2
KVAL    EQU   0xFFF3
FDEP    EQU   0xFFF4          ; perspective depth, 2 bytes
SPIN    EQU   0xFFF6          ; heartbeat segment pattern
STACK   EQU   0x13FF

; ============================================================
START:  LD    SP,=STACK
        LD    A,=AX0
        ST    A,AX
        LD    A,=AY0
        ST    A,AY
        LD    A,=DAX0
        ST    A,DAXV
        LD    A,=DAY0
        ST    A,DAYV
        LD    A,=0xFF
        ST    A,LASTKEY
        LD    EA,=256
        ST    EA,FDEP
        LD    A,=0x01
        ST    A,SPIN
FRAME:  JSR   PROJECT
; ---- draw the wireframe as ONE continuous route (DSO-friendly) ----
        LD    P3,=ROUTE
        LD    A,@1(P3)        ; route[0] = start point
        JSR   GETVERT
        LD    A,VSX
        ST    A,X1
        LD    A,VSY
        ST    A,Y1
        LD    A,=NROUTE-1
        ST    A,ECNT
EDGELP: LD    A,X1            ; current end -> next start
        ST    A,X0
        LD    A,Y1
        ST    A,Y0
        LD    A,@1(P3)        ; next route vertex
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
        JSR   HANDLEKEY
        LD    A,AX
        ADD   A,DAXV
        ST    A,AX
        LD    A,AY
        ADD   A,DAYV
        ST    A,AY
        JSR   HEARTB
        BRA   FRAME

; HEARTB: "alive" indicator on display digit 0 (rotates one segment per frame)
HEARTB: LD    P2,=0xFD00
        LD    A,=0x01
        ST    A,0(P2)
        LD    A,SPIN
        SL    A
        BNZ   HBOK
        LD    A,=0x01
HBOK:   ST    A,SPIN
        ST    A,16(P2)
        RET

; ============================================================
; HANDLEKEY: scan keypad, edge-detect, adjust spin speed / depth
HANDLEKEY: JSR SCANKEY
        ST    A,KEY
        SUB   A,LASTKEY
        BNZ   HKGO            ; changed since last frame -> handle
        RET
HKGO:   LD    A,KEY
        ST    A,LASTKEY
        LD    A,KEY
        SUB   A,=4
        BNZ   HK6
        LD    A,DAYV
        SUB   A,=1
        ST    A,DAYV
        RET
HK6:    LD    A,KEY
        SUB   A,=6
        BNZ   HK2
        LD    A,DAYV
        ADD   A,=1
        ST    A,DAYV
        RET
HK2:    LD    A,KEY
        SUB   A,=2
        BNZ   HK8
        LD    A,DAXV
        SUB   A,=1
        ST    A,DAXV
        RET
HK8:    LD    A,KEY
        SUB   A,=8
        BNZ   HK5
        LD    A,DAXV
        ADD   A,=1
        ST    A,DAXV
        RET
HK5:    LD    A,KEY
        SUB   A,=5
        BNZ   HK0
        LD    A,=0
        ST    A,DAXV
        ST    A,DAYV
        RET
HK0:    LD    A,KEY
        BNZ   HKA             ; KEY != 0
        LD    A,=DAX0
        ST    A,DAXV
        LD    A,=DAY0
        ST    A,DAYV
        RET
HKA:    LD    A,KEY
        SUB   A,=10
        BNZ   HKB
        LD    EA,FDEP
        ADD   EA,=32
        ST    EA,FDEP
        RET
HKB:    LD    A,KEY
        SUB   A,=11
        BNZ   HKBRET
        LD    EA,FDEP
        SUB   EA,=32
        ST    EA,FDEP
        LD    EA,FDEP
        SUB   EA,=160
        LD    A,E
        BP    HKBRET          ; FDEP >= 160 ok
        LD    EA,=160
        ST    EA,FDEP
HKBRET: RET

; SCANKEY: A = pressed green hex key 0..15, or 0xFF if none
SCANKEY: LD   P2,=KP
        LD    A,=0
        ST    A,KROW
        LD    A,=1
        ST    A,KMASK
SKLP:   LD    A,KMASK
        ST    A,0(P2)         ; select row
        LD    A,0(P2)         ; read (inverted)
        ST    A,KVAL
        AND   A,=1
        BNZ   SK8F            ; bit0 set -> key 0-7 not pressed
        LD    A,KROW
        RET
SK8F:   LD    A,KVAL
        AND   A,=2
        BNZ   SKNX            ; bit1 set -> key 8-F not pressed
        LD    A,KROW
        ADD   A,=8
        RET
SKNX:   LD    A,KMASK
        SL    A
        ST    A,KMASK
        LD    A,KROW
        ADD   A,=1
        ST    A,KROW
        SUB   A,=8
        BNZ   SKLP
        LD    A,=0xFF
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
