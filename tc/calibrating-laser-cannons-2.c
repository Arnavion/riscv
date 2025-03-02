#include <stddef.h>
#include <stdint.h>

static volatile uint16_t* const IO = (volatile uint16_t*)(intptr_t)-8;

static uint16_t* const STACK = (uint16_t*)(intptr_t)0x400000;

int main(void) {
	uint16_t* stack_top = STACK;

	uint16_t previous_num = 0;

	bool current_token_is_negative = false;

	for (;;) {
		uint8_t c = (uint8_t)*IO;

		switch (c) {
			case '\0': {
				if (current_token_is_negative) {
					current_token_is_negative = false;
					previous_num = *(stack_top++) - previous_num;
				}

				*IO = previous_num;

				__builtin_unreachable();
				break;
			}

			case ' ':
				if (current_token_is_negative) {
					current_token_is_negative = false;
					previous_num = *(stack_top++) - previous_num;
				}
				break;

			case '&': {
				previous_num = *(stack_top++) & previous_num;
				*IO;
				break;
			}

			case '+': {
				previous_num = *(stack_top++) + previous_num;
				*IO;
				break;
			}

			case '-': {
				current_token_is_negative = true;
				break;
			}

			case '<': {
				previous_num = (uint16_t)(((uint64_t)*(stack_top++)) << ((uint64_t)previous_num));
				*IO;
				*IO;
				break;
			}

			case '>': {
				previous_num = (uint16_t)(((uint64_t)*(stack_top++)) >> ((uint64_t)previous_num));
				*IO;
				*IO;
				break;
			}

			case '^': {
				previous_num = *(stack_top++) ^ previous_num;
				*IO;
				break;
			}

			case '|': {
				previous_num = *(stack_top++) | previous_num;
				*IO;
				break;
			}

			default: {
				*(--stack_top) = previous_num;

				uint16_t current_token = c - '0';
				for (;;) {
					c = *IO;
					if (c == ' ' || c == '\0') {
						previous_num = current_token;
						break;
					}

					current_token = current_token * 10;
					if (current_token_is_negative) {
						current_token -= c - '0';
					}
					else {
						current_token += c - '0';
					}
				}
				break;
			}
		}
	}
}
