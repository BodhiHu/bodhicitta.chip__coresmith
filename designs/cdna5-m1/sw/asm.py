#!/usr/bin/env python3
# Copyright (c) 2026 CDNA5-M1 project.
# SPDX-License-Identifier: MIT
"""CDNA5-M1 assembler.

Encodes the frozen M1 subset (spec/ISA.md) into a little-endian hex image for
the I$ (256 words).  Not binary compatible with gfx-class CDNA5 hardware.

Usage:
  python3 sw/asm.py program.s -o program.hex
  python3 sw/asm.py program.s --verilog > program.vh
"""
from __future__ import annotations

import argparse
import re
import sys

OPCODES = {
    "s_nop": 0x00, "s_mov_b32": 0x01, "s_add_u32": 0x02, "s_sub_u32": 0x03,
    "s_and_b32": 0x04, "s_or_b32": 0x05, "s_xor_b32": 0x06,
    "s_shl_b32": 0x07, "s_shr_b32": 0x08, "s_cmp_lt_u32": 0x09,
    "s_cbranch_scc": 0x0A, "s_branch": 0x0B, "s_endpgm": 0x0C,
    "s_barrier": 0x0D, "s_waitcnt": 0x0E, "s_get_wg_id": 0x0F,
    "s_get_wg_size": 0x10, "s_mov_b64": 0x11, "s_lds_addr": 0x12,
    "s_csr_read": 0x13, "s_tdm_copy": 0x14, "s_wmma": 0x15,
    "s_get_lane_base": 0x16, "s_set_exec": 0x17, "s_softmax": 0x18,
    "v_nop": 0x20, "v_mov_b32": 0x21, "v_add_i32": 0x22, "v_sub_i32": 0x23,
    "v_and_b32": 0x24, "v_or_b32": 0x25, "v_xor_b32": 0x26,
    "v_shl_b32": 0x27, "v_shr_b32": 0x28, "v_mul_i32": 0x29,
    "v_cmp_lt_i32": 0x2A, "v_cndmask": 0x2B, "v_mbcnt_lo_u32": 0x2C,
    "v_dot4_i32_iu8": 0x2D, "v_dot8_i32_iu4": 0x2E,
    "v_cvt_f32_i32": 0x2F, "v_lds_ld": 0x30, "v_lds_st": 0x31,
    "v_mem_ld": 0x32, "v_mem_st": 0x33, "v_add_f16": 0x34,
    "v_mul_f16": 0x35, "v_fma_f16": 0x36, "v_cvt_f16_f32": 0x37,
    "v_lds_ld_idx": 0x38, "v_lds_st_idx": 0x39, "v_readfirstlane_b32": 0x3A,
}

# Instructions whose destination / first operand is a scalar register.
SCALAR_DST = {
    "s_mov_b32", "s_add_u32", "s_sub_u32", "s_and_b32", "s_or_b32",
    "s_xor_b32", "s_shl_b32", "s_shr_b32", "s_get_wg_id", "s_get_wg_size",
    "s_lds_addr", "s_csr_read", "s_get_lane_base", "s_readfirstlane_b32",
}

THREE_SRC = {
    "s_add_u32", "s_sub_u32", "s_and_b32", "s_or_b32", "s_xor_b32",
    "s_shl_b32", "s_shr_b32", "v_add_i32", "v_sub_i32", "v_and_b32",
    "v_or_b32", "v_xor_b32", "v_shl_b32", "v_shr_b32", "v_mul_i32",
    "v_dot4_i32_iu8", "v_dot8_i32_iu4", "v_add_f16", "v_mul_f16",
}

MEM_LD = {"v_lds_ld", "v_lds_ld_idx", "v_mem_ld"}
MEM_ST = {"v_lds_st", "v_lds_st_idx", "v_mem_st"}
DESC = {"s_wmma", "s_tdm_copy", "s_softmax"}


def parse_reg(tok: str) -> tuple[str, int]:
    m = re.fullmatch(r"([sv])(\d+)", tok.strip())
    if not m:
        raise ValueError(f"bad register '{tok}'")
    n = int(m.group(2))
    if m.group(1) == "v" and not 0 <= n < 16:
        raise ValueError("VGPR index must be 0..15")
    if m.group(1) == "s" and not 0 <= n < 32:
        raise ValueError("SGPR index must be 0..31")
    return m.group(1), n


def parse_imm(tok: str) -> int:
    t = tok.strip()
    sign = 1
    if t.startswith("-"):
        sign, t = -1, t[1:]
    return sign * int(t, 0)


class Assembler:
    def __init__(self) -> None:
        self.words: list[int | None] = []
        self.labels: dict[str, int] = {}
        self.fixups: list[tuple[int, str, int]] = []

    def pc(self) -> int:
        return len(self.words)

    def emit(self, w: int) -> None:
        self.words.append(w & 0xFFFFFFFF)

    def assemble(self, text: str) -> list[int]:
        for raw in text.splitlines():
            line = raw.split(";", 1)[0].strip()
            if not line:
                continue
            if line.endswith(":"):
                self.labels[line[:-1].strip()] = self.pc()
                continue
            if line.startswith("."):
                raise ValueError("directives are not supported")
            self.instruction(line)

        for pc, label, kind in self.fixups:
            if label not in self.labels:
                raise ValueError(f"undefined label '{label}'")
            off = self.labels[label] - (pc + 1)
            if not -1024 <= off <= 1023:
                raise ValueError(f"branch offset out of range at pc {pc}")
            if kind == "branch":
                self.words[pc] = ((self.words[pc] or 0) & ~0x7FF) | (off & 0x7FF)
            elif kind == "cbranch":
                self.words[pc] = ((self.words[pc] or 0) & ~0x7FF) | (off & 0x7FF)
        return [w if w is not None else 0 for w in self.words]

    def instruction(self, line: str) -> None:
        parts = re.split(r"[\s,]+", line, maxsplit=1)
        mnem = parts[0].lower()
        if mnem not in OPCODES:
            raise ValueError(f"unknown instruction '{mnem}'")
        ops = []
        if len(parts) > 1:
            ops = [o.strip() for o in re.split(r"\s*,\s*", parts[1]) if o.strip()]
        op = OPCODES[mnem]
        pc = self.pc()

        def enc(dst=0, s0=0, s1=0, s2=0, imm=False, flags=0) -> int:
            return (((op & 0x3F) << 26) | ((1 if imm else 0) << 25) |
                    ((dst & 0x1F) << 20) | ((s0 & 0x1F) << 15) |
                    ((s1 & 0x1F) << 10) | ((s2 & 0x1F) << 5) | (flags & 0x1F))

        if mnem in ("s_nop", "s_endpgm", "s_barrier", "v_nop", "s_waitcnt"):
            self.emit(enc())
            return

        if mnem in ("s_branch", "s_cbranch_scc"):
            label = ops[0]
            self.emit(enc())
            self.fixups.append((pc, label, "branch"))
            return

        if mnem in DESC:
            base = parse_reg(ops[0])[1]
            self.emit(enc(dst=base))
            return

        if mnem in MEM_LD:
            dst = parse_reg(ops[0])[1]
            base = parse_reg(ops[1])[1]
            self.emit(enc(dst=dst, s0=base))
            return

        if mnem in MEM_ST:
            base = parse_reg(ops[0])[1]
            src = parse_reg(ops[1])[1]
            self.emit(enc(s0=base, s1=src))
            return

        if mnem in ("v_mbcnt_lo_u32", "v_readfirstlane_b32", "v_cvt_f32_i32"):
            dst = parse_reg(ops[0])[1]
            s0 = parse_reg(ops[1])[1] if len(ops) > 1 and re.fullmatch(r"[sv]\d+", ops[1].strip()) else 0
            self.emit(enc(dst=dst, s0=s0))
            return

        if mnem == "v_cmp_lt_i32":
            dst = parse_reg(ops[0])[1]
            s0 = parse_reg(ops[1])[1]
            s1 = parse_reg(ops[2])[1]
            self.emit(enc(dst=dst, s0=s0, s1=s1))
            return

        if mnem == "v_cndmask":
            dst = parse_reg(ops[0])[1]
            s0 = parse_reg(ops[1])[1]
            s1 = parse_reg(ops[2])[1]
            s2 = parse_reg(ops[3])[1]
            self.emit(enc(dst=dst, s0=s0, s1=s1, s2=s2))
            return

        if mnem == "s_cmp_lt_u32":
            s0 = parse_reg(ops[0])[1]
            if re.fullmatch(r"[sv]\d+", ops[1].strip()):
                s1 = parse_reg(ops[1])[1]
                self.emit(enc(s0=s0, s1=s1))
            else:
                self.emit(enc(s0=s0, imm=True))
                self.emit(parse_imm(ops[1]))
            return

        if mnem in THREE_SRC:
            dst = parse_reg(ops[0])[1]
            s0 = parse_reg(ops[1])[1]
            if len(ops) > 2 and re.fullmatch(r"[sv]\d+", ops[2].strip()):
                s1 = parse_reg(ops[2])[1]
                self.emit(enc(dst=dst, s0=s0, s1=s1))
            else:
                self.emit(enc(dst=dst, s0=s0, imm=True))
                self.emit(parse_imm(ops[2]))
            return

        if mnem in ("s_mov_b32", "v_mov_b32", "s_set_exec"):
            dst = parse_reg(ops[0])[1]
            src = ops[1]
            if re.fullmatch(r"[sv]\d+", src.strip()):
                s1 = parse_reg(src)[1]
                self.emit(enc(dst=dst, s1=s1))
            else:
                self.emit(enc(dst=dst, imm=True))
                self.emit(parse_imm(src))
            return

        if mnem in ("s_get_wg_id", "s_get_wg_size", "s_get_lane_base"):
            dst = parse_reg(ops[0])[1]
            self.emit(enc(dst=dst))
            return

        raise ValueError(f"unhandled instruction '{mnem}'")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("-o", "--out")
    ap.add_argument("--verilog", action="store_true")
    args = ap.parse_args()

    text = open(args.source).read()
    words = Assembler().assemble(text)
    if len(words) > 256:
        raise SystemExit(f"program too large: {len(words)} > 256 words")
    words += [0] * (256 - len(words))

    if args.verilog:
        print("// generated by sw/asm.py")
        for i, w in enumerate(words):
            print(f"  mem[{i}] = 32'h{w:08x};")
    elif args.out:
        with open(args.out, "w") as f:
            for w in words:
                f.write(f"{w:08x}\n")
    else:
        for w in words:
            print(f"{w:08x}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
