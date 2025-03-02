#include <stddef.h>
#include <stdint.h>

static volatile uint16_t* const IO = (volatile uint16_t*)(intptr_t)-8;

int main(void) {
	uint16_t stack[0x10000];
	size_t stack_top = sizeof(stack) / sizeof(stack[0]);

	bool current_token_is_negative = false;

	for (;;) {
		uint8_t c = (uint8_t)*IO;

		switch (c) {
			case '\0':
				if (current_token_is_negative) {
					current_token_is_negative = false;
					uint16_t b = stack[stack_top++];
					stack[stack_top] -= b;
				}
				else {
					*IO = stack[stack_top];
					return 0;
				}
				break;

			case ' ':
				if (current_token_is_negative) {
					current_token_is_negative = false;
					uint16_t b = stack[stack_top++];
					stack[stack_top] -= b;
				}
				break;

			case '&': {
				uint16_t b = stack[stack_top++];
				stack[stack_top] &= b;
				*IO;
				break;
			}

			case '+': {
				uint16_t b = stack[stack_top++];
				stack[stack_top] += b;
				*IO;
				break;
			}

			case '-': {
				current_token_is_negative = true;
				break;
			}

			case '<': {
				uint16_t b = stack[stack_top++];
				uint16_t a = stack[stack_top];
				stack[stack_top] = (uint16_t)(((uint64_t)a) << ((uint64_t)b));
				*IO;
				*IO;
				break;
			}

			case '>': {
				uint16_t b = stack[stack_top++];
				uint16_t a = stack[stack_top];
				stack[stack_top] = (uint16_t)(((uint64_t)a) >> ((uint64_t)b));
				*IO;
				*IO;
				break;
			}

			case '^': {
				uint16_t b = stack[stack_top++];
				stack[stack_top] ^= b;
				*IO;
				break;
			}

			case '|': {
				uint16_t b = stack[stack_top++];
				stack[stack_top] |= b;
				*IO;
				break;
			}

			default: {
				uint16_t current_token = c - '0';
				for (;;) {
					c = *IO;
					if (c == ' ' || c == '\0') {
						stack[--stack_top] = current_token;
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

	return 0;
}
