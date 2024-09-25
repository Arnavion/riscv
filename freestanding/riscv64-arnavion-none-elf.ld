MEMORY {
	ram (rw) :        ORIGIN = 0x0000000000000000, LENGTH = 0x7ffffffffff80000
	program (rx) :    ORIGIN = 0x8000000000001000, LENGTH = 1M
	in_file (r) :     ORIGIN = 0xffffffffffe00000, LENGTH = 1M
	in_file_len (r) : ORIGIN = 0xffffffffffdffff8, LENGTH = 8
	console (w) :     ORIGIN = 0xfffffffffff00000, LENGTH = 4096
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

	_IN_FILE_PTR = 0xffffffffffe00000;
	_IN_FILE_LEN_PTR = 0xffffffffffdffff8;
	_CONSOLE_PTR = 0xfffffffffff00000;
	_CONSOLE_LEN = 4096;

	_STACK_PTR = 0x500000;
}
