#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

static const uint8_t TOGGLE = 5;

static void move(uint8_t disk_nr, uint8_t source, uint8_t destination, uint8_t spare) {
	if (disk_nr > 0) {
		move(disk_nr - 1, source, spare, destination);
	}

	*IO = source;
	*IO = TOGGLE;
	*IO = destination;
	*IO = TOGGLE;

	if (disk_nr > 0) {
		move(disk_nr - 1, spare, destination, source);
	}
}

int main(void) {
	uint8_t disk_nr = *IO;
	uint8_t source = *IO;
	uint8_t destination = *IO;
	uint8_t spare = *IO;
	move(disk_nr, source, destination, spare);

	__builtin_unreachable();
}
