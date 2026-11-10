/* Linker script: code at 0x0 (instruction memory), data/bss at 0x2000,
 * stack growing down from 0x4000 (data memory, 16 KiB in tb_core). */
OUTPUT_ARCH(riscv)
ENTRY(_start)

SECTIONS
{
	. = 0x00000000;
	.text : {
		*(.text.start)
		*(.text*)
	}

	. = 0x00002000;
	.rodata : { *(.rodata*) }
	.data : { *(.data*) }
	.bss : {
		__bss_start = .;
		*(.bss*)
		*(COMMON)
		__bss_end = .;
	}

	. = 0x00004000;
	__stack_top = .;
}
