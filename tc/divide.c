#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint16_t numerator = *IO;
	uint16_t denominator = *IO << 7;
	uint8_t quotient = 0;

	for (int8_t i = 7; ; i--) {
		if (numerator >= denominator) {
			numerator -= denominator;
			quotient |= 1;
		}

		if (i == 0) {
			break;
		}

		quotient <<= 1;
		denominator >>= 1;
	}

	*IO = quotient;
	*IO = numerator;

	__builtin_unreachable();
}
