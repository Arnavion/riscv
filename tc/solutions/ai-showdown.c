#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	while (true) {
		uint8_t cards_remaining = *IO;
		switch (cards_remaining % 4) {
			case 0: *IO = 3; break;
			case 2: *IO = 1; break;
			case 3: *IO = 2; break;
			default: __builtin_unreachable(); break;
		}
	}
}
