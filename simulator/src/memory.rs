pub(crate) struct Memory {
	ram: Vec<u8>,
	program: Vec<u8>,
	in_file: Vec<u8>,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum LoadOp {
	Byte,
	ByteUnsigned,
	HalfWord,
	HalfWordUnsigned,
	Word,
	WordUnsigned,
	DoubleWord,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum StoreOp {
	Byte,
	HalfWord,
	Word,
	DoubleWord,
}

impl Memory {
	pub(crate) fn new(
		program_path: impl AsRef<std::path::Path>,
		in_file_path: impl AsRef<std::path::Path>,
	) -> Self {
		let program = std::fs::read(program_path).unwrap();
		let in_file = std::fs::read(in_file_path).unwrap();
		Self {
			ram: vec![],
			program,
			in_file,
		}
	}

	pub(crate) fn dump_console(&self) {
		println!("{}", Console(self.ram.get(0x400_000..).unwrap_or_default()));
	}
}

impl LoadOp {
	pub(crate) fn exec(self, memory: &Memory, address: i64) -> i64 {
		let address = address.cast_unsigned();

		match self {
			Self::Byte | Self::ByteUnsigned => (),
			Self::HalfWord | Self::HalfWordUnsigned => assert!(address % 2 == 0, "0x{address:016x} is not aligned for reading a halfword"),
			Self::Word | Self::WordUnsigned => assert!(address % 4 == 0, "0x{address:016x} is not aligned for reading a word"),
			Self::DoubleWord => assert!(address % 8 == 0, "0x{address:016x} is not aligned for reading a doubleword"),
		}

		let data = match address {
			0xffff_ffff_ffe0_0000..=0xffff_ffff_ffef_ffff => {
				// in_file
				let address = usize::try_from(address - 0xffff_ffff_ffe0_0000).unwrap();
				[
					memory.in_file.get(address).copied().unwrap_or_default(),
					memory.in_file.get(address + 1).copied().unwrap_or_default(),
					memory.in_file.get(address + 2).copied().unwrap_or_default(),
					memory.in_file.get(address + 3).copied().unwrap_or_default(),
					memory.in_file.get(address + 4).copied().unwrap_or_default(),
					memory.in_file.get(address + 5).copied().unwrap_or_default(),
					memory.in_file.get(address + 6).copied().unwrap_or_default(),
					memory.in_file.get(address + 7).copied().unwrap_or_default(),
				]
			},

			0x8000_0000_0000_0000..=0xffff_ffff_ffff_ffff => {
				// program
				let address = usize::try_from(address - 0x8000_0000_0000_0000).unwrap();
				[
					memory.program.get(address).copied().unwrap_or_default(),
					memory.program.get(address + 1).copied().unwrap_or_default(),
					memory.program.get(address + 2).copied().unwrap_or_default(),
					memory.program.get(address + 3).copied().unwrap_or_default(),
					memory.program.get(address + 4).copied().unwrap_or_default(),
					memory.program.get(address + 5).copied().unwrap_or_default(),
					memory.program.get(address + 6).copied().unwrap_or_default(),
					memory.program.get(address + 7).copied().unwrap_or_default(),
				]
			},

			0x0000_0000_0000_0000..=0x0000_0000_0400_1fff => {
				// ram
				let address = usize::try_from(address).unwrap();
				[
					memory.ram.get(address).copied().unwrap_or_default(),
					memory.ram.get(address + 1).copied().unwrap_or_default(),
					memory.ram.get(address + 2).copied().unwrap_or_default(),
					memory.ram.get(address + 3).copied().unwrap_or_default(),
					memory.ram.get(address + 4).copied().unwrap_or_default(),
					memory.ram.get(address + 5).copied().unwrap_or_default(),
					memory.ram.get(address + 6).copied().unwrap_or_default(),
					memory.ram.get(address + 7).copied().unwrap_or_default(),
				]
			},

			address => panic!("EFAULT: 0x{address:016x} is unmapped"),
		};

		match self {
			Self::Byte => i8::from_le_bytes([data[0]]).into(),
			Self::ByteUnsigned => u64::from(u8::from_le_bytes([data[0]])).cast_signed(),
			Self::HalfWord => i16::from_le_bytes([data[0], data[1]]).into(),
			Self::HalfWordUnsigned => u64::from(u16::from_le_bytes([data[0], data[1]])).cast_signed(),
			Self::Word => i32::from_le_bytes([data[0], data[1], data[2], data[3]]).into(),
			Self::WordUnsigned => u64::from(u32::from_le_bytes([data[0], data[1], data[2], data[3]])).cast_signed(),
			Self::DoubleWord => i64::from_le_bytes(data),
		}
	}
}

impl TryFrom<u8> for LoadOp {
	type Error = ();

	fn try_from(funct3: u8) -> Result<Self, Self::Error> {
		Ok(match funct3 {
			0b000 => Self::Byte,
			0b001 => Self::HalfWord,
			0b010 => Self::Word,
			0b011 => Self::DoubleWord,
			0b100 => Self::ByteUnsigned,
			0b101 => Self::HalfWordUnsigned,
			0b110 => Self::WordUnsigned,
			_ => return Err(()),
		})
	}
}

impl StoreOp {
	pub(crate) fn exec(self, memory: &mut Memory, address: i64, value: i64) {
		let address = address.cast_unsigned();

		match self {
			Self::Byte => (),
			Self::HalfWord => assert!(address % 2 == 0, "0x{address:016x} is not aligned for writing a halfword"),
			Self::Word => assert!(address % 4 == 0, "0x{address:016x} is not aligned for writing a word"),
			Self::DoubleWord => assert!(address % 8 == 0, "0x{address:016x} is not aligned for writing a doubleword"),
		}

		let data: &mut [u8; 8] = match address {
			0xffff_ffff_ffe0_0000..=0xffff_ffff_ffef_ffff => {
				// in_file
				panic!("EFAULT: 0x{address:016x} is readonly");
			},

			0x8000_0000_0000_0000..=0xffff_ffff_ffff_ffff => {
				// program
				panic!("EFAULT: 0x{address:016x} is readonly");
			},

			0x0000_0000_0000_0000..=0x0000_0000_0400_1fff => {
				// ram
				let address = usize::try_from(address).unwrap();
				if let Some(raw) = memory.ram.get_mut(address..).and_then(|s| s.first_chunk_mut()) {
					raw
				}
				else {
					memory.ram.resize(address + 8, 0_u8);
					memory.ram[address..].first_chunk_mut().unwrap()
				}
			},

			address => panic!("EFAULT: 0x{address:016x} is unmapped"),
		};

		let copy_len = match self {
			Self::Byte => 1,
			Self::HalfWord => 2,
			Self::Word => 4,
			Self::DoubleWord => 8,
		};
		data[..copy_len].copy_from_slice(&value.to_le_bytes()[..copy_len]);
	}
}

impl TryFrom<u8> for StoreOp {
	type Error = ();

	fn try_from(funct3: u8) -> Result<Self, Self::Error> {
		Ok(match funct3 {
			0b000 => Self::Byte,
			0b001 => Self::HalfWord,
			0b010 => Self::Word,
			0b011 => Self::DoubleWord,
			_ => return Err(()),
		})
	}
}

struct Console<'a>(&'a [u8]);

impl std::fmt::Display for Console<'_> {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		fn write_line(f: &mut std::fmt::Formatter<'_>, line: &[u8]) -> std::fmt::Result {
			for &c in line {
				match c {
					b'\0' => write!(f, " ")?,
					b'a'..=b'z' |
					b'A'..=b'Z' |
					b'0'..=b'9' |
					b' ' | b'.' | b',' | b';' | b':' | b'-' | b'_' |
					b'\'' | b'"' | b'`' | b'=' |
					b'(' | b')' | b'<' | b'>'
						=> write!(f, "{}", char::from(c))?,

					_
						=> write!(f, "0x{c:02x}")?,
				}
			}

			Ok(())
		}

		let mut lines = self.0.chunks_exact(80);
		let mut first = true;
		for line in &mut lines {
			if first {
				first = false;
			}
			else {
				writeln!(f)?;
			}

			write_line(f, line)?;
		}

		if !first {
			writeln!(f)?;
		}

		write_line(f, lines.remainder())?;

		Ok(())
	}
}
