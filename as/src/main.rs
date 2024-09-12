fn main() -> Result<(), Box<dyn std::error::Error>> {
	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let (path, supported_extensions, save_breaker) = parse_args(args, &argv0);

	let program = std::fs::read_to_string(path)?;

	let mut pc = 0_u64;

	for instruction in riscv::parse_program(&program, supported_extensions) {
		let instruction = instruction.map_err(|err| err.to_string())?;
		let (lo, hi) =
			instruction.encode(supported_extensions)
			.map_err(|err| format!("instruction could not be encoded {instruction:?}: {err}"))?;
		#[allow(clippy::collapsible_else_if)]
		if let Some(hi) = hi {
			if save_breaker {
				println!("<U32>0x{hi:04x}{lo:04x} ; {pc:3}: {instruction}");
			}
			else {
				println!("0x{lo:04x} 0x{hi:04x} # {pc:3}: {instruction}");
			}

			pc += 4;
		}
		else {
			if save_breaker {
				println!("<U16>0x{lo:04x}     ; {pc:3}: {instruction}");
			}
			else {
				println!("0x{lo:04x}        # {pc:3}: {instruction}");
			}

			pc += 2;
		}
	}

	Ok(())
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> (std::path::PathBuf, riscv::SupportedExtensions, bool) {
	let mut path = None;
	let mut supported_extensions = riscv::SupportedExtensions::RV32I;
	let mut save_breaker = false;

	for opt in &mut args {
		match opt.to_str() {
			Some("--help") => {
				write_usage(std::io::stdout(), argv0);
				std::process::exit(0);
			},

			Some("--") => {
				path = args.next();
				break;
			},

			Some("-c" | "--compressed" | "--compressed=true") => supported_extensions |= riscv::SupportedExtensions::RVC,

			Some("--compressed=false") => supported_extensions &= !riscv::SupportedExtensions::ZCB,

			Some("--compressed=Zcb") => supported_extensions |= riscv::SupportedExtensions::ZCB,

			Some("--save-breaker" | "--sb") => save_breaker = true,

			Some("--32") => supported_extensions &= !riscv::SupportedExtensions::RV64I,

			Some("--64") => supported_extensions |= riscv::SupportedExtensions::RV64I,

			_ if path.is_none() => path = Some(opt),

			_ => write_usage_and_crash(argv0),
		}
	}

	let None = args.next() else { write_usage_and_crash(argv0); };

	let Some(path) = path else { write_usage_and_crash(argv0); };
	(path.into(), supported_extensions, save_breaker)
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} [ --32 | --64 ] [ -c | --compressed | --compressed=[true|false|Zcb] ] [ --sb | --save-breaker ] [ -- ] <program.S>", argv0.to_string_lossy());
}
