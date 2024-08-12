#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

static const uint8_t LEFT = 0;
static const uint8_t FORWARD = 1;
static const uint8_t RIGHT = 2;
static const uint8_t ENJOY = 3;
static const uint8_t USE = 4;

int main(void) {
	volatile uint8_t* mem = 0;

	*IO = LEFT;
	*IO = FORWARD;
	*IO = LEFT;
	*IO = FORWARD;
	*IO = FORWARD;
	*IO = FORWARD;
	*IO = FORWARD;
	*IO = LEFT;
	*IO = FORWARD;
	*IO = RIGHT;
	*IO = FORWARD;

	while (true) {
		uint8_t current = *IO;
		if (__builtin_expect(current, 92) == 92) {
			*IO = ENJOY;
			continue;
		}

		if (mem[current] > 0) {
			*IO = RIGHT;
			*IO = USE;

			__builtin_unreachable();
		}

		mem[current] = current;
	}
}
