#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-1;

int main(void) {
	uint8_t x = *IO;
	*IO = x + 5;
}