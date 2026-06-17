; ============================================================
;  MC6400 / INS8070  -  ROTATING wireframe cube on an X-Y scope
;
;  Per frame:  rotate 8 vertices about Y(beta=AY) then X(alpha=AX),
;  orthographic projection, then draw 12 edges via the interpolating
;  line engine to the double-buffered X/Y DAC.
;    x1 = mf(vx,cosB) + mf(vz,sinB)
;    z1 = mf(vz,cosB) - mf(vx,sinB)
;    y2 = mf(vy,cosA) - mf(z1,sinA)        sx=x1+128  sy=y2+128
;  mf(a,s) = signed( |a|*|s| >>6 ) using the unsigned hardware MPY.
;  Fixed point: sine table scaled x64.   DAC at 0xE000..0xE003.
; ============================================================
        ORG   0x1000

DAC     EQU   0xE000
STEPS   EQU   8               ; points per edge = STEPS+1
DAX     EQU   1               ; X-tumble speed (table steps / frame)
DAY     EQU   2               ; Y-spin speed
AX0     EQU   10              ; initial angles
AY0     EQU   6

; ---- fast internal-RAM vars (0xFFC0+, direct addressing) ----
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
AX      EQU   0xFFD2          ; rotation angle about X
AY      EQU   0xFFD3          ; rotation angle about Y
CAC     EQU   0xFFD4          ; cos(AX)
SAC     EQU   0xFFD5          ; sin(AX)
CBC     EQU   0xFFD6          ; cos(AY)
SBC     EQU   0xFFD7          ; sin(AY)
MA      EQU   0xFFD8          ; MULFIX input a
MS      EQU   0xFFD9          ; MULFIX input s
MSIGN   EQU   0xFFDA
MTMP    EQU   0xFFDB          ; 2 bytes
ACC     EQU   0xFFDD          ; 2 bytes
Z1      EQU   0xFFDF
VX      EQU   0xFFE0
VY      EQU   0xFFE1
VZ      EQU   0xFFE2
VCNT    EQU   0xFFE3
SPIN    EQU   0xFFE4          ; heartbeat segment pattern
HBDIV   EQU   0xFFE5          ; heartbeat frame divider (low duty)
STACK   EQU   0x13FF

; ============================================================
START:  LD    SP,=STACK
        LD    A,=AX0
        ST    A,AX
        LD    A,=AY0
        ST    A,AY
        LD    A,=0x01
        ST    A,SPIN

FRAME:  JSR   PROJECT         ; fill PCOORD[] for current angles
; ---- draw 12 edges ----
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
        LD    A,=1            ; frame marker (P2 = DAC)
        ST    A,3(P2)
; ---- advance angles ----
        LD    A,AX
        ADD   A,=DAX
        ST    A,AX
        LD    A,AY
        ADD   A,=DAY
        ST    A,AY
        JSR   HEARTB
        BRA   FRAME

; HEARTB: low-duty "alive" indicator on display digit 0 — a rotating segment,
; lit only 1 frame in 4 (blanked otherwise) to keep LED duty low for long runs.
HEARTB: LD    P2,=0xFD00
        LD    A,=0x01
        ST    A,0(P2)          ; select digit 0
        ILD   A,HBDIV          ; frame divider
        AND   A,=0x03
        BNZ   HBOFF            ; 3 of 4 frames: blank
        LD    A,SPIN           ; on-frame: advance + show the rotating segment
        SL    A
        BNZ   HBSET
        LD    A,=0x01
HBSET:  ST    A,SPIN
        ST    A,16(P2)         ; segment pattern -> 0xFD10
        RET
HBOFF:  LD    A,=0
        ST    A,16(P2)         ; blank segments (low duty)
        RET

; ============================================================
; PROJECT: compute PCOORD[0..7] = projected (sx,sy) for all vertices
PROJECT: LD   A,AY            ; cos/sin cache
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

; PROJ1: project one vertex.  reads vx,vy,vz via P3++, writes sx,sy via P2++
PROJ1:  LD    A,@1(P3)
        ST    A,VX
        LD    A,@1(P3)
        ST    A,VY
        LD    A,@1(P3)
        ST    A,VZ
; sx = (mf(vx,cosB) + mf(vz,sinB)) + 128
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
        ST    A,@1(P2)        ; sx
; z1 = mf(vz,cosB) - mf(vx,sinB)
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
; sy = (mf(vy,cosA) - mf(z1,sinA)) + 128
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
        ST    A,@1(P2)        ; sy
        RET

; MULFIX: EA = signed( |MA|*|MS| >> 6 ).  MA,MS signed bytes.
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
        LD    E,A             ; E=0
        LD    A,MS
        LD    T,EA            ; T = 00MS
        LD    A,MA            ; EA = 00MA
        MPY   EA,T            ; T = product (EA=0)
        LD    EA,T
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA
        SR    EA              ; EA = product/64
        ST    EA,MTMP         ; save magnitude (LD A,MSIGN clobbers EA low byte!)
        LD    A,MSIGN
        BZ    MFPOS
        LD    EA,=0
        SUB   EA,MTMP         ; EA = -magnitude
        RET
MFPOS:  LD    EA,MTMP         ; EA = +magnitude
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

; GETVERT: A = vertex index -> VSX,VSY = PCOORD[index]
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

; DRAWLN: interpolate (X0,Y0)->(X1,Y1), STEPS+1 points, blanked retrace
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
; data
; sine table, 64 signed bytes, value = round(64*sin(2*pi*i/64))
SINE:   DB    0x00, 0x06, 0x0C, 0x13, 0x18, 0x1E, 0x24, 0x29, 0x2D, 0x31, 0x35, 0x38, 0x3B, 0x3D, 0x3F, 0x40
        DB    0x40, 0x40, 0x3F, 0x3D, 0x3B, 0x38, 0x35, 0x31, 0x2D, 0x29, 0x24, 0x1E, 0x18, 0x13, 0x0C, 0x06
        DB    0x00, 0xFA, 0xF4, 0xED, 0xE8, 0xE2, 0xDC, 0xD7, 0xD3, 0xCF, 0xCB, 0xC8, 0xC5, 0xC3, 0xC1, 0xC0
        DB    0xC0, 0xC0, 0xC1, 0xC3, 0xC5, 0xC8, 0xCB, 0xCF, 0xD3, 0xD7, 0xDC, 0xE2, 0xE8, 0xED, 0xF4, 0xFA
; 8 vertices (vx,vy,vz) signed, +/-50 (0x32 / 0xCE)
VERTS:  DB    0xCE, 0xCE, 0xCE      ; 0 (-,-,-)
        DB    0x32, 0xCE, 0xCE      ; 1 (+,-,-)
        DB    0xCE, 0x32, 0xCE      ; 2 (-,+,-)
        DB    0x32, 0x32, 0xCE      ; 3 (+,+,-)
        DB    0xCE, 0xCE, 0x32      ; 4 (-,-,+)
        DB    0x32, 0xCE, 0x32      ; 5 (+,-,+)
        DB    0xCE, 0x32, 0x32      ; 6 (-,+,+)
        DB    0x32, 0x32, 0x32      ; 7 (+,+,+)
; 12 edges (vertex index pairs)
EDGES:  DB    0x00, 0x01, 0x01, 0x03, 0x03, 0x02, 0x02, 0x00
        DB    0x00, 0x04, 0x04, 0x05, 0x05, 0x07, 0x07, 0x06
        DB    0x06, 0x04, 0x05, 0x01, 0x03, 0x07, 0x02, 0x06
; projected coords, filled each frame
PCOORD: DS    16
