#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint8_t x = *IO;
	uint8_t y = *IO;
	*IO = x ^ y;

	__builtin_unreachable();
}
