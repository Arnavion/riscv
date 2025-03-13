ENTRY(_start)

SECTIONS {
	.text 0x8000000000000000 : {
		*(.text.boot)
	}

	.rodata : {
		*(.rodata .rodata.* .got .data .data.*)
	}

	_STACK_PTR = 0x400000;
	_TIMER_TICK_NS = 1;
	_CONSOLE_PTR = 0x0000000000400000;
	_CONSOLE_LEN = 0x0000000000002000;
	_IN_FILE_PTR = 0xffffffffffe00000;
	_IN_FILE_MAX_LEN = 0xfffff;
}
