#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

static const uint8_t FORWARD = 1;
static const uint8_t ENJOY = 3;
static const uint8_t SHOOT = 5;

int main(void) {
	*IO = SHOOT;
	*IO = FORWARD;
	while (true) {
		uint8_t current = *IO;
		if (__builtin_expect(current, 0) > 0) {
			*IO = SHOOT;
		}
		else {
			*IO = ENJOY;
		}
	}
}
