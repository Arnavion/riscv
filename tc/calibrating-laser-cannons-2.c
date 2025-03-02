#include <stddef.h>
#include <stdint.h>

static volatile uint8_t* const IN = (volatile uint8_t*)(intptr_t)-8;
static volatile uint16_t* const OUT = (volatile uint16_t*)(intptr_t)-8;

static uint16_t* const STACK = (uint16_t*)(intptr_t)0x400000;

static void done(uint16_t result) {
	*OUT = result;
	__builtin_unreachable();
}

static uint16_t parse_int(uint8_t c, bool negative) {
	uint16_t current_token = 0;

	for (;;) {
		c = c - '0';
		current_token = current_token * 10 + c;

		c = *IN;
		switch (c) {
			case ' ':
				if (negative) {
					current_token = -current_token;
				}
				return current_token;

			case '0' ... '9':
				break;

			default:
				__builtin_unreachable();
				break;
		}
	}
}

int main(void) {
	uint16_t* stack_top = STACK;

	uint16_t previous_num;
	{
		uint8_t c = *IN;
		bool negative = c == '-';
		if (negative) {
			c = *IN;
		}
		previous_num = parse_int(c, negative);
	}

	for (;;) {
		uint8_t c = *IN;

		switch (c) {
			case '\0':
				done(previous_num);
				break;

			case '&':
				previous_num = *(stack_top++) & previous_num;
				*IN;
				break;

			case '+':
				previous_num = *(stack_top++) + previous_num;
				*IN;
				break;

			case '-':
				c = *IN;
				switch (c) {
					case '\0':
						previous_num = *(stack_top++) - previous_num;
						done(previous_num);
						break;

					case ' ':
						previous_num = *(stack_top++) - previous_num;
						break;

					case '0' ... '9':
						*(--stack_top) = previous_num;
						previous_num = parse_int(c, true);
						break;

					default:
						__builtin_unreachable();
						break;
				}
				break;

			case '0' ... '9':
				*(--stack_top) = previous_num;
				previous_num = parse_int(c, false);
				break;

			case '<':
				previous_num = (uint16_t)(((uint64_t)*(stack_top++)) << previous_num);
				*IN;
				*IN;
				break;

			case '>':
				previous_num = (uint16_t)(((uint64_t)*(stack_top++)) >> previous_num);
				*IN;
				*IN;
				break;

			case '^':
				previous_num = *(stack_top++) ^ previous_num;
				*IN;
				break;

			case '|':
				previous_num = *(stack_top++) | previous_num;
				*IN;
				break;

			default:
				__builtin_unreachable();
				break;
		}
	}
}
