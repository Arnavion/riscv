#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint8_t state = *IO;

	while (true) {
		uint8_t temp1 = state ^ (state >> 1);
		uint8_t temp2 = temp1 ^ (temp1 << 1);
		state = temp2 ^ (temp2 >> 2);
		*IO = state % 4;
	}
}
