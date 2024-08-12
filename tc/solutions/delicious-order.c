#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

int main(void) {
	uint8_t scores[15];
	for (int i = 0; i < sizeof(scores) / sizeof(scores[0]); i++) {
		uint8_t new = *IO;

		int j;
		for (j = i; j > 0; j--) {
			if (scores[j - 1] <= new) {
				break;
			}

			scores[j] = scores[j - 1];
		}

		scores[j] = new;
	}

	for (int i = 0; i < sizeof(scores) / sizeof(scores[0]); i++) {
		*IO = scores[i];
	}

	__builtin_unreachable();
}
