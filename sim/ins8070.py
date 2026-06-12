#!/usr/bin/env python3
"""INS8070 (SC/MP III) simulator for the Philips MC6400 MasterLab.

Semantics ported faithfully from Thorsten Brehm's emulator (ins8070.js,
MIT) plus the National 70-series instruction-set summary.  Used to develop
and validate INS8070 machine code (e.g. the XY-scope cube) before running it
on real MC6400 hardware via PicoRAM.

Key MC6400 facts modelled here:
  ROM  0x0000-0x0FFF, RAM 0x1000-0x13FF, on-board I/O 0xFD00-0xFDFF,
  INS8070 internal 64-byte RAM 0xFFC0-0xFFFF (fast: no external cycle).
  CPU clock 1 MHz -> 1 cycle ~= 1 us.

Our add-on DAC (not present on stock hardware) is decoded on the expansion
bus.  By default: write 0xE000 -> X channel, 0xE001 -> Y, 0xE002 -> Z/blank.
Every DAC write appends a (cycle, x, y, z) sample to self.dac_samples so the
beam path can be rendered.
"""

def w16(v):
    return v & 0xFFFF

def w8(v):
    return v & 0xFF

def s8(v):
    """interpret byte as signed -128..127"""
    v &= 0xFF
    return v - 256 if v >= 0x80 else v


# S-register bit masks (per emulator / MC6400 manual)
S_IE = 0x01
S_F1 = 0x02
S_F2 = 0x04
S_F3 = 0x08
S_SA = 0x10
S_SB = 0x20
S_OV = 0x40
S_CY = 0x80


class INS8070:
    def __init__(self, dac_base=0xE000, dac_span=0x10):
        self.mem = bytearray(0x10000)
        self.EA = 0
        self.T = 0
        self.S = 0
        self.PC = 1
        self.SP = 0
        self.P2 = 0
        self.P3 = 0
        self.cycles = 0
        self.halted = False
        self._post = None          # pending auto-index post-increment (reg, ofs)
        # DAC
        self.dac_base = dac_base
        self.dac_hi = dac_base + dac_span - 1
        self.dac_x = 0
        self.dac_y = 0
        self.dac_z = 0
        self.dac_samples = []      # list of (cycle, x, y, z)
        self.frame_marks = []      # sample-index boundaries (write to dac_base+3)
        # keypad: set of pressed hex key codes 0..15 (green alphanumeric keys)
        self.keys = set()
        # on-board I/O capture (for ROM validation)
        self.io_matrix = 0
        self.io_writes = []        # (cycle, addr, value)
        self.io_log = False
        self.warn = []
        # tracing / safety
        self.illegal = None

    # ---- register helpers ----
    def A(self):
        return self.EA & 0xFF

    def E(self):
        return (self.EA >> 8) & 0xFF

    def set_A(self, v):
        self.EA = (self.EA & 0xFF00) | (v & 0xFF)

    def set_E(self, v):
        self.EA = (self.EA & 0x00FF) | ((v & 0xFF) << 8)

    def set_S(self, v):
        # SA/SB (bits 4,5) are read-only sense inputs; OV (bit6) not writable
        self.S = (self.S & 0x30) | (v & 0xBF)

    def set_CY(self, on):
        self.S = (self.S | S_CY) if on else (self.S & ~S_CY & 0xFF)

    # ---- memory access (with cycle accounting + I/O hooks) ----
    def _is_ram(self, a):
        return a >= 0xFFC0 or (0x1000 <= a <= 0x13FF)

    def mr8(self, adr, count=True):
        adr = w16(adr)
        if adr >= 0xFFC0:
            return self.mem[adr]            # internal RAM, no penalty
        if count:
            self.cycles += 1
        if adr <= 0x13FF:                   # ROM(0x0-0xFFF)+RAM(0x1000-0x13FF)
            return self.mem[adr]
        if 0xFD00 <= adr <= 0xFDFF:
            return self._io_read(adr)
        if self.dac_base <= adr <= self.dac_hi:
            return 0xFF                      # write-only DAC -> floats high
        return self.mem[adr]

    def mri8(self, adr, count=True):
        return s8(self.mr8(adr, count))

    def mr16(self, adr, count=True):
        adr = w16(adr)
        if adr < 0xFFC0 and count:
            self.cycles += 2
        return self.mem[adr] | (self.mem[w16(adr + 1)] << 8)

    def mw8(self, adr, v, count=True):
        adr = w16(adr)
        v &= 0xFF
        if adr < 0xFFC0 and count:
            self.cycles += 1
        if self.dac_base <= adr <= self.dac_hi:
            self._dac_write(adr, v)
            return
        if 0xFD00 <= adr <= 0xFDFF:
            self._io_write(adr, v)
            return
        if adr >= 0xFFC0 or (0x1000 <= adr <= 0x13FF):
            self.mem[adr] = v
            return
        if adr <= 0x0FFF:
            self.warn.append((self.cycles, "write to ROM", adr, v))
            return
        self.warn.append((self.cycles, "write to unmapped", adr, v))

    def mw16(self, adr, v, count=True):
        self.mw8(adr, v & 0xFF, count)
        self.mw8(w16(adr + 1), (v >> 8) & 0xFF, count)

    # ---- DAC / I/O hooks ----
    def _dac_write(self, adr, v):
        # Hardware model: double-buffered DAC.  Write X (off 0) loads an X
        # holding latch (beam does NOT move).  Write Y (off 1) clocks BOTH the
        # X-output and Y-output latches simultaneously -> the beam jumps
        # straight to (X,Y) (one sample committed).  Z (off 2) is the blank
        # line (no beam move).  off 3 = end-of-frame marker.
        off = adr - self.dac_base
        if off == 0:
            self.dac_x = v
        elif off == 1:
            self.dac_y = v
            self.dac_samples.append((self.cycles, self.dac_x, self.dac_y, self.dac_z))
        elif off == 2:
            self.dac_z = v
        elif off == 3:
            self.frame_marks.append(len(self.dac_samples))

    def _io_write(self, adr, v):
        if (adr & 0xFFF0) == 0xFD00:
            self.io_matrix = v
        self.io_writes.append((self.cycles, adr, v))
        if self.io_log:
            print(f"IO W {adr:04X}={v:02X} (cyc {self.cycles})")

    def _io_read(self, adr):
        # keypad matrix: for the row selected by io_matrix, return inverted
        # button state (bit0: key=row [0-7], bit1: key=row+8 [8-F]); 0xFF=none.
        if (adr & 0xFFF0) == 0xFD00:
            for row in range(8):
                if self.io_matrix & (1 << row):
                    v = 0
                    for k in self.keys:
                        if (k & 7) == row:
                            v |= 1 if k < 8 else 2
                    return v ^ 0xFF
        return 0xFF

    # ---- program loading ----
    def load(self, addr, data):
        for i, b in enumerate(data):
            self.mem[w16(addr + i)] = b & 0xFF

    def reset(self, pc=1):
        self.PC = pc
        self.S = 0
        self.SP = 0
        self.cycles = 0
        self.halted = False

    # ---- ALU (carry=bit7, overflow=bit6 of S) ----
    def _add8(self, a, b):
        a &= 0xFF; b &= 0xFF
        r = a + b
        self.set_CY(r >= 0x100)
        ov = ((a & 0x7F) + (b & 0x7F)) & 0x80
        self.S = (self.S | S_OV) if (bool(r >= 0x100) != bool(ov)) else (self.S & ~S_OV & 0xFF)
        return r & 0xFF

    def _add16(self, a, b):
        a &= 0xFFFF; b &= 0xFFFF
        r = a + b
        self.set_CY(r >= 0x10000)
        ov = ((a & 0x7FFF) + (b & 0x7FFF)) & 0x8000
        self.S = (self.S | S_OV) if (bool(r >= 0x10000) != bool(ov)) else (self.S & ~S_OV & 0xFF)
        return r & 0xFFFF

    def _sub8(self, a, b):
        a &= 0xFF; b &= 0xFF
        r = 0x100 + a - b
        self.set_CY(r >= 0x100)
        return r & 0xFF

    def _sub16(self, a, b):
        a &= 0xFFFF; b &= 0xFFFF
        r = 0x10000 + a - b
        self.set_CY(r >= 0x10000)
        return r & 0xFFFF

    # ---- operand resolution for the regular 0x80-0xFF block ----
    # mode: 0=PCrel 1=SPrel 2=P2rel 3=P3rel 4=immediate 5=direct 6=@P2 7=@P3
    def _addr(self, mode):
        """effective address for memory modes; advances PC over the operand
        byte; performs auto-index pre-decrement and records post-increment."""
        self._post = None
        if mode in (0, 1, 2, 3):
            self.PC = w16(self.PC + 1)
            disp = self.mri8(self.PC)
            base = (self.PC, self.SP, self.P2, self.P3)[mode]
            return w16(base + disp)
        if mode == 5:                       # direct -> 0xFF00 | byte
            self.PC = w16(self.PC + 1)
            return 0xFF00 | self.mr8(self.PC)
        if mode in (6, 7):                  # auto-indexed
            self.PC = w16(self.PC + 1)
            ofs = self.mri8(self.PC)
            reg = 'P2' if mode == 6 else 'P3'
            p = getattr(self, reg)
            if ofs < 0:
                p = w16(p + ofs)
                setattr(self, reg, p)
            ea = p
            if ofs > 0:
                self._post = (reg, ofs)
            return ea
        raise ValueError("bad addr mode %d" % mode)

    def _finish_ai(self):
        if self._post:
            reg, ofs = self._post
            setattr(self, reg, w16(getattr(self, reg) + ofs))
            self._post = None

    def _value(self, mode, width):
        """operand value for read ops; width 1 or 2 bytes."""
        if mode == 4:                       # immediate
            self.PC = w16(self.PC + 1)
            if width == 1:
                return self.mr8(self.PC)
            v = self.mr16(self.PC)
            self.PC = w16(self.PC + 1)
            return v
        ea = self._addr(mode)
        v = self.mr8(ea) if width == 1 else self.mr16(ea)
        self._finish_ai()
        return v

    # base cycle costs (datasheet column; access penalties added by mr/mw)
    @staticmethod
    def _base_cyc(family, variant, mode):
        if family in (0x8, 0xA, 0xB):       # 16-bit EA/T ops
            if mode == 4:
                return 8 if family in (0x8, 0xA) else 10  # LD EA/T imm=8, ADD/SUB EA imm=10
            return 11 if mode in (6, 7) else 10
        if family == 0x9:                   # ILD/DLD
            return 9 if mode in (6, 7) else 8
        # 8-bit A ops (C,D,E,F)
        if mode == 4:
            return 5 if (family == 0xC and variant == 0) else 7   # LD A imm=5
        return 8 if mode in (6, 7) else 7

    def _do_regular(self, op):
        family = op >> 4
        low = op & 0x0F
        mode = low & 0x07
        variant = (low >> 3) & 1
        self.cycles += self._base_cyc(family, variant, mode)
        if family == 0xC:
            if variant == 0:                # LD A
                self.set_A(self._value(mode, 1))
            else:                           # ST A
                ea = self._addr(mode); self.mw8(ea, self.A()); self._finish_ai()
        elif family == 0x8:
            if variant == 0:                # LD EA
                self.EA = self._value(mode, 2)
            else:                           # ST EA
                ea = self._addr(mode); self.mw16(ea, self.EA); self._finish_ai()
        elif family == 0xA:                 # LD T (variant 0 only)
            self.T = self._value(mode, 2)
        elif family == 0xB:
            if variant == 0:                # ADD EA
                self.EA = self._add16(self.EA, self._value(mode, 2))
            else:                           # SUB EA
                self.EA = self._sub16(self.EA, self._value(mode, 2))
        elif family == 0xD:
            if variant == 0:                # AND A
                self.set_A(self.A() & self._value(mode, 1))
            else:                           # OR A
                self.set_A(self.A() | self._value(mode, 1))
        elif family == 0xE:                 # XOR A (variant 0 only)
            self.set_A(self.A() ^ self._value(mode, 1))
        elif family == 0xF:
            if variant == 0:                # ADD A
                self.set_A(self._add8(self.A(), self._value(mode, 1)))
            else:                           # SUB A
                self.set_A(self._sub8(self.A(), self._value(mode, 1)))
        elif family == 0x9:                 # ILD/DLD A
            ea = self._addr(mode)
            v = w8(self.mr8(ea) + (1 if variant == 0 else -1))
            self.mw8(ea, v); self.set_A(v); self._finish_ai()
        else:
            self._illegal(op)

    # ---- branch helper (mirrors emulator opBRANCH) ----
    def _branch(self, cond, base):
        self.PC = w16(self.PC + 1)
        if cond:
            self.PC = w16(base + self.mri8(self.PC))
        self.cycles += 5

    def _illegal(self, op):
        self.illegal = (self.PC, op)
        self.halted = True

    # ---- single step ----
    def step(self):
        if self.halted:
            return
        op = self.mem[self.PC]
        self.cycles += 1                    # instruction fetch

        if op >= 0x80:
            self._do_regular(op)
        elif op == 0x00:                    # NOP
            self.cycles += 3
        elif op == 0x01:                    # XCH A,E
            self.EA = ((self.EA >> 8) | (self.EA << 8)) & 0xFFFF
            self.cycles += 5
        elif op == 0x06:                    # LD A,S
            self.set_A(self.S); self.cycles += 3
        elif op == 0x07:                    # LD S,A
            self.set_S(self.A()); self.cycles += 3
        elif op == 0x08:                    # PUSH EA
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.EA); self.cycles += 8
        elif op == 0x09:                    # LD T,EA
            self.T = self.EA; self.cycles += 4
        elif op == 0x0A:                    # PUSH A
            self.SP = w16(self.SP - 1); self.mw8(self.SP, self.A()); self.cycles += 5
        elif op == 0x0B:                    # LD EA,T
            self.EA = self.T; self.cycles += 4
        elif op == 0x0C:                    # SR EA
            self.EA = (self.EA >> 1) & 0xFFFF; self.cycles += 4
        elif op == 0x0D:                    # DIV EA,T (unsigned)
            if self.T != 0:
                q = self.EA // self.T; r = self.EA % self.T
                self.EA = w16(q); self.T = w16(r)
            self.cycles += 41
        elif op == 0x0E:                    # SL A
            self.set_A((self.A() << 1) & 0xFF); self.cycles += 3
        elif op == 0x0F:                    # SL EA
            self.EA = (self.EA << 1) & 0xFFFF; self.cycles += 4
        elif 0x10 <= op <= 0x1F:            # CALL 0..15  -> vector at 0x20+2n
            n = op - 0x10
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.PC)
            self.PC = self.mr16(0x20 + 2 * n); self.cycles += 17
        elif op == 0x20:                    # JSR XXYY
            self.SP = w16(self.SP - 2); self.mw16(self.SP, w16(self.PC + 2))
            self.PC = self.mr16(w16(self.PC + 1)); self.cycles += 16
        elif op == 0x22:                    # PLI P2,=XXYY
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.P2)
            self.P2 = self.mr16(w16(self.PC + 1)); self.PC = w16(self.PC + 2); self.cycles += 15
        elif op == 0x23:                    # PLI P3,=XXYY
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.P3)
            self.P3 = self.mr16(w16(self.PC + 1)); self.PC = w16(self.PC + 2); self.cycles += 15
        elif op == 0x24:                    # JMP XXYY
            self.PC = self.mr16(w16(self.PC + 1)); self.cycles += 9
        elif op == 0x25:                    # LD SP,=XXYY
            self.SP = self.mr16(w16(self.PC + 1)); self.PC = w16(self.PC + 2); self.cycles += 8
        elif op == 0x26:                    # LD P2,=XXYY
            self.P2 = self.mr16(w16(self.PC + 1)); self.PC = w16(self.PC + 2); self.cycles += 8
        elif op == 0x27:                    # LD P3,=XXYY
            self.P3 = self.mr16(w16(self.PC + 1)); self.PC = w16(self.PC + 2); self.cycles += 8
        elif op == 0x2C:                    # MPY EA,T (unsigned 16x16->32)
            m = self.EA * self.T
            self.EA = (m >> 16) & 0xFFFF; self.T = m & 0xFFFF; self.cycles += 37
        elif op == 0x2D:                    # BND XX (branch if A not a digit)
            a = self.A(); self._branch(a < 0x30 or a > 0x39, w16(self.PC + 1))
        elif op == 0x2E:                    # SSM P2
            self.P2 = self._ssm(self.P2)
        elif op == 0x2F:                    # SSM P3
            self.P3 = self._ssm(self.P3)
        elif op == 0x30:                    # LD EA,PC
            self.EA = self.PC; self.cycles += 4
        elif op == 0x31:                    # LD EA,SP
            self.EA = self.SP; self.cycles += 4
        elif op == 0x32:                    # LD EA,P2
            self.EA = self.P2; self.cycles += 4
        elif op == 0x33:                    # LD EA,P3
            self.EA = self.P3; self.cycles += 4
        elif op == 0x38:                    # POP A
            self.set_A(self.mr8(self.SP)); self.SP = w16(self.SP + 1); self.cycles += 6
        elif op == 0x39:                    # AND S,=XX
            self.PC = w16(self.PC + 1); self.set_S(self.S & self.mr8(self.PC)); self.cycles += 5
        elif op == 0x3A:                    # POP EA
            self.EA = self.mr16(self.SP); self.SP = w16(self.SP + 2); self.cycles += 9
        elif op == 0x3B:                    # OR S,=XX
            self.PC = w16(self.PC + 1); self.set_S(self.S | self.mr8(self.PC)); self.cycles += 5
        elif op == 0x3C:                    # SR A
            self.set_A(self.A() >> 1); self.cycles += 3
        elif op == 0x3D:                    # SRL A (shift right through link)
            self.set_A((self.A() >> 1) | (0x80 if (self.S & S_CY) else 0)); self.cycles += 3
        elif op == 0x3E:                    # RR A
            a = self.A(); self.set_A((a >> 1) | ((a & 1) << 7)); self.cycles += 3
        elif op == 0x3F:                    # RRL A (rotate right through link)
            a = self.A(); link = a & 1
            self.set_A((a >> 1) | (0x80 if (self.S & S_CY) else 0)); self.set_CY(link); self.cycles += 3
        elif op == 0x40:                    # LD A,E
            self.set_A(self.E()); self.cycles += 4
        elif op == 0x44:                    # LD PC,EA
            self.PC = self.EA; self.cycles += 5
        elif op == 0x45:                    # LD SP,EA
            self.SP = self.EA; self.cycles += 5
        elif op == 0x46:                    # LD P2,EA
            self.P2 = self.EA; self.cycles += 5
        elif op == 0x47:                    # LD P3,EA
            self.P3 = self.EA; self.cycles += 5
        elif op == 0x48:                    # LD E,A
            self.set_E(self.A()); self.cycles += 4
        elif op == 0x4C:                    # XCH PC,EA
            self.PC, self.EA = self.EA, self.PC; self.cycles += 7
        elif op == 0x4D:                    # XCH EA,SP
            self.EA, self.SP = self.SP, self.EA; self.cycles += 7
        elif op == 0x4E:                    # XCH EA,P2
            self.EA, self.P2 = self.P2, self.EA; self.cycles += 7
        elif op == 0x4F:                    # XCH EA,P3
            self.EA, self.P3 = self.P3, self.EA; self.cycles += 7
        elif op == 0x50:                    # AND A,E
            self.set_A(self.A() & self.E()); self.cycles += 4
        elif op == 0x54:                    # PUSH PC
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.PC); self.cycles += 8
        elif op == 0x56:                    # PUSH P2
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.P2); self.cycles += 8
        elif op == 0x57:                    # PUSH P3
            self.SP = w16(self.SP - 2); self.mw16(self.SP, self.P3); self.cycles += 8
        elif op == 0x58:                    # OR A,E
            self.set_A(self.A() | self.E()); self.cycles += 4
        elif op == 0x5C:                    # RET
            self.PC = self.mr16(self.SP); self.SP = w16(self.SP + 2); self.cycles += 10
        elif op == 0x5E:                    # POP P2
            self.P2 = self.mr16(self.SP); self.SP = w16(self.SP + 2); self.cycles += 10
        elif op == 0x5F:                    # POP P3
            self.P3 = self.mr16(self.SP); self.SP = w16(self.SP + 2); self.cycles += 10
        elif op == 0x60:                    # XOR A,E
            self.set_A(self.A() ^ self.E()); self.cycles += 4
        elif op == 0x64:                    # BP XX (A>0, i.e. bit7 clear)
            self._branch((self.A() & 0x80) == 0, w16(self.PC + 1))
        elif op == 0x66:                    # BP XX,P2
            self._branch((self.A() & 0x80) == 0, self.P2)
        elif op == 0x67:                    # BP XX,P3
            self._branch((self.A() & 0x80) == 0, self.P3)
        elif op == 0x6C:                    # BZ XX
            self._branch(self.A() == 0, w16(self.PC + 1))
        elif op == 0x6E:                    # BZ XX,P2
            self._branch(self.A() == 0, self.P2)
        elif op == 0x6F:                    # BZ XX,P3
            self._branch(self.A() == 0, self.P3)
        elif op == 0x70:                    # ADD A,E
            self.set_A(self._add8(self.A(), self.E())); self.cycles += 4
        elif op == 0x74:                    # BRA XX
            self._branch(True, w16(self.PC + 1))
        elif op == 0x76:                    # BRA XX,P2
            self._branch(True, self.P2)
        elif op == 0x77:                    # BRA XX,P3
            self._branch(True, self.P3)
        elif op == 0x78:                    # SUB A,E
            self.set_A(self._sub8(self.A(), self.E())); self.cycles += 4
        elif op == 0x7C:                    # BNZ XX
            self._branch(self.A() != 0, w16(self.PC + 1))
        elif op == 0x7E:                    # BNZ XX,P2
            self._branch(self.A() != 0, self.P2)
        elif op == 0x7F:                    # BNZ XX,P3
            self._branch(self.A() != 0, self.P3)
        else:
            self._illegal(op)

        self.PC = w16(self.PC + 1)          # trailing increment (the "off-by-one")

    def _ssm(self, address):
        a = self.A()
        self.cycles += 3
        for _ in range(256):
            self.cycles += 2
            if self.mr8(address) == a:
                self.PC = w16(self.PC + 2)
                return address
            address = w16(address + 1)
        return address

    def run(self, max_steps=10_000_000, until_cycle=None, stop_pc=None):
        n = 0
        while not self.halted and n < max_steps:
            if until_cycle is not None and self.cycles >= until_cycle:
                break
            if stop_pc is not None and self.PC == stop_pc:
                break
            self.step()
            n += 1
        return n


if __name__ == "__main__":
    import sys
    cpu = INS8070()
    if len(sys.argv) > 1:
        with open(sys.argv[1], "rb") as f:
            cpu.load(0x0000, f.read())
    cpu.reset()
    cpu.run(max_steps=200000)
    print("cycles", cpu.cycles, "PC", hex(cpu.PC), "illegal", cpu.illegal)
    print("io_writes", len(cpu.io_writes), "dac", len(cpu.dac_samples))
