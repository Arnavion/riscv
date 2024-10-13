#![cfg(target_arch = "riscv64")]

#![feature(
	maybe_uninit_write_slice,
	ptr_sub_ptr,
)]

#![no_main]
#![no_std]

use core::fmt::Write;

core::arch::global_asm!("
	.global _start
	.extern _STACK_PTR

	.section .text._start

_start:
	lga sp, _STACK_PTR
	j {main}
", main = sym main);

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
		extern "C" {
			static mut _IN_FILE_PTR: u8;
			static _IN_FILE_LEN_PTR: usize;
		}

		let in_file_ptr = &raw const _IN_FILE_PTR;
		let in_file_len_ptr = &raw const _IN_FILE_LEN_PTR;

		let mut in_file = unsafe { core::slice::from_raw_parts(in_file_ptr, *in_file_len_ptr) };

		core::iter::from_fn(move || {
			if in_file.is_empty() {
				return None;
			}

			let (line, rest) = split_line(in_file);
			in_file = rest;
			Some(line)
		})
	};

	let supported_extensions = riscv::SupportedExtensions::RV64C_ZCB | riscv::SupportedExtensions::ZBA;

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
		extern "C" {
			static _TIMER_TICK_NS: core::ffi::c_void;
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
		extern "C" {
			static mut _CONSOLE_PTR: core::mem::MaybeUninit<u8>;
			static mut _CONSOLE_END_PTR: core::mem::MaybeUninit<u8>;
		}

		let console_ptr: *mut core::mem::MaybeUninit<u8> = &raw mut _CONSOLE_PTR;
		let console_end_ptr: *mut core::mem::MaybeUninit<u8> = &raw mut _CONSOLE_END_PTR;
		let console_len: usize = unsafe { console_end_ptr.sub_ptr(console_ptr) };

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

/// Returns `(line, rest)`, where `line` ends at `b'\n'` or
/// reached the end of the given slice.
///
/// If `rest` is empty then `line` reached the end of the given slice,
/// and is thus the last line.
/// This is a SWAR implementation.
///
/// Ref: <https://en.wikipedia.org/w/index.php?title=SWAR&oldid=1276491101#Further_refinements_2>
fn split_line(s: &[u8]) -> (&[u8], &[u8]) {
	const C1: usize = usize::from_ne_bytes([b'\n'; core::mem::size_of::<usize>()]);
	const C2: usize = usize::from_ne_bytes([0x01; core::mem::size_of::<usize>()]);
	const C3: usize = usize::from_ne_bytes([0x80; core::mem::size_of::<usize>()]);

	let (s_head, s_aligned, s_tail) = unsafe { s.align_to::<usize>() };

	if let Some(i) = s_head.iter().position(|&b| b == b'\n') {
		return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
	}

	let mut line_end = s_head.len();
	for &chunk in s_aligned {
		let chunk = chunk ^ C1;
		if chunk.wrapping_sub(C2) & !chunk & C3 != 0 {
			let i = chunk.to_ne_bytes().into_iter().position(|b| b == b'\0');
			let i = unsafe { i.unwrap_unchecked() };
			let i = line_end + i;
			return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
		}

		line_end += core::mem::size_of::<usize>();
	}

	if let Some(i) = s_tail.iter().position(|&b| b == b'\n') {
		let i = line_end + i;
		return (unsafe { s.get_unchecked(..i) }, unsafe { s.get_unchecked(i + 1..) });
	}

	(s, b"")
}
