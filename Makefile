# Cache-Safety build helpers
CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -Wall -Wextra -Wpedantic
IVERILOG ?= iverilog
VVP      ?= vvp
RISCV_TC ?= $(HOME)/.local/share/riscv-tc
RANDOM_SEEDS ?= 20

.PHONY: all sim test test-sim test-rtl test-riscv waves lint clean

all: sim

sim: cache_sim

cache_sim: sim/src/cache.cpp
	$(CXX) $(CXXFLAGS) sim/src/cache.cpp -o cache_sim

test: test-sim test-rtl test-riscv

test-sim: cache_sim
	python3 -m unittest discover -s sim/tests -v

test-rtl: tb_picorv32.vvp
	$(VVP) tb_picorv32.vvp

test-riscv:
	RISCV_TC=$(RISCV_TC) RANDOM_SEEDS=$(RANDOM_SEEDS) ./tests/run_riscv_tests.sh

tb_picorv32.vvp: rtl/core/picorv32/picorv32.v tb/unit/tb_picorv32.sv
	$(IVERILOG) -g2012 -o $@ rtl/core/picorv32/picorv32.v tb/unit/tb_picorv32.sv

waves: rtl/core/picorv32/picorv32.v tb/unit/tb_picorv32.sv
	$(IVERILOG) -g2012 -o tb_picorv32.vvp rtl/core/picorv32/picorv32.v tb/unit/tb_picorv32.sv
	$(VVP) tb_picorv32.vvp +vcd
	@echo "Waveform: tb_picorv32.vcd (open with GTKWave)"

lint:
	@command -v verilator >/dev/null 2>&1 && \
	  verilator --lint-only -Wall rtl/core/picorv32/picorv32.v || \
	  echo "verilator not installed; skipping RTL lint"

clean:
	rm -f cache_sim tb_picorv32.vvp *.vcd
