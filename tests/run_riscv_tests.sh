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
	"$ROOT/rtl/predictor/bht_2bit.sv" \
	"$ROOT/rtl/predictor/btb.sv" \
	"$ROOT/rtl/core/scoreboard.sv" \
	"$ROOT/rtl/cache/replacement_lru.sv" \
	"$ROOT/rtl/cache/replacement_plru.sv" \
	"$ROOT/rtl/cache/l1_dcache.sv" \
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

echo "== unit tests =="
rm -f "$BUILD/.unit_status"
for unit in bht btb; do
	case "$unit" in
		bht) src="$ROOT/rtl/predictor/bht_2bit.sv" ;;
		btb) src="$ROOT/rtl/predictor/btb.sv" ;;
	esac
	iverilog -g2012 -o "$BUILD/tb_$unit.vvp" "$src" "$ROOT/tb/unit/tb_$unit.sv"
	out=$(vvp "$BUILD/tb_$unit.vvp" 2>&1 || true)
	if grep -q '^PASS' <<<"$out" && ! grep -q '^FAIL' <<<"$out"; then
		echo "PASS tb_$unit ($(printf '%s\n' "$out" | grep '^PASS'))"
	else
		echo "FAIL tb_$unit:"
		printf '%s\n' "$out"
		echo "UNIT_FAIL=1" >> "$BUILD/.unit_status"
	fi
done
# L1 data cache: same testbench under both replacement policies
for pol in lru plru; do
	dflag=""
	[[ "$pol" == "plru" ]] && dflag="-DPLRU_TEST"
	iverilog -g2012 $dflag -o "$BUILD/tb_dcache_$pol.vvp" \
		"$ROOT/rtl/cache/replacement_lru.sv" \
		"$ROOT/rtl/cache/replacement_plru.sv" \
		"$ROOT/rtl/cache/l1_dcache.sv" \
		"$ROOT/tb/unit/tb_dcache.sv"
	out=$(vvp "$BUILD/tb_dcache_$pol.vvp" 2>&1 || true)
	if grep -q '^DCACHE TEST PASS' <<<"$out" && ! grep -q '^FAIL' <<<"$out"; then
		echo "PASS tb_dcache ($pol, $(printf '%s\n' "$out" | grep -c '^PASS') checks)"
	else
		echo "FAIL tb_dcache ($pol):"
		printf '%s\n' "$out"
		echo "UNIT_FAIL=1" >> "$BUILD/.unit_status"
	fi
done
if [[ -f "$BUILD/.unit_status" ]]; then
	rm -f "$BUILD/.unit_status"
	echo
	echo "RESULT: unit tests FAILED"
	exit 1
fi

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
	local name="$1" hex="$2" expected="$3" out magic vflags=""
	# Phase 5: the attack needs a long timeout and dumps the result
	# region (RES lines) for the signature plot
	if [[ "$name" == "spectre_v1" ]]; then
		vflags="+TIMEOUT=2000000 +DUMPADDR=2000 +DUMPWORDS=1799"
	fi
	out=$(vvp "$BUILD/tb_core.vvp" +HEX="$hex" $vflags 2>&1 || true)
	# misprediction statistics (Phase 3), shown for branch-heavy tests
	# (herestrings: `printf | grep -q` races SIGPIPE under `pipefail`)
	if grep -q '^STAT' <<<"$out"; then
		grep '^STAT' <<<"$out" | sed "s/^/  [$name] /"
	fi
	magic=$(grep -oE 'MAGIC 0x[0-9a-fA-F]+' <<<"$out" | \
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

	# Phase 4: speculative-fill side effect (squash_fill only)
	if [[ "$name" == "squash_fill" ]]; then
		local f_out
		f_out=$(vvp "$BUILD/tb_core.vvp" +HEX="$hex" \
			+expectfill=100 +expectnofill=200 2>&1 || true)
		if grep -q '^EXPECTFILL PASS' <<<"$f_out" && \
		   grep -q '^EXPECTNOFILL PASS' <<<"$f_out"; then
			echo "  fill side-effect OK (0x100 present, 0x200 absent)"
		else
			printf '%s\n' "$f_out" | grep -E '^(EXPECT|MAGIC|STAT)' || true
			echo "  FAIL $name fill expectation"
			FAIL=$((FAIL + 1))
		fi
	fi

	# Phase 5: RES dump -> CSV -> signature plot + recovery verification
	if [[ "$name" == "spectre_v1" ]]; then
		local res_csv="$ROOT/results/spectre/results.csv"
		mkdir -p "$ROOT/results/spectre"
		if ! grep -q '^RES ' <<<"$out"; then
			echo "  FAIL $name — no RES dump lines"
			FAIL=$((FAIL + 1))
			return
		fi
		grep '^RES ' <<<"$out" | \
			python3 -c '
import sys, csv
rows = {}
for line in sys.stdin:
    _, i, v = line.split()
    rows[int(i)] = int(v, 16)
w = csv.writer(open(sys.argv[1], "w", newline=""))
w.writerow(["trial", "secret", "b", "latency"])
trials = len(rows) // 257
for t in range(trials):
    base = t * 257
    secret = rows[base]
    for b in range(256):
        w.writerow([t, secret, b, rows[base + 1 + b]])
' "$res_csv"
		if python3 "$ROOT/scripts/plot_spectre.py" --csv "$res_csv" \
			--out-dir "$ROOT/results/spectre" --verify; then
			echo "  spectre signature OK (dip at secret, recovery 7/7)"
		else
			echo "  FAIL $name spectre recovery"
			FAIL=$((FAIL + 1))
		fi
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
