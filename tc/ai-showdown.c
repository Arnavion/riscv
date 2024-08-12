#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-1;

int main(void) {
	uint8_t pick[4] = { 3, 0, 1, 2 };

	while (true) {
		uint8_t cards_remaining = *IO;
		*IO = pick[cards_remaining % 4];
	}
}
