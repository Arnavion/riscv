fn main() -> Result<(), Box<dyn std::error::Error>> {
	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let path = parse_args(args, &argv0);

	let program = std::fs::read_to_string(path)?;

	let mut pc = 0_u64;

	for instruction in riscv::parse_program(&program) {
		let instruction = instruction.map_err(|err| err.to_string())?;
		let encoded =
			instruction.encode()
			.map_err(|err| format!("instruction could not be encoded {instruction:?}: {err}"))?;
		println!("0x{encoded:08x}  # {pc:3}: {instruction}");

		pc += 4;
	}

	Ok(())
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> std::path::PathBuf {
	let mut path = None;

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

			_ if path.is_none() => path = Some(opt),

			_ => write_usage_and_crash(argv0),
		}
	}

	let None = args.next() else { write_usage_and_crash(argv0); };

	let Some(path) = path else { write_usage_and_crash(argv0); };
	path.into()
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} [ -- ] <program.S>", argv0.to_string_lossy());
}
