#include <stdint.h>

static volatile uint8_t* const IO = (volatile uint8_t*)(intptr_t)-8;

static const uint8_t TOGGLE = 5;

int main(void) {
	uint8_t highest_disk_nr = *IO;
	uint8_t src = *IO;
	uint8_t dest = *IO;
	uint8_t spare = *IO;

	uint64_t positions = 0;
	uint32_t num_disks_is_even = highest_disk_nr % 2;
	uint32_t pegs =
		((uint32_t) src) |
		(((uint32_t) dest) << ((1 + num_disks_is_even) * 8)) |
		(((uint32_t) spare) << ((2 - num_disks_is_even) * 8));

	for (uint64_t i = 0; ; i++) {
		uint8_t j = __builtin_ctzl(~i);

		// positions = stdc_rotate_right(positions, ((uint32_t) j) * 8);
		positions = (positions >> ((uint32_t) j) * 8) | (positions << (64 - ((uint32_t) j) * 8));

		uint8_t position = positions & 0b11;
		*IO = (pegs >> (position * 8)) & 0xff;
		*IO = TOGGLE;

		uint8_t next_position = (position + 1 + (j & 1)) % 3;
		*IO = (pegs >> (next_position * 8)) & 0xff;
		*IO = TOGGLE;

		positions = (positions & 0xffffffffffffff00ULL) | ((uint64_t) next_position);
		// positions = stdc_rotate_left(positions, ((uint32_t) j) * 8);
		positions = (positions << ((uint32_t) j) * 8) | (positions >> (64 - ((uint32_t) j) * 8));
	}
}
