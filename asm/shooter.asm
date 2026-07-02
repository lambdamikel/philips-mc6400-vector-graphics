; ============================================================
;  MC6400 / INS8070 - VECTOR SHOOTER  (fixed-config build)
;    Play:  4 = left, 6 = right, 0 = fire ; F1/F2/F3 = aliens-left bar
;  Aliens are a 3-column x N-row grid; clear the wave or get overrun and
;  it auto-respawns.  Endpoints-only + Z-blank between objects.
;
;  Wave/speed are set at build time (four EQUs below) so each variant is a
;  small standalone .RAM - pick one per exhibit.  Values patched per build:
;    NAL   = alien count  (3 / 6 / 9)
;    GRPY0 = formation top (200 / 174 / 148 for 1 / 2 / 3 rows)
;    SAM   = ticks/alien-move (slow 4, med 2, fast 1)
;    SDS   = descend step     (slow 8, med 12, fast 16)
; ============================================================
        ORG   0x1000
DAC     EQU   0xE000
KP      EQU   0xFD00
STACK   EQU   0x13FF

; ---- per-build config (default = 6 aliens, medium) ----
NAL     EQU   6
GRPY0   EQU   174
SAM     EQU   2
SDS     EQU   12

REPS    EQU   4               ; redraws per logic tick (lower = faster game)
DWCNT   EQU   12
GUNSTEP EQU   8
GUNY    EQU   30
GXMIN   EQU   24
GXMAX   EQU   232
COLSP   EQU   56
ROWSP   EQU   26
GRPXMIN EQU   24
GRPXMAX EQU   120
GDIR0   EQU   8               ; alien shuffle step (bigger = faster)
LOSEY   EQU   52
BULY0   EQU   46
BULSPD  EQU   20
BULYMX  EQU   214
HW      EQU   14
HH      EQU   12
WINCYC  EQU   12              ; victory blink half-cycles
FLREPS  EQU   30              ; redraws per bright half-cycle (~5x longer on-screen)

GUNX    EQU   0xFFC0
OX      EQU   0xFFC1
OY      EQU   0xFFC2
PCNT    EQU   0xFFC3
DWMEM   EQU   0xFFC4
BULX    EQU   0xFFC5
BULY    EQU   0xFFC6
BULACT  EQU   0xFFC7
GRPX    EQU   0xFFC8
GRPY    EQU   0xFFC9
GDIR    EQU   0xFFCA
TICK    EQU   0xFFCB
RCNT    EQU   0xFFCC
KL      EQU   0xFFCD
KR      EQU   0xFFCE
KF      EQU   0xFFCF
AX      EQU   0xFFD0
AY      EQU   0xFFD1
TMP     EQU   0xFFD2
ALCNT   EQU   0xFFD3
COLX    EQU   0xFFD4
ROWY    EQU   0xFFD5
ROW     EQU   0xFFD6
COL     EQU   0xFFD7
AIDX    EQU   0xFFD8          ; 16-bit (D8 lo, D9 hi=0)
MASK    EQU   0xFFDA
ALIVE   EQU   0xFFDB          ; 9 bytes DB..E3
MSGSEL  EQU   0xFFE4          ; 0 = WIN, 1 = lose (X)

; ============================================================
START:  LD    SP,=STACK
        LD    A,=128
        ST    A,GUNX
        JSR   INITWAVE
FRAME:  LD    P2,=DAC
        LD    A,=1
        ST    A,2(P2)
        JSR   LOGIC
        LD    A,=REPS
        ST    A,RCNT
RDRAW:  JSR   DRAWALL
        DLD   A,RCNT
        BNZ   RDRAW
        LD    P2,=DAC
        LD    A,=1
        ST    A,3(P2)
        BRA   FRAME

; ============================================================
SETUPFORM:
        LD    A,=NAL
        ST    A,ALCNT
        LD    A,=0
        ST    A,AIDX
        ST    A,AIDX+1
        LD    EA,=ALIVE
        LD    P2,EA
SFL:    LD    A,AIDX
        SUB   A,=NAL
        LD    A,S
        AND   A,=0x80
        BZ    SFA
        LD    A,=0
        BRA   SFS
SFA:    LD    A,=1
SFS:    ST    A,@1(P2)
        ILD   A,AIDX
        SUB   A,=9
        LD    A,S
        AND   A,=0x80
        BZ    SFL
        LD    A,=GRPXMIN
        ST    A,GRPX
        LD    A,=GDIR0
        ST    A,GDIR
        LD    A,=GRPY0
        ST    A,GRPY
        RET

INITWAVE:
        JSR   SETUPFORM
        LD    A,=0
        ST    A,BULACT
        LD    A,=SAM
        ST    A,TICK
        RET

; ============================================================
LOGIC:  JSR   READIN
        LD    A,KL              ; turret left
        BNZ   NOLEFT
        LD    A,GUNX
        SUB   A,=GUNSTEP
        ST    A,TMP
        SUB   A,=GXMIN
        LD    A,S
        AND   A,=0x80
        BZ    CLL
        LD    A,TMP
        ST    A,GUNX
        BRA   NOLEFT
CLL:    LD    A,=GXMIN
        ST    A,GUNX
NOLEFT: LD    A,KR              ; turret right
        BNZ   NORT
        LD    A,GUNX
        ADD   A,=GUNSTEP
        ST    A,TMP
        LD    A,=GXMAX
        SUB   A,TMP
        LD    A,S
        AND   A,=0x80
        BZ    CLR
        LD    A,TMP
        ST    A,GUNX
        BRA   NORT
CLR:    LD    A,=GXMAX
        ST    A,GUNX
NORT:   LD    A,KF              ; fire
        BNZ   NOFIRE
        LD    A,BULACT
        BNZ   NOFIRE
        LD    A,=1
        ST    A,BULACT
        LD    A,GUNX
        ST    A,BULX
        LD    A,=BULY0
        ST    A,BULY
NOFIRE: LD    A,BULACT          ; advance bullet
        BZ    NOBUL
        LD    A,BULY
        ADD   A,=BULSPD
        ST    A,BULY
        LD    A,=BULYMX
        SUB   A,BULY
        LD    A,S
        AND   A,=0x80
        BNZ   NOBUL
        LD    A,=0
        ST    A,BULACT
NOBUL:  DLD   A,TICK            ; move formation
        BNZ   NOMOVE
        LD    A,=SAM
        ST    A,TICK
        LD    A,GRPX
        ADD   A,GDIR
        ST    A,GRPX
        LD    A,GRPX
        SUB   A,=GRPXMIN
        LD    A,S
        AND   A,=0x80
        BZ    BOUNCE
        LD    A,=GRPXMAX
        SUB   A,GRPX
        LD    A,S
        AND   A,=0x80
        BNZ   NOMOVE
BOUNCE: LD    A,=0
        SUB   A,GDIR
        ST    A,GDIR
        LD    A,GRPX
        ADD   A,GDIR
        ST    A,GRPX
        LD    A,GRPY
        SUB   A,=SDS
        ST    A,GRPY
NOMOVE: LD    A,BULACT          ; collisions
        BZ    NOCOLL
        LD    A,=0
        ST    A,AIDX
        ST    A,AIDX+1
        LD    A,GRPY
        ST    A,ROWY
        LD    A,=0
        ST    A,ROW
CRW:    LD    A,GRPX
        ST    A,COLX
        LD    A,=0
        ST    A,COL
CCL:    LD    EA,=ALIVE
        ADD   EA,AIDX
        LD    P2,EA
        LD    A,0(P2)
        BZ    CNX
        LD    A,COLX
        ST    A,AX
        LD    A,ROWY
        ST    A,AY
        JSR   HITCHK
        BZ    CNX
        LD    A,=0
        ST    A,0(P2)
        DLD   A,ALCNT
        LD    A,=0
        ST    A,BULACT
        BRA   NOCOLL
CNX:    ILD   A,AIDX
        LD    A,COLX
        ADD   A,=COLSP
        ST    A,COLX
        ILD   A,COL
        SUB   A,=3
        LD    A,S
        AND   A,=0x80
        BZ    CCL
        LD    A,ROWY
        ADD   A,=ROWSP
        ST    A,ROWY
        ILD   A,ROW
        SUB   A,=3
        LD    A,S
        AND   A,=0x80
        BZ    CRW
NOCOLL: LD    A,ALCNT           ; win / lose
        BZ    DOWIN
        ; lose only when the LOWEST STILL-LIVING alien reaches LOSEY
        ; (rows are ALIVE[0..2]=bottom, [3..5], [6..8]; ROWY climbs by ROWSP)
        LD    EA,=ALIVE
        LD    P2,EA
        LD    A,GRPY
        ST    A,ROWY
        LD    A,=3
        ST    A,ROW
LRW:    LD    A,=3
        ST    A,COL
LRC:    LD    A,@1(P2)
        BNZ   GOTROW
        DLD   A,COL
        BNZ   LRC
        LD    A,ROWY
        ADD   A,=ROWSP
        ST    A,ROWY
        DLD   A,ROW
        BNZ   LRW
GOTROW: LD    A,=LOSEY
        SUB   A,ROWY
        LD    A,S
        AND   A,=0x80
        BZ    NORESP
        LD    A,=1              ; overrun -> "X" then next wave
        ST    A,MSGSEL
        JSR   FLASH
        JSR   INITWAVE
        BRA   NORESP
DOWIN:  LD    A,=0              ; cleared -> "WIN!" then next wave
        ST    A,MSGSEL
        JSR   FLASH
        JSR   INITWAVE
NORESP: LD    A,=0              ; F-LED aliens-left bar
        ST    A,MASK
        LD    A,ALCNT
        BZ    FPD
        LD    A,=0x02
        ST    A,MASK
        LD    A,ALCNT
        SUB   A,=4
        LD    A,S
        AND   A,=0x80
        BZ    FPD
        LD    A,=0x06
        ST    A,MASK
        LD    A,ALCNT
        SUB   A,=7
        LD    A,S
        AND   A,=0x80
        BZ    FPD
        LD    A,=0x0E
        ST    A,MASK
FPD:    LD    A,MASK
        LD    S,A
        RET

; ============================================================
; FLASH - blink the win/lose graphic + all F-LEDs a few times
FLASH:  LD    A,=WINCYC
        ST    A,ROW
WF1:    LD    A,ROW
        AND   A,=1
        BZ    WFDARK
        LD    A,=0x0E
        LD    S,A
        LD    A,=FLREPS
        ST    A,RCNT
WFDR:   JSR   SHOWMSG
        LD    P2,=DAC
        LD    A,=1
        ST    A,3(P2)
        DLD   A,RCNT
        BNZ   WFDR
        BRA   WFNX
WFDARK: LD    A,=0
        LD    S,A
        LD    P2,=DAC
        LD    A,=1
        ST    A,2(P2)
        LD    A,=REPS
        ST    A,RCNT
WFDK:   JSR   DWELL
        JSR   DWELL
        LD    P2,=DAC
        LD    A,=1
        ST    A,3(P2)
        DLD   A,RCNT
        BNZ   WFDK
WFNX:   DLD   A,ROW
        BNZ   WF1
        RET

; SHOWMSG - draw WIN! or the X depending on MSGSEL (tail-calls, returns to FLASH)
SHOWMSG:LD    A,MSGSEL
        BZ    WINDRAW
        BRA   LOSEDRAW

; WINDRAW - the word "WIN" in vector strokes, centred
WINDRAW:LD    A,=98
        ST    A,OX
        LD    A,=128
        ST    A,OY
        LD    P3,=LW
        JSR   DRAWOBJ
        LD    A,=128
        ST    A,OX
        LD    A,=128
        ST    A,OY
        LD    P3,=LI
        JSR   DRAWOBJ
        LD    A,=158
        ST    A,OX
        LD    A,=128
        ST    A,OY
        LD    P3,=LN
        JSR   DRAWOBJ
        RET

; LOSEDRAW - a big X (crossed out), centred
LOSEDRAW:
        LD    A,=128
        ST    A,OX
        LD    A,=128
        ST    A,OY
        LD    P3,=XA
        JSR   DRAWOBJ
        LD    A,=128
        ST    A,OX
        LD    A,=128
        ST    A,OY
        LD    P3,=XB
        JSR   DRAWOBJ
        RET

; ============================================================
HITCHK: LD    A,AX
        SUB   A,=HW
        ST    A,TMP
        LD    A,BULX
        SUB   A,TMP
        LD    A,S
        AND   A,=0x80
        BZ    MISS
        LD    A,AX
        ADD   A,=HW
        SUB   A,BULX
        LD    A,S
        AND   A,=0x80
        BZ    MISS
        LD    A,AY
        SUB   A,=HH
        ST    A,TMP
        LD    A,BULY
        SUB   A,TMP
        LD    A,S
        AND   A,=0x80
        BZ    MISS
        LD    A,AY
        ADD   A,=HH
        SUB   A,BULY
        LD    A,S
        AND   A,=0x80
        BZ    MISS
        LD    A,=1
        RET
MISS:   LD    A,=0
        RET

; ============================================================
READIN: LD    P2,=KP
        LD    A,=0x10
        ST    A,0(P2)
        LD    A,0(P2)
        AND   A,=0x01
        ST    A,KL
        LD    A,=0x40
        ST    A,0(P2)
        LD    A,0(P2)
        AND   A,=0x01
        ST    A,KR
        LD    A,=0x01
        ST    A,0(P2)
        LD    A,0(P2)
        AND   A,=0x01
        ST    A,KF
        ; ---- fold in SA/SB console buttons (SA=left, SB=right, both=fire) ----
        LD    A,S
        ST    A,TMP
        AND   A,=0x30              ; SA & SB both set?
        SUB   A,=0x30
        BZ    SBOTH
        LD    A,TMP
        AND   A,=0x10              ; SA -> left
        BZ    SCHKB
        LD    A,=0
        ST    A,KL
        BRA   SDONE
SCHKB:  LD    A,TMP
        AND   A,=0x20             ; SB -> right
        BZ    SDONE
        LD    A,=0
        ST    A,KR
        BRA   SDONE
SBOTH:  LD    A,=0
        ST    A,KF                 ; both -> fire
SDONE:  RET

; ============================================================
DRAWALL:LD    A,GUNX
        ST    A,OX
        LD    A,=GUNY
        ST    A,OY
        LD    P3,=GUN
        JSR   DRAWOBJ
        LD    A,=0
        ST    A,AIDX
        ST    A,AIDX+1
        LD    A,GRPY
        ST    A,ROWY
        LD    A,=0
        ST    A,ROW
DRW:    LD    A,GRPX
        ST    A,COLX
        LD    A,=0
        ST    A,COL
DCL:    LD    EA,=ALIVE
        ADD   EA,AIDX
        LD    P2,EA
        LD    A,0(P2)
        BZ    DNX
        LD    A,COLX
        ST    A,OX
        LD    A,ROWY
        ST    A,OY
        LD    P3,=ALIEN
        JSR   DRAWOBJ
DNX:    ILD   A,AIDX
        LD    A,COLX
        ADD   A,=COLSP
        ST    A,COLX
        ILD   A,COL
        SUB   A,=3
        LD    A,S
        AND   A,=0x80
        BZ    DCL
        LD    A,ROWY
        ADD   A,=ROWSP
        ST    A,ROWY
        ILD   A,ROW
        SUB   A,=3
        LD    A,S
        AND   A,=0x80
        BZ    DRW
        LD    A,BULACT
        BZ    DAEND
        LD    A,BULX
        ST    A,OX
        LD    A,BULY
        ST    A,OY
        LD    P3,=BULLET
        JSR   DRAWOBJ
DAEND:  RET

DRAWOBJ:LD    A,@1(P3)
        ST    A,PCNT
        LD    P2,=DAC
        LD    A,=1
        ST    A,2(P2)
        JSR   PLOT
        LD    P2,=DAC
        LD    A,=0
        ST    A,2(P2)
        DLD   A,PCNT
DOLP:   JSR   PLOT
        DLD   A,PCNT
        BNZ   DOLP
        RET

PLOT:   LD    A,@1(P3)
        ADD   A,OX
        LD    P2,=DAC
        ST    A,0(P2)
        LD    A,@1(P3)
        ADD   A,OY
        ST    A,1(P2)
        JSR   DWELL
        RET

DWELL:  LD    A,=DWCNT
        ST    A,DWMEM
DWLP:   DLD   A,DWMEM
        BNZ   DWLP
        RET

; ============================================================
GUN:    DB    9
        DB    -14,0,  14,0,  14,6,  4,6,  4,14,  -4,14,  -4,6,  -14,6,  -14,0
ALIEN:  DB    7
        DB    -12,-6,  0,-10,  12,-6,  12,6,  0,10,  -12,6,  -12,-6
BULLET: DB    2
        DB    0,0,  0,8
; "WIN!" letter strokes (open paths)
LW:     DB    5
        DB    -10,14,  -5,-14,  0,4,  5,-14,  10,14
LI:     DB    2
        DB    0,14,  0,-14
LN:     DB    4
        DB    -8,-14,  -8,14,  8,-14,  8,14
; big "X" for the lose screen (two diagonal strokes)
XA:     DB    2
        DB    -22,22,  22,-22
XB:     DB    2
        DB    -22,-22,  22,22
