MEMORY {
	ram (rw) :        ORIGIN = 0x0000000000000000, LENGTH = 4M
	console (w) :     ORIGIN = 0x0000000000400000, LENGTH = 8K
	program (rx) :    ORIGIN = 0x8000000000000000, LENGTH = 1M
	in_file (r) :     ORIGIN = 0xffffffffffe00000, LENGTH = 1M
	in_file_len (r) : ORIGIN = 0xffffffffffdffff8, LENGTH = 8
}

SECTIONS {
	.text.boot : {
		*(.text.boot)
	} >program

	.text : {
		*(.text)
	} >program

	.rodata : {
		*(.rodata)
	} >program

	.got : {
		*(.got)
	} >program

	_STACK_PTR = 0x400000;
	_TIMER_TICK_NS = 1;
	_CONSOLE_PTR = 0x0000000000400000;
	_CONSOLE_LEN = 0x0000000000001000;
	_IN_FILE_PTR = 0xffffffffffe00000;
	_IN_FILE_LEN_PTR = 0xffffffffffdffff8;
}
