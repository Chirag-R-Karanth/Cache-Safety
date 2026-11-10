#!/usr/bin/env bash
# Build + run the RV32I test suite (directed + randomized) on core5 under
# Icarus. Requires a RISC-V toolchain (default: xpack riscv-none-elf-gcc in
# ~/.local/share/riscv-tc, override with RISCV_TC=...).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="${RISCV_TC:-$HOME/.local/share/riscv-tc}"
CROSS="${TC}/bin/riscv-none-elf-"
BUILD="$ROOT/build/riscv-tests"
RANDOM_SEEDS="${RANDOM_SEEDS:-10}"

if [[ ! -x "${CROSS}gcc" ]]; then
	echo "ERROR: RISC-V toolchain not found at ${CROSS}gcc (set RISCV_TC)" >&2
	exit 2
fi

mkdir -p "$BUILD"
echo "== compiling testbench =="
iverilog -g2012 -o "$BUILD/tb_core.vvp" \
	"$ROOT/rtl/core/core_pkg.sv" \
	"$ROOT/rtl/core/decode_comb.sv" \
	"$ROOT/rtl/core/regfile.sv" \
	"$ROOT/rtl/core/decode.sv" \
	"$ROOT/rtl/core/fetch.sv" \
	"$ROOT/rtl/core/execute.sv" \
	"$ROOT/rtl/core/mem_stage.sv" \
	"$ROOT/rtl/core/writeback.sv" \
	"$ROOT/rtl/core/csr.sv" \
	"$ROOT/rtl/core/core5.sv" \
	"$ROOT/tb/integration/tb_core.sv"

CFLAGS="-march=rv32i_zicsr -mabi=ilp32 -nostdlib -nostartfiles -ffreestanding -O1"

PASS=0
FAIL=0

# expect_value <src-file> — parse "# expect: N" / "expect: N" comment
expect_value() {
	grep -oE 'expect:[[:space:]]*[0-9a-fA-FxX]+' "$1" | head -1 | \
		sed -E 's/expect:[[:space:]]*//' | \
		{ read -r v; printf '%d' "$v"; }
}

# run_hex <name> <hex> <expected>
run_hex() {
	local name="$1" hex="$2" expected="$3" out magic
	out=$(vvp "$BUILD/tb_core.vvp" +HEX="$hex" 2>&1 || true)
	magic=$(printf '%s\n' "$out" | grep -oE 'MAGIC 0x[0-9a-fA-F]+' | \
		head -1 | awk '{print $2}' || true)
	if [[ -z "$magic" ]]; then
		echo "FAIL $name — no MAGIC (tail: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' '))"
		FAIL=$((FAIL + 1))
		return
	fi
	if (( magic == expected )); then
		echo "PASS $name (magic=$magic)"
		PASS=$((PASS + 1))
	else
		echo "FAIL $name magic=$magic expected=$expected"
		FAIL=$((FAIL + 1))
	fi
}

# build_asm <name> <src> [extra objects...]
build_asm() {
	local name="$1" src="$2"; shift 2
	"${CROSS}gcc" $CFLAGS -T "$ROOT/tests/link.ld" \
		-o "$BUILD/$name.elf" "$@" "$src"
	"${CROSS}objcopy" -O binary "$BUILD/$name.elf" "$BUILD/$name.bin"
	python3 "$ROOT/tests/bin2hex.py" "$BUILD/$name.bin" "$BUILD/$name.hex"
}

echo "== directed assembly tests =="
for src in "$ROOT"/tests/asm/*.S; do
	name=$(basename "$src" .S)
	build_asm "$name" "$src"
	expected=$(expect_value "$src")
	run_hex "$name" "$BUILD/$name.hex" "$expected"

	# Cross-check with the ISS (skip tests using CSRs, not modelled there)
	if ! grep -q 'csrr' "$src"; then
		iss=$(python3 "$ROOT/tests/asm/iss.py" "$BUILD/$name.hex" | \
			awk '{print $2}')
		iss_dec=$((iss))
		if (( iss_dec == expected )); then
			echo "  iss cross-check OK ($iss)"
		else
			echo "  FAIL $name iss=$iss expected=$expected"
			FAIL=$((FAIL + 1))
		fi
	fi
done

echo "== C tests =="
for src in "$ROOT"/tests/c/*.c; do
	name=$(basename "$src" .c)
	build_asm "$name" "$src" "$ROOT/tests/start.S"
	expected=$(expect_value "$src")
	run_hex "$name" "$BUILD/$name.hex" "$expected"
done

echo "== randomized tests ($RANDOM_SEEDS seeds) =="
for i in $(seq 1 "$RANDOM_SEEDS"); do
	name="rand_$i"
	python3 "$ROOT/tests/asm/gen_random.py" --seed "$i" --out "$BUILD/$name.S"
	build_asm "$name" "$BUILD/$name.S"
	iss=$(python3 "$ROOT/tests/asm/iss.py" "$BUILD/$name.hex" | awk '{print $2}')
	expected=$((iss))
	run_hex "$name" "$BUILD/$name.hex" "$expected"
done

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
