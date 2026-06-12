#!/usr/bin/env python3
"""Render an INS8070 DAC beam-stream (ins8070.INS8070.dac_samples) to an
image, modelling an X-Y oscilloscope in vector mode.

Samples are (cycle, x, y, z), x,y in 0..255.  Between consecutive samples the
CRT beam sweeps a straight analog line (unless Z-blanked: z bit0 set).  We
model the beam faithfully: a fixed amount of light energy per beam *move* is
spread along the segment, so longer (faster) moves are dimmer and points where
the beam dwells are brighter -- the authentic vector-display look.  Sub-pixel
(bilinear) splatting avoids the integer-rasterisation staircase, so even a few
points per edge render as smooth lines, exactly as on real hardware.

Writes a PGM (P5) and shells out to ImageMagick `convert` for PNG/GIF.
"""
import subprocess, os, tempfile, math, array


def _beam_buffer(samples, size, margin, blank_bit, seg_energy, dot_energy):
    buf = array.array('f', [0.0]) * (size * size)
    span = size - 2 * margin

    def fx(x):
        return margin + x * span / 255.0

    def fy(y):
        return margin + (255 - y) * span / 255.0

    def splat(px, py, w):
        ix, iy = int(math.floor(px)), int(math.floor(py))
        dx, dy = px - ix, py - iy
        for (gx, gy, gw) in ((ix, iy, (1 - dx) * (1 - dy)),
                             (ix + 1, iy, dx * (1 - dy)),
                             (ix, iy + 1, (1 - dx) * dy),
                             (ix + 1, iy + 1, dx * dy)):
            if 0 <= gx < size and 0 <= gy < size:
                buf[gy * size + gx] += w * gw

    prev = None
    for (_, x, y, z) in samples:
        px, py = fx(x), fy(y)
        if prev is not None and not (z & blank_bit):
            x0, y0 = prev
            dist = math.hypot(px - x0, py - y0)
            n = max(1, int(dist))
            w = seg_energy / n               # energy/length => dimmer when faster
            for i in range(1, n + 1):
                t = i / n
                splat(x0 + (px - x0) * t, y0 + (py - y0) * t, w)
        splat(px, py, dot_energy)            # dwell glow at each output point
        prev = (px, py)
    return buf


def _tonemap_pgm(buf, size, path, gamma=0.45, scale=None):
    if scale is None:
        s = sorted(buf)
        scale = s[int(len(s) * 0.997)] or max(buf) or 1.0
    out = bytearray(size * size)
    inv = 1.0 / scale
    for i, v in enumerate(buf):
        t = v * inv
        if t > 1.0:
            t = 1.0
        out[i] = int(255 * (t ** gamma))
    with open(path, "wb") as f:
        f.write(b"P5\n%d %d\n255\n" % (size, size))
        f.write(bytes(out))


def render_png(samples, path, size=512, margin=28, blank_bit=0x01,
               seg_energy=1.0, dot_energy=0.5, green=True, gamma=0.45, scale=None):
    buf = _beam_buffer(samples, size, margin, blank_bit, seg_energy, dot_energy)
    with tempfile.NamedTemporaryFile(suffix=".pgm", delete=False) as tf:
        pgm = tf.name
    _tonemap_pgm(buf, size, pgm, gamma=gamma, scale=scale)
    if green:
        subprocess.run(["convert", pgm, "+level-colors", "black,#22ff55",
                        "-blur", "0x0.6", path], check=True)
    else:
        subprocess.run(["convert", pgm, path], check=True)
    os.unlink(pgm)
    return path


def frames_of(cpu):
    marks = [0] + list(cpu.frame_marks) + [len(cpu.dac_samples)]
    segs = []
    for i in range(len(marks) - 1):
        seg = cpu.dac_samples[marks[i]:marks[i + 1]]
        if seg:
            segs.append(seg)
    return segs


def render_gif(cpu, path, size=384, fps=20, max_frames=None, **kw):
    segs = frames_of(cpu)
    if max_frames:
        segs = segs[:max_frames]
    tmpdir = tempfile.mkdtemp()
    frames = []
    # fix a common brightness scale across frames for stable animation
    for i, seg in enumerate(segs):
        fp = os.path.join(tmpdir, "f%04d.png" % i)
        render_png(seg, fp, size=size, **kw)
        frames.append(fp)
    if frames:
        delay = max(2, int(100 / fps))
        subprocess.run(["convert", "-delay", str(delay), "-loop", "0"]
                       + frames + [path], check=True)
    for fp in frames:
        os.unlink(fp)
    os.rmdir(tmpdir)
    return path, len(frames)


if __name__ == "__main__":
    samples = []
    for k in range(1500):
        t = k * 2 * math.pi / 1500
        x = int(127 + 120 * math.sin(3 * t))
        y = int(127 + 120 * math.sin(4 * t + 0.6))
        samples.append((k, x, y, 0))
    render_png(samples, "build/lissajous.png", size=512)
    print("wrote build/lissajous.png")
