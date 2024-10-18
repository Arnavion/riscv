#![cfg(target_arch = "riscv64")]

#![feature(
	maybe_uninit_write_slice,
)]

#![no_main]
#![no_std]

use core::fmt::Write;

core::arch::global_asm!("
	.global _start
	.extern _STACK_PTR
	.extern _CONSOLE_PTR
	.extern _CONSOLE_LEN
	.extern _IN_FILE_PTR
	.extern _IN_FILE_LEN_PTR

	.section .text.boot

_start: lga sp, _STACK_PTR
	jal main
_halt: ebreak
	j _halt
");

#[unsafe(no_mangle)]
extern "C" fn main() {
	let timer = HardwareTimer::new();

	let mut console = Console::new();

	let in_file_ptr: *const u8;
	let in_file_len_ptr: *const u64;

	unsafe {
		core::arch::asm!("lga {}, _IN_FILE_PTR", out(reg) in_file_ptr);
		core::arch::asm!("lga {}, _IN_FILE_LEN_PTR", out(reg) in_file_len_ptr);
	}

	let program = unsafe { core::slice::from_raw_parts(in_file_ptr, (*in_file_len_ptr).try_into().expect("u64 -> usize")) };

	let result = main_inner(&mut console, program);
	_ = writeln!(console, "{result:?}");

	let (cycles, time, instret) = timer.since();
	let (time_s, time_ms) = (time.as_secs(), time.subsec_millis());
	#[allow(clippy::cast_possible_truncation)]
	let frequency = (cycles * 1_000_000_000) / (time.as_nanos() as u64);
	_ = writeln!(console, "executed {instret} instructions in {cycles} cycles, {time_s}.{time_ms:03} s, {frequency} Hz");
}

fn main_inner(console: &mut Console<'_>, program: &[u8]) -> Result<(), ()> {
	let program = core::str::from_utf8(program).map_err(|err| { _ = writeln!(console, "{err}"); })?;

	let supported_extensions = riscv::SupportedExtensions::RV64C_ZCB | riscv::SupportedExtensions::ZBA;

	for instruction in riscv::parse_program(program, supported_extensions) {
		let instruction = instruction.map_err(|err| { _ = writeln!(console, "{err}"); })?;
		let (lo, hi) =
			instruction.encode(supported_extensions)
			.map_err(|err| { _ = writeln!(console, "{err}"); })?;

		if let Some(hi) = hi {
			_ = writeln!(console, "<U32>0x{hi:04x}{lo:04x} ; {instruction}");
		}
		else {
			_ = writeln!(console, "<U16>0x{lo:04x}     ; {instruction}");
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
		let tick_ns: u64;

		unsafe {
			core::arch::asm!("lga {}, _TIMER_TICK_NS", out(reg) tick_ns);
		}

		let (cycles, time, instret) = Self::read();
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
			core::arch::asm!("rdcycle {}", out(reg) cycles);
			core::arch::asm!("rdtime {}", out(reg) time);
			core::arch::asm!("rdinstret {}", out(reg) instret);
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
		let console_ptr: *mut core::mem::MaybeUninit<u8>;
		let console_len: usize;

		unsafe {
			core::arch::asm!("lga {}, _CONSOLE_PTR", out(reg) console_ptr);
			core::arch::asm!("lga {}, _CONSOLE_LEN", out(reg) console_len);
		}

		Console {
			region: unsafe { core::slice::from_raw_parts_mut(console_ptr, console_len) },
			col: 0,
		}
	}
}

impl Drop for Console<'_> {
	fn drop(&mut self) {
		unsafe { core::arch::asm!("fence"); }
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
					cursor.write(b' ');
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

	unsafe { core::arch::asm!("j _halt", options(noreturn)); }
}
