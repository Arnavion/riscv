#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

static const uint8_t SPACE = ' ';
static const uint8_t CASE_DIFF = 'a' - 'A';

int main(void) {
	bool capitalize = true;

	while (true) {
		uint8_t c = *IO;

		if (c == SPACE) {
			capitalize = true;
		}
		else if (capitalize) {
			c -= CASE_DIFF;
			capitalize = false;
		}

		*IO = c;
	}
}
