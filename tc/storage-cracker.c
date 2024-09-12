#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint8_t guess = 0x80;
	uint8_t mask = 0x80;

	for (;;) {
		*IO = guess;
		if (*IO == 1) {
			guess ^= mask;
		}
		mask >>= 1;
		guess |= mask;
	}
}
