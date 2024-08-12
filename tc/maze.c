#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

const uint8_t LEFT = 0;
const uint8_t FORWARD = 1;
const uint8_t RIGHT = 2;
const uint8_t USE = 4;

const uint8_t NOTHING = 0;

int main(void) {
	while (true) {
		*IO = LEFT;

		while (true) {
			*IO = USE;

			if (*IO == NOTHING) {
				break;
			}

			*IO = RIGHT;
		}

		*IO = FORWARD;
	}
}
