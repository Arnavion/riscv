#include <stdint.h>

static volatile uint64_t* const IO = (volatile uint64_t*)(intptr_t)-8;

int main(void) {
	uint16_t state = *IO;

	while (true) {
		uint16_t temp1 = state ^ (state >> 7);
		uint16_t temp2 = temp1 ^ (temp1 << 9);
		state = temp2 ^ (temp2 >> 8);
		*IO = state;
	}
}
