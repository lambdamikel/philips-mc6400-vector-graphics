#!/usr/bin/env python3
"""A small two-pass assembler for the National INS8070 (Philips MC6400).

Designed to exactly invert the decoding in sim/ins8070.py, including the
INS8070 quirks:
  * JMP/JSR absolute operands are emitted as (target-1)  [PC off-by-one]
  * PCr branch displacement = target-(instruction_end)
  * direct addressing reaches 0xFF00..0xFFFF (emit low byte)

Syntax (case-insensitive mnemonics/registers):
  label:                      define label (also `label EQU expr`)
  ORG expr / EQU / DB .. / DW .. / DS n
  operand forms:
     =expr            immediate         (8 or 16 bit per instruction)
     expr             direct  -> 0xFF00|low(expr)   (group mnemonics)
     expr(PC|SP|P2|P3)  register-relative, expr = signed displacement
     @expr(P2|P3)     auto-indexed (expr<0 pre-dec, expr>0 post-inc)
     E / S / EA / Pn  register operands for the implied moves
  control:
     JMP/JSR expr     BRA/BP/BZ/BNZ/BND label    CALL n   PLI Pn,=expr
Comment: ';' to end of line.
"""
import re, sys

REGS = ('PC', 'SP', 'P2', 'P3')
# mode offsets within a group:  PCr SPr P2r P3r imm dir @P2 @P3
M_PCR, M_SPR, M_P2R, M_P3R, M_IMM, M_DIR, M_AP2, M_AP3 = range(8)

# generic groups: mnemonic -> (base_opcode, operand_width_bytes, has_imm)
GROUPS = {
    'LD A':  (0xC0, 1, True),
    'ST A':  (0xC8, 1, False),
    'ADD A': (0xF0, 1, True),
    'SUB A': (0xF8, 1, True),
    'AND A': (0xD0, 1, True),
    'OR A':  (0xD8, 1, True),
    'XOR A': (0xE0, 1, True),
    'LD EA': (0x80, 2, True),
    'ST EA': (0x88, 2, False),
    'LD T':  (0xA0, 2, True),
    'ADD EA': (0xB0, 2, True),
    'SUB EA': (0xB8, 2, True),
    'ILD A': (0x90, 1, False),
    'DLD A': (0x98, 1, False),
}

# implied / fixed-opcode instructions: "MNEM OPERANDS" -> opcode
IMPLIED = {
    'NOP': 0x00, 'XCH A,E': 0x01,
    'LD A,S': 0x06, 'LD S,A': 0x07, 'LD T,EA': 0x09, 'LD EA,T': 0x0B,
    'LD EA,PC': 0x30, 'LD EA,SP': 0x31, 'LD EA,P2': 0x32, 'LD EA,P3': 0x33,
    'LD A,E': 0x40, 'LD PC,EA': 0x44, 'LD SP,EA': 0x45, 'LD P2,EA': 0x46,
    'LD P3,EA': 0x47, 'LD E,A': 0x48,
    'PUSH EA': 0x08, 'PUSH A': 0x0A, 'PUSH PC': 0x54, 'PUSH P2': 0x56, 'PUSH P3': 0x57,
    'POP A': 0x38, 'POP EA': 0x3A, 'POP P2': 0x5E, 'POP P3': 0x5F, 'RET': 0x5C,
    'SR A': 0x3C, 'SRL A': 0x3D, 'RR A': 0x3E, 'RRL A': 0x3F,
    'SR EA': 0x0C, 'SL A': 0x0E, 'SL EA': 0x0F,
    'XCH PC,EA': 0x4C, 'XCH EA,SP': 0x4D, 'XCH EA,P2': 0x4E, 'XCH EA,P3': 0x4F,
    'ADD A,E': 0x70, 'SUB A,E': 0x78, 'AND A,E': 0x50, 'OR A,E': 0x58, 'XOR A,E': 0x60,
    'MPY EA,T': 0x2C, 'MPY': 0x2C, 'DIV EA,T': 0x0D, 'DIV': 0x0D,
    'SSM P2': 0x2E, 'SSM P3': 0x2F,
}

# 16-bit immediate pointer loads
PTR_IMM = {'LD SP': 0x25, 'LD P2': 0x26, 'LD P3': 0x27}
PLI = {'PLI P2': 0x22, 'PLI P3': 0x23}
# PCr conditional/uncond branches (label form)
BRANCH = {'BRA': 0x74, 'BP': 0x64, 'BZ': 0x6C, 'BNZ': 0x7C, 'BND': 0x2D}
SREG = {'AND S': 0x39, 'OR S': 0x3B}   # AND/OR S,=expr


class AsmError(Exception):
    pass


def _split_operands(s):
    """split on commas at paren depth 0"""
    out, depth, cur = [], 0, ''
    for ch in s:
        if ch == '(':
            depth += 1; cur += ch
        elif ch == ')':
            depth -= 1; cur += ch
        elif ch == ',' and depth == 0:
            out.append(cur.strip()); cur = ''
        else:
            cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


class Assembler:
    def __init__(self):
        self.sym = {}
        self.org = 0x1000
        self.listing = []

    # ---------- expression evaluation ----------
    def eval(self, expr, pc, final):
        expr = expr.strip()
        # normalise number/operator syntax to python
        def repl(m):
            t = m.group(0)
            up = t.upper()
            if up == '$' or up == '*':
                return str(pc)
            if t.startswith('0x') or t.startswith('0X'):
                return str(int(t, 16))
            if up.endswith('H') and re.fullmatch(r'[0-9A-Fa-f]+H', t):
                return str(int(t[:-1], 16))
            if t.startswith('%'):
                return str(int(t[1:], 2))
            if re.fullmatch(r'\d+', t):
                return t
            if re.fullmatch(r"'.'", t):
                return str(ord(t[1]))
            # symbol
            if up in self.sym:
                return str(self.sym[up])
            if final:
                raise AsmError("undefined symbol: %s" % t)
            return '0'
        # tokenizer for the replacer: numbers, hex, symbols, $, *, char-literal
        tokenised = re.sub(r"'.'|0[xX][0-9A-Fa-f]+|%[01]+|[0-9A-Fa-f]+[Hh]\b|\d+|[A-Za-z_.][A-Za-z0-9_.]*|\$|\*", repl, expr)
        # only allow safe characters now
        if not re.fullmatch(r"[0-9()+\-*/%<>&|~ ]*", tokenised.replace('<<', '').replace('>>', '')):
            # allow shifts
            pass
        try:
            return int(eval(tokenised, {"__builtins__": {}}, {})) & 0xFFFFFFFF
        except AsmError:
            raise
        except Exception as e:
            raise AsmError("bad expression %r -> %r (%s)" % (expr, tokenised, e))

    # ---------- operand parsing ----------
    def parse_operand(self, op):
        """return (mode, kind, expr_str) where kind in imm/dir/rel/auto;
        mode is the group mode offset for rel/auto/dir/imm."""
        op = op.strip()
        if op.startswith('='):
            return (M_IMM, 'imm', op[1:].strip())
        m = re.fullmatch(r'@\s*(.*)\(\s*([A-Za-z0-9]+)\s*\)', op)
        if m:
            reg = m.group(2).upper()
            if reg == 'P2':
                return (M_AP2, 'auto', m.group(1).strip())
            if reg == 'P3':
                return (M_AP3, 'auto', m.group(1).strip())
            raise AsmError("auto-index needs P2/P3: %s" % op)
        m = re.fullmatch(r'(.*)\(\s*([A-Za-z0-9]+)\s*\)', op)
        if m:
            reg = m.group(2).upper()
            if reg not in REGS:
                raise AsmError("bad register in %s" % op)
            mode = {'PC': M_PCR, 'SP': M_SPR, 'P2': M_P2R, 'P3': M_P3R}[reg]
            return (mode, 'rel', m.group(1).strip())
        return (M_DIR, 'dir', op)        # bare expr -> direct

    # ---------- length (pass 1) ----------
    def length(self, mnem, ops):
        full = (mnem + ' ' + ','.join(ops)).strip()
        if mnem in ('ORG', 'EQU', 'SET'):
            return 0
        if mnem == 'DS':
            return self.eval(ops[0], 0, True)
        if mnem in ('DB', 'BYTE', 'FCB'):
            return len(ops)
        if mnem in ('DW', 'WORD', 'FDB'):
            return 2 * len(ops)
        if full in IMPLIED:
            return 1
        if mnem == 'CALL':
            return 1
        if mnem in BRANCH:
            return 2
        key2 = (mnem + ' ' + ops[0]) if ops else mnem
        if key2 in PTR_IMM or key2 in PLI:
            return 3
        if key2 in SREG:
            return 2
        if mnem == 'JMP' or mnem == 'JSR':
            return 3
        grp = self._group_key(mnem, ops)
        if grp:
            base, width, has_imm = GROUPS[grp]
            mode, kind, _ = self.parse_operand(ops[-1])
            if kind == 'imm':
                return 1 + width
            return 2
        raise AsmError("unknown instruction: %s" % full)

    def _group_key(self, mnem, ops):
        # the group mnemonic is mnem + register part of first operand for
        # 'LD A'/'LD EA'/'LD T'/'ST A'/'ST EA'/'ILD A'/'DLD A'; arithmetic use mnem+reg
        if not ops:
            return None
        cand = mnem + ' ' + ops[0].upper()
        if cand in GROUPS:
            # second operand is the addressed operand
            return cand
        return None

    # ---------- emit (pass 2) ----------
    def emit(self, mnem, ops, pc):
        full = (mnem + ' ' + ','.join(ops)).strip()
        if full in IMPLIED:
            return [IMPLIED[full]]
        if mnem == 'CALL':
            n = self.eval(ops[0], pc, True)
            if not 0 <= n <= 15:
                raise AsmError("CALL n must be 0..15")
            return [0x10 + n]
        if mnem in BRANCH:
            target = self.eval(ops[0], pc, True)
            disp = target - (pc + 2)
            if not -128 <= disp <= 127:
                raise AsmError("branch out of range (%d) to %04X" % (disp, target))
            return [BRANCH[mnem], disp & 0xFF]
        key2 = (mnem + ' ' + ops[0]) if ops else mnem
        if key2 in PTR_IMM:
            v = self.eval(ops[1][1:], pc, True)   # strip '='
            return [PTR_IMM[key2], v & 0xFF, (v >> 8) & 0xFF]
        if key2 in PLI:
            v = self.eval(ops[1][1:], pc, True)
            return [PLI[key2], v & 0xFF, (v >> 8) & 0xFF]
        if key2 in SREG:
            v = self.eval(ops[1][1:], pc, True)
            return [SREG[key2], v & 0xFF]
        if mnem in ('JMP', 'JSR'):
            v = (self.eval(ops[0], pc, True) - 1) & 0xFFFF   # off-by-one
            op = 0x24 if mnem == 'JMP' else 0x20
            return [op, v & 0xFF, (v >> 8) & 0xFF]
        grp = self._group_key(mnem, ops)
        if grp:
            base, width, has_imm = GROUPS[grp]
            mode, kind, ex = self.parse_operand(ops[-1])
            opcode = base + mode
            if kind == 'imm':
                if not has_imm:
                    raise AsmError("%s has no immediate mode" % grp)
                v = self.eval(ex, pc, True)
                if width == 1:
                    return [opcode, v & 0xFF]
                return [opcode, v & 0xFF, (v >> 8) & 0xFF]
            if kind == 'dir':
                a = self.eval(ex, pc, True)
                low = a & 0xFF
                if a > 0xFF and (a & 0xFF00) != 0xFF00:
                    raise AsmError("direct address %04X not in 0xFF00..0xFFFF" % a)
                return [opcode, low]
            # rel / auto: operand is a signed displacement
            d = self.eval(ex, pc, True)
            d = d - 0x10000 if d > 0x7FFF else d
            if not -128 <= d <= 127:
                raise AsmError("displacement out of range: %d" % d)
            return [opcode, d & 0xFF]
        raise AsmError("cannot emit: %s" % full)

    # ---------- driver ----------
    def parse_line(self, line):
        line = line.split(';', 1)[0].rstrip()
        if not line.strip():
            return (None, None, [])
        label = None
        m = re.match(r'^([A-Za-z_.][A-Za-z0-9_.]*):', line)
        if m:
            label = m.group(1)
            line = line[m.end():]
        elif not line[0].isspace():
            # label without colon, if followed by EQU/SET
            parts = line.split(None, 2)
            if len(parts) >= 2 and parts[1].upper() in ('EQU', 'SET', '='):
                label = parts[0]
                line = ' ' + parts[1] + ' ' + (parts[2] if len(parts) > 2 else '')
        line = line.strip()
        if not line:
            return (label, None, [])
        parts = line.split(None, 1)
        mnem = parts[0].upper()
        rest = parts[1] if len(parts) > 1 else ''
        ops = _split_operands(rest)
        return (label, mnem, ops)

    def assemble(self, text):
        lines = [self.parse_line(l) for l in text.splitlines()]
        # pass 1: symbols + length
        pc = self.org
        for i, (label, mnem, ops) in enumerate(lines):
            if mnem in ('EQU', 'SET', '='):
                self.sym[label.upper()] = self.eval(ops[0], pc, False)
                continue
            if mnem == 'ORG':
                pc = self.eval(ops[0], pc, True)
                self.org = self.org if self.sym else pc  # first ORG sets base
                if label:
                    self.sym[label.upper()] = pc
                continue
            if label:
                self.sym[label.upper()] = pc
            if mnem is None:
                continue
            pc += self.length(mnem, ops)
        # pass 2: emit
        out = bytearray()
        base = None
        pc = self.org
        # find starting ORG
        for (label, mnem, ops) in lines:
            if mnem == 'ORG':
                pc = self.eval(ops[0], pc, True)
                break
        start = pc
        for (label, mnem, ops) in lines:
            if mnem in ('EQU', 'SET', '='):
                continue
            if mnem == 'ORG':
                newpc = self.eval(ops[0], pc, True)
                while pc < newpc:
                    out.append(0); pc += 1
                pc = newpc
                continue
            if mnem is None:
                continue
            if mnem == 'DS':
                n = self.eval(ops[0], pc, True)
                out.extend([0] * n); pc += n; continue
            if mnem in ('DB', 'BYTE', 'FCB'):
                bs = [self.eval(o, pc, True) & 0xFF for o in ops]
                out.extend(bs); pc += len(bs); continue
            if mnem in ('DW', 'WORD', 'FDB'):
                for o in ops:
                    v = self.eval(o, pc, True)
                    out.append(v & 0xFF); out.append((v >> 8) & 0xFF); pc += 2
                continue
            bs = self.emit(mnem, ops, pc)
            self.listing.append((pc, bs, (mnem + ' ' + ', '.join(ops)).strip()))
            out.extend(bs); pc += len(bs)
        return start, bytes(out)


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('input')
    ap.add_argument('-o', '--output')
    ap.add_argument('--org', default=None)
    ap.add_argument('-l', '--listing', action='store_true')
    a = ap.parse_args()
    asm = Assembler()
    if a.org:
        asm.org = int(a.org, 0)
    text = open(a.input).read()
    start, code = asm.assemble(text)
    if a.output:
        open(a.output, 'wb').write(code)
    print("start=0x%04X  length=%d bytes (0x%X..0x%X)" % (start, len(code), start, start + len(code) - 1))
    if a.listing:
        for pc, bs, src in asm.listing:
            print("%04X  %-14s %s" % (pc, ' '.join('%02X' % b for b in bs), src))
    return 0


if __name__ == '__main__':
    sys.exit(main())
