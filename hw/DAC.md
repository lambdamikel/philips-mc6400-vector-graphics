# MC6400 MasterLab — X-Y Oscilloscope DAC (expansion-bus add-on)

A small, double-buffered **2-channel 8-bit R-2R DAC** that hangs off the
MC6400 expansion connector ("BUSBELEGUNG") and drives an oscilloscope in X-Y
(vector) mode.  The INS8070 writes X then Y as memory-mapped I/O; the beam
jumps straight to the new point and the scope's analog sweep draws the lines.

This is the companion hardware for the demos.  It is the first known
expansion-port peripheral for the MasterLab, so the address map below is *our*
choice — nothing on the stock machine uses the `0xE000` block.

> **Status:** this is a *paper design* — it has not been built or tested on real
> hardware yet. It was designed alongside the cycle-accurate simulator, which
> models the double-buffered behaviour exactly, but expect to tune timing/levels
> on first build.

## For a digital scope (e.g. Hantek DSO5072P)

This DAC is a plain analog X/Y source, so **it works with your DSO** — the two
channels go to CH1 (X) and CH2 (Y) in X-Y mode. Two notes:

- **Build the X and Y channels only; skip the optional Z-blank flip-flop
  (74HC74).** A DSO has no Z/intensity input, and you don't need one: all the
  demo programs draw the wireframe as a single continuous stroke (Eulerian
  route / retrace-over-existing-edges), so there are no beam jumps to blank.
- **The double-buffering (the three 74HC374s) is still required** — it makes X
  and Y update on the same edge so the beam moves in straight diagonals.

DSO setup: X-Y mode, CH1=X CH2=Y, **DC coupling**, display set to **Vectors**
(not Dots), **persistence on**, and timebase set so one frame (~50–100 ms) fits
the capture window. Adjust V/div + position to fill the screen. The hardware is
correct/compatible regardless; how smooth it *looks* depends on the DSO's X-Y
refresh — an analog CRT scope would look nicer, but is not required.

## Block diagram

```
  Bus signals               Address decode  (74LS04 + 74LS21 + 74LS138)
  -----------               ----------------------------------------------
  A12 A13 A14 A15  ----->    BLKSEL = A15 & A14 & A13 & !A12
  A0  A1           ----->    74LS138 select inputs
  NWDS (write)     ----->    74LS138 enable = BLKSEL & NWDS
                                |
                                +--> XCLK    write 0xE000
                                +--> YCLK    write 0xE001  (commit)
                                +--> ZCLK    write 0xE002  (optional Z-blank)

  Data path  (X-out and Y-out are BOTH clocked by YCLK, so X and Y update together)

  D0..D7 --+--> [ X-hold 74HC374 ] --Q--> [ X-out 74HC374 ] --Q--> [ R-2R X ] --> op-amp --> CH1 (X)
           |         clk = XCLK                clk = YCLK
           |
           +------------------------------> [ Y-out 74HC374 ] --Q--> [ R-2R Y ] --> op-amp --> CH2 (Y)
                                                 clk = YCLK
```

## Address map (our decode)

| Address | Write does | Clocks |
|---------|-----------|--------|
| `0xE000` | load X into holding latch (beam does NOT move) | X-hold (74HC374 #1) |
| `0xE001` | **commit**: X-out ← X-hold and Y-out ← data, simultaneously | X-out (#2) + Y-out (#3) |
| `0xE002` | Z / beam-blank bit (optional) | Z flip-flop (74HC74) |

The program always writes **X first, then Y**; the Y write commits both axes at
once so the beam moves in a straight diagonal (no L-shaped staircase).  Only
`A15..A12` and `A1,A0` are decoded, so the whole `0xE000–0xEFFF` block aliases
to these few registers — harmless, since nothing else lives there.

## Why double-buffered (3 latches, not 2)

With two independent latches the beam visibly jogs horizontally then vertically
between every point (X updates before Y).  The X-holding latch + a common
commit strobe make X and Y update on the same clock edge, giving clean vectors.
Verified in the simulator (`sim/ins8070.py` models exactly this).

## The R-2R ladder (one per channel)

Each 74HC374 output bit drives the ladder rail-to-rail (0 V / +5 V). Standard
8-bit voltage-mode R-2R, with **R = 10 kΩ** and **2R = 20 kΩ**:

```
   Vout (MSB node)
    |
    +--[R]--+--[R]--+--[R]--+--[R]--+--[R]--+--[R]--+--[R]--+--[2R]--GND
    |       |       |       |       |       |       |       |
   [2R]    [2R]    [2R]    [2R]    [2R]    [2R]    [2R]    [2R]
    |       |       |       |       |       |       |       |
    D7      D6      D5      D4      D3      D2      D1      D0
   (MSB)                                                   (LSB)

   Vout --> op-amp unity-gain buffer (e.g. MCP6002) --> scope X (or Y), ~0..5 V
```

The **X-out** latch's `Q` outputs feed the X ladder; the **Y-out** latch
(clocked by the same `0xE001` commit strobe, but with its `D` inputs taken
straight from the data bus) feeds the Y ladder. So on the commit write, X-out
latches the held X value and Y-out latches the current bus value (Y) — both on
one edge. Use **0.1 % resistors (or a matched network)** for a monotonic 8-bit
ladder.

## Bill of materials

| Qty | Part | Purpose | Notes |
|-----|------|---------|-------|
| 3 | **74HC374** octal D-latch | X-hold, X-out, Y-out | **HC (CMOS)** — clean 0/5 V outputs for ladder accuracy. Don't use LS here. |
| 1 | 74LS138 (or 74HC138) | 3→8 line decoder → channel strobes | |
| 1 | 74LS21 (or 74HC21) | dual 4-input AND | `BLKSEL = A15·A14·A13·!A12` |
| 1 | 74LS04 (or 74HC04) | hex inverter | for `!A12` (and spare) |
| 1 | MCP6002 (rail-to-rail dual op-amp) | X & Y output buffers | single +5 V; or TL072 with ±supply |
| 32 | resistors for 2× R-2R | DAC ladders | R=10 kΩ, 2R=20 kΩ. **Use 0.1 % (or a matched network)** for monotonic 8-bit. |
| 1 | 74HC74 (optional) | Z/blank flip-flop | only if your scope has a Z (intensity) input |
| — | 0.1 µF decoupling caps (1 per IC), header/ribbon to bus | | |

Powered from the bus **+5 V / GND** (the connector supplies it).

## Decode logic — discrete vs GAL

**Discrete (no programmer needed):**
```
!A12   = 74LS04 inverter
BLKSEL = 74LS21:  A13 & A14 & A15 & !A12
74LS138:  G1 = BLKSEL,  /G2A = NWDS,  /G2B = GND,  A = A0, B = A1, C = GND
          Y0 -> 74HC374 X-hold CLK
          Y1 -> 74HC374 X-out CLK  AND  Y-out CLK   (tie together)
          Y2 -> 74HC74  Z clock (D = D0)
```
A '138 output idles HIGH, pulses LOW during the matching write, and returns
HIGH (rising edge) when `NWDS` releases — that rising edge clocks the '374s,
latching data that is stable through the write.

**GAL/ATF16V8 (one chip, if you have a programmer)** — WinCUPL:
```
FIELD addr = [A15..A12];
BLKSEL = (addr:E000);                 /* A15·A14·A13·!A12 */
XCLK = !(BLKSEL & !NWDS & !A1 & !A0); /* active-low strobe, 0xE000 */
YCLK = !(BLKSEL & !NWDS & !A1 &  A0); /* commit, 0xE001 */
ZCLK = !(BLKSEL & !NWDS &  A1 & !A0); /* 0xE002 */
```

## Wiring to the MC6400 "BUSBELEGUNG" connector

Take from the expansion connector (see `pics/mc6400-bus.jpg` in the picoram
repo): `D0–D7`, `A0`, `A1`, `A12`, `A13`, `A14`, `A15`, **`NWDS`** (Write
Strobe, active-low), `+5V`, `GND`.  (You do *not* need `NRDS`, the other address
lines, `NBREQ`, or `NRST` for this write-only DAC.)

## Output / scope setup

- Each ladder → op-amp **unity follower** → scope X (and Y) input, giving
  ~0–5 V per axis.  Set the scope to **X-Y mode**, DC-coupled, and use the
  position/gain knobs to centre and size the figure.
- For a centred ±2.5 V swing, use the op-amp as a difference amp subtracting a
  2.5 V reference instead of a plain follower.
- **Z/blank (optional):** if the scope has a rear Z (intensity) input, drive it
  from the Z flip-flop (blank = beam off during retrace) for a perfectly clean
  wireframe.  Without it you'll see faint retrace lines on a non-blanking scope —
  but the demos avoid this by drawing in one continuous stroke. You can also
  blank using an INS8070 flag output (`F1/F2/F3`) instead of the `0xE002` latch.

## Bring-up / test

**0. Before building anything**, load a `.RAM` over PicoRAM and run it: every demo
spins one segment of the built-in display (digit 0) once per frame, so you can
confirm the program is alive on the real machine before soldering the DAC.

1. With no program running, manually (or with a tiny test program) write a few
   values to `0xE000`/`0xE001` and check the two ladder/op-amp outputs with a
   meter: `0x00`→~0 V, `0x80`→~2.5 V, `0xFF`→~5 V, monotonic across codes.
2. Load `CUBE.RAM` via PicoRAM, RUN — a tumbling wireframe cube should appear.
   `asm/test1.asm` (writes a static point) is handy for first light.
3. If lines stairstep, confirm the **commit (0xE001)** clocks *both* output
   latches; if a channel is stuck, check its '374 `/OE` is tied LOW.
