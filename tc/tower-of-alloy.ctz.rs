const IO: *mut u8 = -8_isize as usize as _;

fn main() {
	let highest_disk_nr = unsafe { IO.read_volatile() };
	let src = unsafe { IO.read_volatile() };
	let dest = unsafe { IO.read_volatile() };
	let spare = unsafe { IO.read_volatile() };

	let mut positions = 0_u64;
	let pegs = {
		let src = u32::from(src);
		let dest = u32::from(dest);
		let spare = u32::from(spare);
		let num_disks_is_even = highest_disk_nr % 2;

		src |
			(dest << ((1 + num_disks_is_even) * 8)) |
			(spare << ((2 - num_disks_is_even) * 8))
	};

	for i in 0_u64.. {
		let j = i.trailing_ones() as u8;

		positions = positions.rotate_right(u32::from(j) * 8);

		let position = (positions & 0b11) as u8;
		unsafe {
			IO.write_volatile(((pegs >> (position * 8)) & 0xff) as u8);
			IO.write_volatile(5);
		}

		let next_position = (position + 1 + (j & 1));
		let next_position = next_position % 3;
		unsafe {
			IO.write_volatile(((pegs >> (next_position * 8)) & 0xff) as u8);
			IO.write_volatile(5);
		}

		positions = (positions & 0xffffffffffffff00_u64) | u64::from(next_position);
		positions = positions.rotate_left(u32::from(j) * 8);
	}
}
