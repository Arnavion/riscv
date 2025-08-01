use crate::{EncodeError, instruction::Imm, ParseError};

macro_rules! registers {
	(
		$vis:vis enum $ty:ident {
			$($variant:ident = $asm:literal $(, $asm_alt:literal)* => $encoded:literal ,)*
		}
	) => {
		#[derive(Clone, Copy, Debug, Eq, PartialEq)]
		$vis enum $ty {
			$($variant ,)*
		}

		impl $ty {
			$vis const fn encode_5b(self) -> u32 {
				match self {
					$(Self::$variant => $encoded ,)*
				}
			}
		}

		impl core::fmt::Display for $ty {
			fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
				match self {
					$(Self::$variant => f.write_str($asm),)*
				}
			}
		}

		impl<'a> TryFrom<&'a [u8]> for $ty {
			type Error = ParseError<'a>;

			fn try_from(token: &'a [u8]) -> Result<Self, Self::Error> {
				let token = core::str::from_utf8(token).map_err(|_| crate::ParseError::InvalidUtf8 { token })?;

				Ok(match token {
					$($asm $(| $asm_alt)* => Self::$variant,)*

					_ => return Err(crate::ParseError::MalformedRegister { token } ),
				})
			}
		}
	};
}

registers! {
	pub enum Register {
		X0 = "x0", "zero" => 0b00000,
		X1 = "x1", "ra" => 0b00001,
		X2 = "x2", "sp" => 0b00010,
		X3 = "x3", "gp" => 0b00011,
		X4 = "x4", "tp" => 0b00100,
		X5 = "x5", "t0" => 0b00101,
		X6 = "x6", "t1" => 0b00110,
		X7 = "x7", "t2" => 0b00111,
		X8 = "x8", "s0", "fp" => 0b01000,
		X9 = "x9", "s1" => 0b01001,
		X10 = "x10", "a0" => 0b01010,
		X11 = "x11", "a1" => 0b01011,
		X12 = "x12", "a2" => 0b01100,
		X13 = "x13", "a3" => 0b01101,
		X14 = "x14", "a4" => 0b01110,
		X15 = "x15", "a5" => 0b01111,
		X16 = "x16", "a6" => 0b10000,
		X17 = "x17", "a7" => 0b10001,
		X18 = "x18", "s2" => 0b10010,
		X19 = "x19", "s3" => 0b10011,
		X20 = "x20", "s4" => 0b10100,
		X21 = "x21", "s5" => 0b10101,
		X22 = "x22", "s6" => 0b10110,
		X23 = "x23", "s7" => 0b10111,
		X24 = "x24", "s8" => 0b11000,
		X25 = "x25", "s9" => 0b11001,
		X26 = "x26", "s10" => 0b11010,
		X27 = "x27", "s11" => 0b11011,
		X28 = "x28", "t3" => 0b11100,
		X29 = "x29", "t4" => 0b11101,
		X30 = "x30", "t5" => 0b11110,
		X31 = "x31", "t6" => 0b11111,

		// RV{32,64}{F,D,Q}
		F0 = "f0", "ft0" => 0b00000,
		F1 = "f1", "ft1" => 0b00001,
		F2 = "f2", "ft2" => 0b00010,
		F3 = "f3", "ft3" => 0b00011,
		F4 = "f4", "ft4" => 0b00100,
		F5 = "f5", "ft5" => 0b00101,
		F6 = "f6", "ft6" => 0b00110,
		F7 = "f7", "ft7" => 0b00111,
		F8 = "f8", "fs0" => 0b01000,
		F9 = "f9", "fs1" => 0b01001,
		F10 = "f10", "fa0" => 0b01010,
		F11 = "f11", "fa1" => 0b01011,
		F12 = "f12", "fa2" => 0b01100,
		F13 = "f13", "fa3" => 0b01101,
		F14 = "f14", "fa4" => 0b01110,
		F15 = "f15", "fa5" => 0b01111,
		F16 = "f16", "fa6" => 0b10000,
		F17 = "f17", "fa7" => 0b10001,
		F18 = "f18", "fs2" => 0b10010,
		F19 = "f19", "fs3" => 0b10011,
		F20 = "f20", "fs4" => 0b10100,
		F21 = "f21", "fs5" => 0b10101,
		F22 = "f22", "fs6" => 0b10110,
		F23 = "f23", "fs7" => 0b10111,
		F24 = "f24", "fs8" => 0b11000,
		F25 = "f25", "fs9" => 0b11001,
		F26 = "f26", "fs10" => 0b11010,
		F27 = "f27", "fs11" => 0b11011,
		F28 = "f28", "ft8" => 0b11100,
		F29 = "f29", "ft9" => 0b11101,
		F30 = "f30", "ft10" => 0b11110,
		F31 = "f31", "ft11" => 0b11111,
	}
}

impl Register {
	pub(crate) const fn encode_rd_5b(self) -> u32 {
		self.encode_5b() << 7
	}

	pub(crate) const fn encode_rs1_5b(self) -> u32 {
		self.encode_5b() << 15
	}

	pub(crate) const fn encode_rs2_5b(self) -> u32 {
		self.encode_5b() << 20
	}

	pub(crate) const fn is_compressible(self) -> bool {
		matches!(
			self,
			Self::X8 |
			Self::X9 |
			Self::X10 |
			Self::X11 |
			Self::X12 |
			Self::X13 |
			Self::X14 |
			Self::X15,
		)
	}

	pub(crate) fn encode_3b(self) -> Result<u32, EncodeError> {
		Ok(match self {
			Self::X8 => 0b000,
			Self::X9 => 0b001,
			Self::X10 => 0b010,
			Self::X11 => 0b011,
			Self::X12 => 0b100,
			Self::X13 => 0b101,
			Self::X14 => 0b110,
			Self::X15 => 0b111,
			_ => return Err(EncodeError::IncompressibleRegister),
		})
	}
}

macro_rules! csr {
	(
		$vis:vis enum $ty:ident {
			$($variant:ident = $asm:literal => $encoded:literal ,)*
		}
	) => {
		#[derive(Clone, Copy, Debug, Eq, PartialEq)]
		$vis enum $ty {
			$($variant ,)*

			Other(u16),
		}

		impl $ty {
			$vis fn encode_12b(self) -> u32 {
				match self {
					$(Self::$variant => $encoded << 20,)*

					Self::Other(encoded) => u32::from(encoded) << 20,
				}
			}
		}

		impl core::fmt::Display for $ty {
			fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
				match self {
					$(Self::$variant => f.write_str($asm),)*

					Self::Other(encoded) => write!(f, "{encoded}"),
				}
			}
		}

		impl<'a> TryFrom<&'a [u8]> for $ty {
			type Error = ParseError<'a>;

			fn try_from(token: &'a [u8]) -> Result<Self, Self::Error> {
				if let Ok(Imm(encoded)) = token.try_into() {
					let encoded = encoded.try_into().map_err(|_| crate::ParseError::MalformedIntegerCsr { token })?;
					Ok(Self::Other(encoded))
				}
				else {
					let token = core::str::from_utf8(token).map_err(|_| crate::ParseError::InvalidUtf8 { token })?;

					Ok(match token {
						$($asm => Self::$variant,)*

						_ => return Err(crate::ParseError::MalformedRegister { token }),
					})
				}
			}
		}
	};
}

csr! {
	pub enum Csr {
		Cycle = "cycle" => 0xc00,
		CycleH = "cycleh" => 0xc80,
		InstRet = "instret" => 0xc02,
		InstRetH = "instreth" => 0xc82,
		Misa = "misa" => 0x301,
		Time = "time" => 0xc01,
		TimeH = "timeh" => 0xc81,
	}
}
