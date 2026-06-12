#!/usr/bin/env python3
"""Reference model of the exact fixed-point cube math the INS8070 asm will do.

 * sine table S[i] = round(64*sin(2*pi*i/64)), i=0..63, signed bytes (-64..64)
 * angles ax,ay are 0..63 indices; cos(t)=S[(t+16)&63], sin(t)=S[t&63]
 * mf(a,s) = trunc(|a|*|s| / 64) with sign(a)^sign(s)   (matches abs-MPY+SR6+sign)
 * rotate about Y(beta=ay) then X(alpha=ax); orthographic projection:
       x1 = mf(vx,cosB) + mf(vz,sinB)
       z1 = mf(vz,cosB) - mf(vx,sinB)
       y2 = mf(vy,cosA) - mf(z1,sinA)
       sx = x1+128 ; sy = y2+128
This is the oracle: the asm must reproduce sx,sy exactly.
"""
import math

C = 50  # cube half-size

# vertices: bit0=x, bit1=y, bit2=z (0->-C, 1->+C)
VERTS = []
for i in range(8):
    vx = C if (i & 1) else -C
    vy = C if (i & 2) else -C
    vz = C if (i & 4) else -C
    VERTS.append((vx, vy, vz))

# 12 edges (vertex index pairs), ordered to chain where possible
EDGES = [(0, 1), (1, 3), (3, 2), (2, 0),          # bottom face (z-)
         (0, 4), (4, 5), (5, 7), (7, 6), (6, 4),   # to top + top face (z+)
         (5, 1), (3, 7), (2, 6)]                    # remaining verticals
# (note: indices use bit0=x,bit1=y,bit2=z; faces are z=const)

SINE = [round(64 * math.sin(2 * math.pi * i / 64)) for i in range(64)]


def mf(a, s):
    # signed product / 64, floored (matches optimized asm MULFIX:
    # sign-extend + unsigned MPY -> signed low16, then arithmetic >>6)
    return (a * s) >> 6


def project(ax, ay):
    cB = SINE[(ay + 16) & 63]; sB = SINE[ay & 63]
    cA = SINE[(ax + 16) & 63]; sA = SINE[ax & 63]
    out = []
    for (vx, vy, vz) in VERTS:
        x1 = mf(vx, cB) + mf(vz, sB)
        z1 = mf(vz, cB) - mf(vx, sB)
        # z1 fits in a signed byte (|z1| < 128); asm passes its low byte
        if z1 < -128 or z1 > 127:
            z1 = max(-128, min(127, z1))
        y2 = mf(vy, cA) - mf(z1, sA)
        out.append(((x1 + 128) & 0xFF, (y2 + 128) & 0xFF))
    return out


def sdiv(n, d):
    q = abs(n) // d
    return -q if n < 0 else q


def project_persp(ax, ay, F=256):
    """perspective: screen = (rotated_xy * 256) / (z2 + F).  Matches the asm:
    same truncating mf(), z1 clamped to a byte, signed truncating divide."""
    cB = SINE[(ay + 16) & 63]; sB = SINE[ay & 63]
    cA = SINE[(ax + 16) & 63]; sA = SINE[ax & 63]
    out = []
    for (vx, vy, vz) in VERTS:
        x1 = mf(vx, cB) + mf(vz, sB)
        z1 = mf(vz, cB) - mf(vx, sB)
        z1 = max(-128, min(127, z1))
        y2 = mf(vy, cA) - mf(z1, sA)
        z2 = mf(vy, sA) + mf(z1, cA)
        zc = z2 + F
        sx = (sdiv(x1 << 8, zc) + 128) & 0xFF
        sy = (sdiv(y2 << 8, zc) + 128) & 0xFF
        out.append((sx, sy))
    return out


def db_bytes(vals):
    return ', '.join('0x%02X' % (v & 0xFF) for v in vals)


if __name__ == "__main__":
    import sys
    ax = int(sys.argv[1]) if len(sys.argv) > 1 else 10
    ay = int(sys.argv[2]) if len(sys.argv) > 2 else 6
    print("; sine table (64 signed bytes, x64)")
    for r in range(0, 64, 16):
        print("        DB    " + db_bytes(SINE[r:r + 16]))
    print()
    print(";  edges (vertex index pairs):", EDGES)
    flat = []
    for a, b in EDGES:
        flat += [a, b]
    print("        DB    " + db_bytes(flat))
    print()
    pc = project(ax, ay)
    print("; projected coords for ax=%d ay=%d :" % (ax, ay), pc)
    flat = []
    for (sx, sy) in pc:
        flat += [sx, sy]
    print("        DB    " + db_bytes(flat))
    # also dump min/max for range sanity
    xs = [p[0] for p in pc]; ys = [p[1] for p in pc]
    print("; x range %d..%d  y range %d..%d" % (min(xs), max(xs), min(ys), max(ys)))
