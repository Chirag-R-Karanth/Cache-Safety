#!/usr/bin/env python3
"""Generate deterministic memory-access traces that mimic real kernel patterns.

Produces (committed alongside this script):
  loop_reuse.trace    — small working set iterated in a loop (temporal locality)
  stream_stride.trace — streaming column-stride sweep (compulsory + conflict)

These stand in for benchmark traces until the RISC-V toolchain (Phase 2)
lets us extract traces from compiled programs.
"""
import pathlib

OUT = pathlib.Path(__file__).resolve().parent
LINE = 64


def loop_reuse():
    """4 doubles (32 B) reused for 60 iterations with periodic writes —
    models a hot scalar loop; expect very high hit rate in a 256 B cache."""
    lines = ['# hot loop over 4 lines, 60 iterations']
    for i in range(60):
        for j in range(4):
            lines.append(f'R 0x{j * LINE:x}')
        if i % 10 == 9:
            lines.append(f'W 0x{LINE:x}')  # periodic store to line 1
    return '\n'.join(lines) + '\n'


def stream_stride():
    """Column sweep of a 8x8 matrix of 64 B tiles (row-major machine,
    column-major access): each column step jumps 8 lines, reusing a tile
    every 8 steps only if it stays resident — conflict/compulsory mix."""
    lines = ['# column sweep over 8x8 tile matrix, two passes']
    for _pass in range(2):
        for col in range(8):
            for row in range(8):
                addr = (col * 8 + row) * LINE * 8  # 8 lines per tile-row
                lines.append(f'R 0x{addr:x}')
        lines.append('W 0x0')
    return '\n'.join(lines) + '\n'


def main():
    (OUT / 'loop_reuse.trace').write_text(loop_reuse())
    (OUT / 'stream_stride.trace').write_text(stream_stride())
    print(f'Wrote {OUT / "loop_reuse.trace"} and {OUT / "stream_stride.trace"}')


if __name__ == '__main__':
    main()
