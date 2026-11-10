#!/usr/bin/env python3
"""Minimal RV32I instruction-set simulator.

Executes a word-hex program image (one 32-bit word per line) against a
separate 16 KiB data memory and returns the value stored to the magic
signature region (0xFFFF0000..0xFFFFFFFF) — the same convention tb_core
uses. Built for validating randomly generated test programs.
"""
import sys

M32 = 0xFFFFFFFF


def sx32(v):
    v &= M32
    return v - (1 << 32) if v & 0x80000000 else v


def imm_i(instr):
    v = instr >> 20
    return v - 0x1000 if v & 0x800 else v


def imm_s(instr):
    v = ((instr >> 25) << 5) | ((instr >> 7) & 0x1F)
    return v - 0x1000 if v & 0x800 else v


def imm_b(instr):
    v = (((instr >> 31) & 1) << 12) | (((instr >> 7) & 1) << 11) | \
        (((instr >> 25) & 0x3F) << 5) | (((instr >> 8) & 0xF) << 1)
    return v - 0x2000 if v & 0x1000 else v


def imm_j(instr):
    v = (((instr >> 31) & 1) << 20) | (((instr >> 12) & 0xFF) << 12) | \
        (((instr >> 20) & 1) << 11) | (((instr >> 21) & 0x3FF) << 1)
    return v - 0x200000 if v & 0x100000 else v


class Iss:
    def __init__(self, hexfile):
        with open(hexfile) as f:
            self.imem = [int(line, 16) for line in f
                         if line.strip() and not line.startswith('//')]
        self.dmem = bytearray(0x4000)
        self.regs = [0] * 32
        self.pc = 0

    def rd(self, i):
        return self.regs[i]

    def wr(self, i, v):
        if i:
            self.regs[i] = v & M32

    def load(self, addr, size, unsigned):
        if addr + size > len(self.dmem):
            raise RuntimeError(f'data load out of range: {addr:#x}')
        v = int.from_bytes(self.dmem[addr:addr + size], 'little')
        if not unsigned and size < 4 and (v >> (size * 8 - 1)):
            v -= 1 << (size * 8)
        return v & M32

    def store(self, addr, size, val):
        if addr + size > len(self.dmem):
            raise RuntimeError(f'data store out of range: {addr:#x}')
        self.dmem[addr:addr + size] = \
            (val & ((1 << (size * 8)) - 1)).to_bytes(size, 'little')

    def run(self, max_steps=500000):
        for _ in range(max_steps):
            idx = self.pc >> 2
            if idx >= len(self.imem):
                raise RuntimeError(f'fetch out of range: pc={self.pc:#x}')
            instr = self.imem[idx] & M32
            op = instr & 0x7F
            rd = (instr >> 7) & 0x1F
            f3 = (instr >> 12) & 7
            rs1 = (instr >> 15) & 0x1F
            rs2 = (instr >> 20) & 0x1F
            f7 = instr >> 25
            npc = self.pc + 4

            if op == 0x37:                                    # LUI
                self.wr(rd, instr & 0xFFFFF000)
            elif op == 0x17:                                  # AUIPC
                self.wr(rd, self.pc + (instr & 0xFFFFF000))
            elif op == 0x6F:                                  # JAL
                self.wr(rd, self.pc + 4)
                npc = self.pc + imm_j(instr)
            elif op == 0x67:                                  # JALR
                assert f3 == 0, f'bad jalr at {self.pc:#x}'
                t = (self.rd(rs1) + imm_i(instr)) & ~1 & M32
                self.wr(rd, self.pc + 4)
                npc = t
            elif op == 0x63:                                  # branches
                a, b = self.rd(rs1), self.rd(rs2)
                sa, sb = sx32(a), sx32(b)
                taken = (a == b, a != b, False, False,
                         sa < sb, sa >= sb, a < b, a >= b)[f3]
                if taken:
                    npc = self.pc + imm_b(instr)
            elif op == 0x03:                                  # loads
                addr = (self.rd(rs1) + imm_i(instr)) & M32
                size = (1, 2, 4, None, 1, 2, None, None)[f3]
                assert size, f'bad load f3={f3} at {self.pc:#x}'
                self.wr(rd, self.load(addr, size, unsigned=f3 >= 4))
            elif op == 0x23:                                  # stores
                addr = (self.rd(rs1) + imm_s(instr)) & M32
                size = (1, 2, 4, None, None, None, None, None)[f3]
                assert size, f'bad store f3={f3} at {self.pc:#x}'
                if addr >> 16 == 0xFFFF:                      # magic signature
                    return self.rd(rs2)
                self.store(addr, size, self.rd(rs2))
            elif op == 0x13:                                  # op-imm
                a = self.rd(rs1)
                sh = rs2  # shamt lives in the rs2 field for shifts
                if f3 == 0:
                    v = a + imm_i(instr)
                elif f3 == 2:
                    v = 1 if sx32(a) < imm_i(instr) else 0
                elif f3 == 3:
                    v = 1 if a < (imm_i(instr) & M32) else 0
                elif f3 == 4:
                    v = a ^ (imm_i(instr) & M32)
                elif f3 == 6:
                    v = a | (imm_i(instr) & M32)
                elif f3 == 7:
                    v = a & (imm_i(instr) & M32)
                elif f3 == 1:
                    assert f7 == 0, f'bad slli at {self.pc:#x}'
                    v = a << sh
                elif f3 == 5:
                    if f7 == 0:
                        v = a >> sh
                    elif f7 == 0x20:
                        v = sx32(a) >> sh
                    else:
                        raise RuntimeError(f'bad srli/srai at {self.pc:#x}')
                self.wr(rd, v)
            elif op == 0x33:                                  # op
                a, b = self.rd(rs1), self.rd(rs2)
                if f3 == 0:
                    v = a - b if f7 == 0x20 else a + b
                elif f3 == 1:
                    v = a << (b & 31)
                elif f3 == 2:
                    v = 1 if sx32(a) < sx32(b) else 0
                elif f3 == 3:
                    v = 1 if a < b else 0
                elif f3 == 4:
                    v = a ^ b
                elif f3 == 5:
                    if f7 == 0:
                        v = a >> (b & 31)
                    elif f7 == 0x20:
                        v = sx32(a) >> (b & 31)
                    else:
                        raise RuntimeError(f'bad srl/sra at {self.pc:#x}')
                elif f3 == 6:
                    v = a | b
                else:
                    v = a & b
                if f7 not in (0, 0x20) or (f7 == 0x20 and f3 not in (0, 5)):
                    raise RuntimeError(f'bad f7={f7:#x} at {self.pc:#x}')
                self.wr(rd, v)
            else:
                raise RuntimeError(f'illegal opcode {op:#x} at {self.pc:#x}')
            self.pc = npc
        raise RuntimeError('max steps exceeded (missing magic store?)')


def main():
    if len(sys.argv) != 2:
        print('usage: iss.py program.hex', file=sys.stderr)
        return 2
    result = Iss(sys.argv[1]).run()
    print(f'ISS_RESULT 0x{result:08x}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
