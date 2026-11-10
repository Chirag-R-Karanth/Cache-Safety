#!/usr/bin/env python3
"""Convert a raw binary image to $readmemh word-hex (one word per line)."""
import sys


def main():
    if len(sys.argv) != 3:
        print('usage: bin2hex.py in.bin out.hex', file=sys.stderr)
        return 2
    data = open(sys.argv[1], 'rb').read()
    # pad to word boundary
    if len(data) % 4:
        data += b'\x00' * (4 - len(data) % 4)
    with open(sys.argv[2], 'w') as out:
        for i in range(0, len(data), 4):
            word = int.from_bytes(data[i:i + 4], 'little')
            out.write(f'{word:08x}\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
