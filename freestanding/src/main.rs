#![cfg(target_arch = "riscv64")]

#![feature(
	abi_custom,
)]

#![no_main]
#![no_std]

use core::fmt::Write;

#[unsafe(naked)]
#[unsafe(no_mangle)]
pub unsafe extern "custom" fn _start() {
	core::arch::naked_asm!("
		.extern _STACK_PTR
		lga sp, _STACK_PTR
		j {main}
	", main = sym main);
}

fn main() -> ! {
	{
		let timer = HardwareTimer::new();

		let mut console = Console::new();

		let result = main_inner(&mut console);
		_ = writeln!(console, "{result:?}");

		let (cycles, time, instret) = timer.since();
		let (time_s, time_ms) = (time.as_secs(), time.subsec_millis());
		#[allow(clippy::cast_possible_truncation)]
		let frequency = (cycles * 1_000_000_000) / (time.as_nanos() as u64);
		_ = writeln!(console, "executed {instret} instructions in {cycles} cycles, {time_s}.{time_ms:03} s, {frequency} Hz");
	}

	halt();
}

fn main_inner(console: &mut Console<'_>) -> Result<(), ()> {
	let program = {
		unsafe extern "C" {
			safe static mut _IN_FILE_PTR: u8;
			safe static mut _IN_FILE_END_PTR: u8;
		}

		let in_file_ptr = &raw const _IN_FILE_PTR;
		let in_file_end_ptr = &raw const _IN_FILE_END_PTR;
		let in_file_max_len = unsafe { in_file_end_ptr.byte_offset_from_unsigned(in_file_ptr) };

		let mut in_file = unsafe { core::slice::from_raw_parts(in_file_ptr, in_file_max_len) };

		core::iter::from_fn(move || {
			if in_file.is_empty() {
				return None;
			}

			let (line, rest) = split_line(in_file);
			in_file = rest;
			Some(line)
		})
	};

	let supported_extensions = riscv::SupportedExtensions::RV64C_ZCB | riscv::SupportedExtensions::ZBA | riscv::SupportedExtensions::ZBB;

	let mut pc = 0_u64;

	for instruction in riscv::parse_program(program, supported_extensions) {
		let instruction =
			instruction
			.map_err(|err| { _ = writeln!(console, "{err}"); })?;
		let (lo, hi) =
			instruction.encode(supported_extensions)
			.map_err(|err| { _ = writeln!(console, "{err}"); })?;

		if let Some(hi) = hi {
			_ = writeln!(console, "<U32>0x{hi:04x}{lo:04x} ; {pc:3}: {instruction}");

			pc += 4;
		}
		else {
			_ = writeln!(console, "<U16>0x{lo:04x}     ; {pc:3}: {instruction}");

			pc += 2;
		}
	}

	Ok(())
}

#[derive(Clone, Copy)]
struct HardwareTimer {
	tick_ns: u64,
	cycles: u64,
	time: u64,
	instret: u64,
}

impl HardwareTimer {
	fn new() -> Self {
		unsafe extern "C" {
			safe static _TIMER_TICK_NS: core::ffi::c_void;
		}

		let (cycles, time, instret) = Self::read();

		let tick_ns: u64 = (&raw const _TIMER_TICK_NS).addr() as _;

		Self {
			tick_ns,
			cycles,
			time,
			instret,
		}
	}

	fn since(self) -> (u64, core::time::Duration, u64) {
		let (new_cycles, new_time, new_instret) = Self::read();
		let time_ns = (new_time - self.time) * self.tick_ns;
		let time = core::time::Duration::from_nanos(time_ns);
		(new_cycles - self.cycles, time, new_instret - self.instret)
	}

	fn read() -> (u64, u64, u64) {
		let cycles: u64;
		let time: u64;
		let instret: u64;
		unsafe {
			core::arch::asm!(
				"rdcycle {cycles}",
				"rdtime {time}",
				"rdinstret {instret}",
				cycles = lateout(reg) cycles,
				time = lateout(reg) time,
				instret = lateout(reg) instret,
				options(nomem, nostack),
			);
		}
		(cycles, time, instret)
	}
}

struct Console<'a> {
	region: &'a mut [core::mem::MaybeUninit<u8>],
	col: usize,
}

impl Console<'static> {
	fn new() -> Self {
		unsafe extern "C" {
			safe static mut _CONSOLE_PTR: core::mem::MaybeUninit<u8>;
			safe static mut _CONSOLE_END_PTR: core::mem::MaybeUninit<u8>;
		}

		let console_ptr: *mut core::mem::MaybeUninit<u8> = &raw mut _CONSOLE_PTR;
		let console_end_ptr: *mut core::mem::MaybeUninit<u8> = &raw mut _CONSOLE_END_PTR;
		let console_len: usize = unsafe { console_end_ptr.byte_offset_from_unsigned(console_ptr) };

		Console {
			region: unsafe { core::slice::from_raw_parts_mut(console_ptr, console_len) },
			col: 0,
		}
	}
}

impl Drop for Console<'_> {
	fn drop(&mut self) {
		unsafe {
			core::arch::asm!(
				"fence",
				options(nostack),
			);
		}
	}
}

impl Write for Console<'_> {
	fn write_str(&mut self, s: &str) -> core::fmt::Result {
		for line in s.split_inclusive('\n') {
			let (line, nl) = match line.rsplit_once('\n') {
				Some((line, _)) => (line, true),
				None => (line, false),
			};
			let (this_region, rest_region) = core::mem::take(&mut self.region).split_at_mut_checked(line.len()).ok_or(core::fmt::Error)?;
			this_region.write_copy_of_slice(line.as_bytes());
			self.region = rest_region;
			self.col += line.len();

			if nl {
				let num_spaces = 80 - (self.col % 80);
				let (this_region, rest_region) = core::mem::take(&mut self.region).split_at_mut_checked(num_spaces).ok_or(core::fmt::Error)?;
				if let Some(cursor) = this_region.first_mut() {
					cursor.write(b'\0');
				}
				self.region = rest_region;
				self.col = 0;
			}
		}

		if let Some((first, _)) = self.region.split_first_mut() {
			first.write(b'_');
		}

		Ok(())
	}
}

#[panic_handler]
fn panic(panic: &core::panic::PanicInfo<'_>) -> ! {
	{
		let mut console = Console::new();
		_ = writeln!(console, "panic: {}", panic.message());
	}

	halt();
}

fn halt() -> ! {
	loop {
		unsafe {
			core::arch::asm!(
				"ebreak",
				options(nomem, nostack),
			);
		}
	}
}

/// Returns `(line, rest)`, where `line` ends at either a `b'\0'` or a `b'\n'` or
/// reached the end of the given slice.
///
/// If `rest` is empty then `line` ended at a `b'\0'` or reached the end of the given slice,
/// and is thus the last line.
mod split_line {
	/// This is a vector implementation based on the V extension.
	#[cfg(target_feature = "v")]
	pub(super) fn split_line(mut s: &[u8]) -> (&[u8], &[u8]) {
		let s_orig = s;
		let mut line_end = 0;

		loop {
			unsafe {
				let read: usize;
				core::arch::asm!(
					"vsetvli zero, {len}, e8, m8, ta, ma",
					"vle8ff.v v8, ({ptr})",
					"csrr {read}, vl",
					len = in(reg) s.len(),
					ptr = in(reg) s.as_ptr(),
					read = lateout(reg) read,
					out("v8") _,
					out("v9") _,
					out("v10") _,
					out("v11") _,
					out("v12") _,
					out("v13") _,
					out("v14") _,
					out("v15") _,
					options(nostack),
				);

				{
					let i: usize;
					core::arch::asm!(
						"vmseq.vi v0, v8, {c}",
						"vfirst.m {i}, v0",
						lateout("v0") _,
						c = const b'\n',
						i = lateout(reg) i,
						options(nostack),
					);
					if i.cast_signed() >= 0 {
						let i = line_end + i;
						return (s_orig.get_unchecked(..i), s_orig.get_unchecked(i + 1..));
					}
				}

				{
					let i: usize;
					core::arch::asm!(
						"vmseq.vi v0, v8, {c}",
						"vfirst.m {i}, v0",
						lateout("v0") _,
						c = const b'\0',
						i = lateout(reg) i,
						options(nostack),
					);
					if i.cast_signed() >= 0 {
						let i = line_end + i;
						return (s_orig.get_unchecked(..i), b"");
					}
				}

				s = s.get_unchecked(read..);
				line_end += read;
			}
		}
	}

	/// This is a SWAR implementation based on the Zbb extension.
	#[cfg(all(not(target_feature = "v"), target_feature = "zbb"))]
	pub(super) fn split_line(s: &[u8]) -> (&[u8], &[u8]) {
		const C1: usize = usize::from_ne_bytes([b'\n'; core::mem::size_of::<usize>()]);

		fn expand_slice_to_usize(s: &[u8]) -> usize {
			unsafe { core::hint::assert_unchecked(s.len() < core::mem::size_of::<usize>()); }

			// `s` is guaranteed to be contained within an aligned usize-sized chunk.
			// We can read that chunk, then shift it so that the bytes of `s` are the first,
			// then set the excess bytes to 0xff. This result will then only contain a `b'\0'` or `b'\n'`
			// at the index that `s` contains a `b'\0'` or `b'\n'`.
			//
			// We can't dereference the chunk pointer in Rust code because there is no guarantee that
			// all `size_of::<usize>()` bytes are in the same allocation as `s`,
			// so dereferencing the pointer would be UB. miri confirms this.
			// However it *is* legal to read that usize using an inline assembly load instruction.
			// miri cannot introspect this to prove it, but this is also what the SWAR impl of `strlen`
			// in compiler_builtins does, with the same justification.

			let s_ptr = s.as_ptr().addr();
			let s_aligned_start_ptr = (s.as_ptr().addr() / core::mem::size_of::<usize>()) * core::mem::size_of::<usize>();

			let chunk: usize;
			unsafe {
				core::arch::asm!(
					"ld {chunk}, ({s_aligned_start_ptr})",
					s_aligned_start_ptr = in(reg) s_aligned_start_ptr,
					chunk = lateout(reg) chunk,
					options(nostack, pure, readonly),
				);
			}

			#[cfg(target_endian = "little")]
			{
				let num_trailing_garbage_bits = (s_ptr % core::mem::size_of::<usize>()) * 8;
				let chunk = chunk >> num_trailing_garbage_bits;

				let num_valid_bits = s.len() * 8;
				let chunk = chunk | (usize::MAX << num_valid_bits);

				chunk
			}
			#[cfg(target_endian = "big")]
			{
				let num_leading_garbage_bits = (s_ptr % core::mem::size_of::<usize>()) * 8;
				let chunk = chunk << num_leading_garbage_bits;

				let num_valid_bits = s.len() * 8;
				let chunk = chunk | (usize::MAX >> num_valid_bits);

				chunk
			}
		}

		// `chunk` must have been formed by interpreting the underlying bytes in native-endian order.
		fn index_of_zero(chunk: usize) -> Option<usize> {
			let result: usize;
			unsafe {
				core::arch::asm!(
					"orc.b {result}, {chunk}",
					chunk = in(reg) chunk,
					result = lateout(reg) result,
					options(nomem, nostack, pure),
				);
			}
			if result == usize::MAX {
				None
			}
			else {
				#[cfg(target_endian = "little")]
				let i = usize::try_from(result.trailing_ones() / 8).expect("u32 -> usize");
				#[cfg(target_endian = "big")]
				let i = usize::try_from(result.leading_ones() / 8).expect("u32 -> usize");

				Some(i)
			}
		}

		// Note: `s_aligned` elements will have been interpreted from the underlying bytes in native-endian order.
		let (s_head, s_aligned, s_tail) = unsafe { s.align_to::<usize>() };

		{
			let chunk = expand_slice_to_usize(s_head);

			if let Some(i) = index_of_zero(chunk ^ C1) {
				return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
			}

			if let Some(i) = index_of_zero(chunk) {
				return (unsafe { s.get_unchecked(..i) }, b"");
			}
		}

		let mut line_end = s_head.len();
		for &chunk in s_aligned {
			if let Some(i) = index_of_zero(chunk ^ C1) {
				let i = line_end + i;
				return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
			}

			if let Some(i) = index_of_zero(chunk) {
				let i = line_end + i;
				return (unsafe { s.get_unchecked(..i) }, b"");
			}

			line_end += core::mem::size_of::<usize>();
		}

		{
			let chunk = expand_slice_to_usize(s_tail);

			if let Some(i) = index_of_zero(chunk ^ C1) {
				let i = line_end + i;
				return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
			}

			if let Some(i) = index_of_zero(chunk) {
				let i = line_end + i;
				return (unsafe { s.get_unchecked(..i) }, b"");
			}
		}

		(s, b"")
	}

	/// This is a SWAR implementation used when the Zbb extension is not present.
	///
	/// Ref: <https://en.wikipedia.org/w/index.php?title=SWAR&oldid=1276491101#Further_refinements_2>
	#[cfg(all(not(target_feature = "v"), not(target_feature = "zbb")))]
	pub(super) fn split_line(s: &[u8]) -> (&[u8], &[u8]) {
		const C1: usize = usize::from_ne_bytes([b'\n'; core::mem::size_of::<usize>()]);
		const C2: usize = usize::from_ne_bytes([0x01; core::mem::size_of::<usize>()]);
		const C3: usize = usize::from_ne_bytes([0x80; core::mem::size_of::<usize>()]);

		let (s_head, s_aligned, s_tail) = unsafe { s.align_to::<usize>() };

		for (i, &b) in s_head.iter().enumerate() {
			if b == b'\n' {
				return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
			}
			if b == b'\0' {
				return (unsafe { s.get_unchecked(..i) }, b"");
			}
		}

		let mut line_end = s_head.len();
		for &chunk in s_aligned {
			{
				let chunk = chunk ^ C1;
				if chunk.wrapping_sub(C2) & !chunk & C3 != 0 {
					let i = chunk.to_ne_bytes().into_iter().position(|b| b == b'\0');
					let i = unsafe { i.unwrap_unchecked() };
					let i = line_end + i;
					return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
				}
			}

			if chunk.wrapping_sub(C2) & !chunk & C3 != 0 {
				let i = chunk.to_ne_bytes().into_iter().position(|b| b == b'\0');
				let i = unsafe { i.unwrap_unchecked() };
				let i = line_end + i;
				return (unsafe { s.get_unchecked(..i) }, b"");
			}

			line_end += core::mem::size_of::<usize>();
		}

		for (i, &b) in s_tail.iter().enumerate() {
			let i = line_end + i;
			if b == b'\n' {
				return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
			}
			if b == b'\0' {
				return (unsafe { s.get_unchecked(..i) }, b"");
			}
		}

		(s, b"")
	}
}
use split_line::split_line;

/// This is a vector implementation based on the V extension.
#[cfg(target_feature = "v")]
#[unsafe(no_mangle)]
extern "C" fn memcmp(mut s1: *const u8, mut s2: *const u8, mut n: usize) -> i32 {
	while n > 0 {
		unsafe {
			let read: usize;
			let index_ne: usize;
			core::arch::asm!(
				"vsetvli {read}, {n}, e8, m8, ta, ma",
				"vle8.v v8, ({s1})",
				"vle8.v v16, ({s2})",
				"vmsne.vv v0, v8, v16",
				"vfirst.m {index_ne}, v0",
				n = in(reg) n,
				s1 = in(reg) s1,
				s2 = in(reg) s2,
				read = out(reg) read,
				index_ne = lateout(reg) index_ne,
				out("v0") _,
				out("v8") _,
				out("v9") _,
				out("v10") _,
				out("v11") _,
				out("v12") _,
				out("v13") _,
				out("v14") _,
				out("v15") _,
				out("v16") _,
				out("v17") _,
				out("v18") _,
				out("v19") _,
				out("v20") _,
				out("v21") _,
				out("v22") _,
				out("v23") _,
				options(nostack),
			);

			if index_ne.cast_signed() >= 0 {
				let e1 = s1.add(index_ne);
				let e2 = s2.add(index_ne);
				return i32::from(*e1) - i32::from(*e2);
			}

			n -= read;
			s1 = s1.add(read);
			s2 = s2.add(read);
		}
	}

	0
}

/// This is a vector implementation based on the V extension.
#[cfg(target_feature = "v")]
#[unsafe(no_mangle)]
extern "C" fn memcpy(mut dest: *mut u8, mut src: *const u8, mut n: usize) -> *mut u8 {
	let result = dest;

	while n > 0 {
		unsafe {
			let read: usize;
			core::arch::asm!(
				"vsetvli {read}, {n}, e8, m8, ta, ma",
				"vle8.v v8, ({src})",
				"vse8.v v8, ({dest})",
				n = in(reg) n,
				src = in(reg) src,
				read = out(reg) read,
				dest = in(reg) dest,
				out("v8") _,
				out("v9") _,
				out("v10") _,
				out("v11") _,
				out("v12") _,
				out("v13") _,
				out("v14") _,
				out("v15") _,
				options(nostack),
			);

			n -= read;
			dest = dest.add(read);
			src = src.add(read);
		}
	}

	result
}

/// This is a vector implementation based on the V extension.
#[cfg(target_feature = "v")]
#[unsafe(no_mangle)]
extern "C" fn memmove(dest: *mut u8, src: *const u8, mut n: usize) -> *mut u8 {
	if dest.addr().wrapping_sub(src.addr()) >= n {
		// Either dest < src, or src and dest don't overlap.
		// In the former case we want to copy forwards like memcpy does.
		// In the latter case the copy direction doesn't matter, so forwards
		// is fine.
		return memcpy(dest, src, n);
	}

	let result = dest;

	let mut src = unsafe { src.add(n) };
	let mut dest = unsafe { dest.add(n) };

	while n > 0 {
		unsafe {
			let read: usize;
			core::arch::asm!(
				"vsetvli {read}, {n}, e8, m8, ta, ma",
				"sub {src}, {src}, {read}",
				"sub {dest}, {dest}, {read}",
				"vle8.v v8, ({src})",
				"vse8.v v8, ({dest})",
				n = in(reg) n,
				src = inout(reg) src,
				read = out(reg) read,
				dest = inout(reg) dest,
				out("v8") _,
				out("v9") _,
				out("v10") _,
				out("v11") _,
				out("v12") _,
				out("v13") _,
				out("v14") _,
				out("v15") _,
				options(nostack),
			);

			n -= read;
		}
	}

	result
}
