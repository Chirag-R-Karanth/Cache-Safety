/* CRT0 for core5 tests: set stack, clear BSS, call main, publish result. */
.section .text.start, "ax"
.globl _start
_start:
	lui  sp, %hi(__stack_top)
	addi sp, sp, %lo(__stack_top)

	la   t0, __bss_start
	la   t1, __bss_end
1:
	bgeu t0, t1, 2f
	sw   zero, 0(t0)
	addi t0, t0, 4
	j    1b
2:
	call main
	lui  t1, 0xFFFF0          /* magic signature address */
	sw   a0, 0(t1)
3:
	j    3b
