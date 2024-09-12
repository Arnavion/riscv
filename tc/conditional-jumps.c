#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint8_t count = 0;
	while (true) {
		uint8_t n = *IO;
		count++;
		if (n == 37) {
			break;
		}
	}
	*IO = count;
}
