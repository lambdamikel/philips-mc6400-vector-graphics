# Philips MC6400 Vector Graphics

**Real-time 3-D wireframe vector graphics — a rotating cube, torus, and sphere —
drawn on an X-Y oscilloscope, computed live in INS8070 machine code on a 1984
Philips MC6400 "MasterLab" CPU trainer.**

The MasterLab has a 1 MHz [National INS8070](https://en.wikipedia.org/wiki/National_Semiconductor_SC/MP)
(SC/MP III) CPU and **1 KB of RAM**. With a small home-made R-2R DAC on its
expansion bus, it drives a scope in X-Y mode and tumbles shaded-free wireframe
solids in real time — perspective projection, hardware-multiply rotation, and
interactive hex-pad control, all in well under a kilobyte of code.

As far as I know this is the **first expansion-port peripheral ever built for the
MasterLab**.

<p align="center">
  <img src="media/cube.gif" width="30%" alt="rotating cube"/>
  <img src="media/torus.gif" width="30%" alt="rotating torus"/>
  <img src="media/sphere.gif" width="30%" alt="rotating sphere"/>
</p>

*(These are renders from the cycle-accurate simulator, modelling the analog
oscilloscope beam. They are produced by the exact byte stream the real CPU sends
to the DAC.)*

---

## What's in the box

A complete, self-contained project — built from scratch in Python with no
external assembler or emulator:

| Part | What |
|------|------|
| **`asm/asm8070.py`** | A two-pass **INS8070 assembler** (handles the chip's off-by-one PC, `0xFF00`-page direct addressing, etc.) |
| **`sim/ins8070.py`** | A **cycle-accurate INS8070 simulator** with a virtual DAC + keypad. Validated by running the real MasterLab monitor ROM. |
| **`sim/render.py`** | An **X-Y oscilloscope renderer** — models the analog beam (sub-pixel, intensity ∝ dwell) → PNG/GIF. |
| **`asm/*.asm`** | The demos: cube (ortho / perspective / interactive), torus, sphere. |
| **`tools/gen_obj.py`** | Procedurally generates the torus & sphere meshes → ready-to-assemble `.asm`. |
| **`tools/make_ram.py`** | Exports an assembled binary to PicoRAM `.RAM` format (load from SD card). |
| **`hw/DAC.md`** | Schematic, BOM, and wiring for the **R-2R DAC** that hangs off the expansion bus. |
| **`ram/`** | Pre-built `.RAM` files — drop on an SD card and run. |

## The programs

| `.RAM` | Object | Projection | Interactive | Refresh |
|--------|--------|-----------|-------------|---------|
| `ram/CUBE.RAM` | cube | orthographic | – | ~25 Hz |
| `ram/CUBE_PERSP.RAM` | cube | perspective | – | ~20 Hz |
| `ram/CUBE_KEY.RAM` | cube | perspective | **yes** | ~19 Hz |
| `ram/TORUS.RAM` | torus | orthographic | **yes** | ~9.6 Hz |
| `ram/SPHERE.RAM` | sphere | orthographic | **yes** | ~13 Hz |

Interactive controls (MasterLab green hex keys): **4/6** yaw, **2/8** pitch,
**5** freeze, **0** reset. Control is velocity-based — nudge it and it keeps
spinning on its own.

<p align="center">
  <img src="media/cube.png" width="32%" alt="cube"/>
  <img src="media/torus.png" width="32%" alt="torus"/>
  <img src="media/sphere.png" width="32%" alt="sphere"/>
</p>

## How it works

**Each frame** the CPU rotates the object's vertices about two axes, projects
them to 2-D, and streams the result to the DAC:

- **Fixed-point rotation** using the INS8070's *unsigned* hardware `MPY` (16×16→32,
  37 cycles) with sign handled by hand, and a 64-entry ×64 sine table. The cube's
  perspective version uses the hardware `DIV` for the perspective divide.
- **The R-2R DAC is double-buffered** (3× 74HC374): writing X loads a holding
  latch, writing Y commits *both* axes on one clock edge — so the beam jumps
  straight to (x, y) instead of stair-stepping.
- **One continuous stroke.** The wireframe is drawn as a single unbroken path
  (a retrace-minimizing route for the cube; an **Eulerian circuit** of the mesh
  for the torus/sphere, which are 4-regular graphs). That means **no beam jumps
  to blank** — so it looks clean on *digital* scopes too (no Z-axis needed), and
  the curved meshes can be drawn by simply streaming vertices and letting the
  beam connect them.

There are two fun INS8070 gotchas documented in the code: **`A` is the low byte
of `EA`** (so `LD A` silently clobbers a 16-bit result), and the double-buffering
trick above (without it the beam draws L-shaped jogs between points).

## Build & run

Everything is plain Python 3 + ImageMagick (for rendering). No Node, no `asl`.

```bash
# assemble a program
python3 asm/asm8070.py asm/cube_persp.asm -o build/cube.bin -l

# simulate + render an animated GIF of the scope output
python3 - <<'PY'
import sys; sys.path[:0] = ["sim", "asm"]
from asm8070 import Assembler
from ins8070 import INS8070
import render
code = Assembler().assemble(open("asm/cube_persp.asm").read())[1]
cpu = INS8070(); cpu.load(0x1000, code); cpu.reset(pc=0x1000)
cpu.run(max_steps=4_000_000)
render.render_gif(cpu, "cube.gif", fps=20, max_frames=64)
PY

# (re)generate the torus / sphere mesh
python3 tools/gen_obj.py torus  asm/torus.asm
python3 tools/gen_obj.py sphere asm/sphere.asm

# export to a PicoRAM .RAM file for the real machine
python3 tools/make_ram.py build/cube.bin ram/CUBE_PERSP.RAM
```

On real hardware: load a `.RAM` file via
[PicoRAM Ultimate](https://github.com/lambdamikel/picoram-ultimate) (SD card),
build the [DAC](hw/DAC.md), wire it to the expansion bus, connect to a scope in
X-Y mode, and RUN.

## The hardware

A 2-channel 8-bit **R-2R ladder DAC** on the expansion connector — full details,
schematic, and bill of materials in **[`hw/DAC.md`](hw/DAC.md)**. Decode the
`0xE000` block off the bus, latch the data bus on the write strobe, three
74HC374s for double-buffering, two resistor ladders, two op-amp buffers. Powered
from the bus's +5 V.

## A note on scopes

A true **analog CRT** scope is ideal for this — a real electron beam draws
smooth, bright, continuous vectors with phosphor persistence. A modern **digital
storage scope (DSO)** also works (the demos are designed to be DSO-friendly:
single continuous stroke, no blanking required) — set it to **X-Y mode**, CH1=X
CH2=Y, **DC coupling**, **vectors/trace** (not dots), and **persistence on**.
The output is the same analog X/Y either way; the analog scope just looks nicer.

<p align="center"><img src="media/dso_vs_analog.png" width="60%" alt="analog vs DSO rendering"/></p>

## Credits

- The **MasterLab MC6400 emulator** by Thorsten Brehm —
  [ThorstenBr/MasterLab-MC6400](https://github.com/ThorstenBr/MasterLab-MC6400)
  — was the reference for the INS8070 instruction semantics (and a great
  validation oracle). The simulator here is a Python port of that CPU model.
- **PicoRAM Ultimate** — [lambdamikel/picoram-ultimate](https://github.com/lambdamikel/picoram-ultimate)
  — loads these programs into the machine over SD card, and documented the
  expansion-bus pinout.

## License

MIT — see [LICENSE](LICENSE).
