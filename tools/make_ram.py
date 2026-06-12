#!/usr/bin/env python3
"""Convert an assembled INS8070 binary (origin 0x1000) into a PicoRAM Ultimate
`.RAM` dump for the Philips MC6400 MasterLab, so it can be loaded from SD card.

Format (matches the example dumps in the picoram-ultimate repo):
  * a leading newline, then 128 lines of 16 bytes each = a 2 KB image of
    0x1000..0x17FF (the MASTERLAB RAM region; only the first 1 KB is used),
  * each byte uppercase hex, single-space separated, no trailing space,
  * UNIX line endings (0x0A), no trailing newline after the last line.
"""
import sys

BYTES = 2048      # 0x1000..0x17FF
WIDTH = 16


def to_ram(binary):
    img = bytearray(BYTES)
    n = min(len(binary), BYTES)
    img[:n] = binary[:n]
    lines = []
    for off in range(0, BYTES, WIDTH):
        row = img[off:off + WIDTH]
        lines.append(' '.join('%02X' % b for b in row))
    return ('\n' + '\n'.join(lines)).encode('ascii')


def main():
    if len(sys.argv) < 3:
        print("usage: make_ram.py in.bin out.RAM"); return 1
    data = open(sys.argv[1], 'rb').read()
    if len(data) > BYTES:
        print("warning: %d bytes exceeds %d" % (len(data), BYTES))
    open(sys.argv[2], 'wb').write(to_ram(data))
    print("wrote %s (%d program bytes -> %d byte image)" %
          (sys.argv[2], len(data), BYTES))
    return 0


def parse_ram(text):
    """inverse: .RAM text -> bytes image (for validation)."""
    out = bytearray()
    for line in text.split('\n'):
        line = line.strip()
        if not line:
            continue
        for tok in line.split():
            out.append(int(tok, 16))
    return bytes(out)


if __name__ == '__main__':
    sys.exit(main())
