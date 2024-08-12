#![allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]

use crate::{EncodeError, ParseError, Register};

macro_rules! instructions {
	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ }
	) => {
		#[derive(Clone, Copy, Debug)]
		$vis enum $ty {
			$($variants)*
		}

		impl $ty {
			$vis fn encode($self) -> Result<u32, EncodeError> {
				let raw_instruction = match $self {
					$($encode_arms)*
				};

				raw_instruction.encode()
			}

			$vis fn parse($parse_line: &str) -> Result<Option<Self>, ParseError<'_>> {
				let mut $parse_tokens = tokens($parse_line.as_bytes());

				let Some(token) = $parse_tokens.next() else {
					return Ok(None);
				};
				let token = core::str::from_utf8(token).map_err(|_| ParseError::MalformedInstruction { line: $parse_line })?;

				Ok(Some(match token {
					$($parse_arms)*
					_ => return Err(ParseError::UnknownInstruction { line: $parse_line }),
				}))
			}
		}

		impl core::fmt::Display for $ty {
			fn fmt(&self, $f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
				match self {
					$($display_arms)*
				}
			}
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[r( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, src1: Register, src2: Register }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, src1: Register, src2: Register },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, src1, src2 } => RawInstruction::R {
					opcode: OpCode::$opcode,
					rd: dest,
					funct3: Funct3::$variant,
					rs1: src1,
					rs2: src2,
					funct7: Funct7::$variant,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let src1 = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src1 = src1.try_into()?;

					let src2 = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src2 = src2.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, src1, src2 }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, src1, src2 } => write!($f, concat!($asm, " {}, {}, {}"), dest, src1, src2),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant,
			}
			{
				$self
				$($encode_arms)*
				Self::$variant => RawInstruction::I {
					opcode: OpCode::$opcode,
					rd: Register::X0,
					funct3: Funct3::$variant,
					rs1: Register::X0,
					imm: Func12::$variant.encode() as _,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant => $f.write_str($asm),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, src: Register, imm: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, src: Register, imm: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, src, imm } => RawInstruction::I {
					opcode: OpCode::$opcode,
					rd: dest,
					funct3: Funct3::$variant,
					rs1: src,
					imm,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let src = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src = src.try_into()?;

					let imm = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(imm) = imm.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, src, imm }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, src, imm } => write!($f, concat!($asm, " {}, {}, {}"), dest, src, imm),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, src: Register, shamt: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, src: Register, shamt: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, src, shamt } => {
					// shamt is always treated as positive
					assert!(shamt & ((1 << 5) - 1) == shamt, "shamt overflow in {:?}: 0x{shamt:08x}", $self);
					RawInstruction::I {
						opcode: OpCode::$opcode,
						rd: dest,
						funct3: Funct3::$variant,
						rs1: src,
						imm: (shamt as u32 | (Funct7::$variant.encode() << 5)) as i32,
					}
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let src = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src = src.try_into()?;

					let shamt = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(shamt) = shamt.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, src, shamt }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, src, shamt } => write!($f, concat!($asm, " {}, {}, {}"), dest, src, shamt),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, base: Register, offset: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, base: Register, offset: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, base, offset } => RawInstruction::I {
					opcode: OpCode::$opcode,
					rd: dest,
					funct3: Funct3::$variant,
					rs1: base,
					imm: offset,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let Some((base, offset)) = parse_base_and_offset(&mut $parse_tokens) else {
						return Err(ParseError::MalformedInstruction { line: $parse_line });
					};

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, base, offset }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, base, offset } => write!($f, concat!($asm, " {}, {}({})"), dest, offset, base),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[s( $asm:tt , $opcode:tt )] $variant:tt { base: Register, offset: i32, src: Register }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { base: Register, offset: i32, src: Register },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { base, offset, src } => RawInstruction::S {
					opcode: OpCode::$opcode,
					funct3: Funct3::$variant,
					rs1: base,
					rs2: src,
					imm: offset,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let src = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src = src.try_into()?;

					let Some((base, offset)) = parse_base_and_offset(&mut $parse_tokens) else {
						return Err(ParseError::MalformedInstruction { line: $parse_line });
					};

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { base, offset, src }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { base, offset, src } => write!($f, concat!($asm, " {}, {}({})"), src, offset, base),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[b( $asm:tt , $opcode:tt )] $variant:tt { src1: Register, src2: Register, offset: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { src1: Register, src2: Register, offset: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { src1, src2, offset } => RawInstruction::B {
					opcode: OpCode::$opcode,
					funct3: Funct3::$variant,
					rs1: src1,
					rs2: src2,
					imm: offset,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let src1 = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src1 = src1.try_into()?;

					let src2 = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src2 = src2.try_into()?;

					let offset = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(offset) = offset.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { src1, src2, offset }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { src1, src2, offset } => write!($f, concat!($asm, " {}, {}, {}"), src1, src2, offset),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[u( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, imm: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, imm: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, imm } => RawInstruction::U {
					opcode: OpCode::$opcode,
					rd: dest,
					imm,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let imm = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(imm) = imm.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, imm }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, imm } => write!($f, concat!($asm, " {}, {}"), dest, imm),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[j( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, offset: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, offset: i32 },
			}
			{
				$self
				$($encode_arms)*
				Self::$variant { dest, offset } => RawInstruction::J {
					opcode: OpCode::$opcode,
					rd: dest,
					imm: offset,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let offset = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(offset) = offset.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, offset }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, offset } => write!($f, concat!($asm, " {}, {}"), dest, offset),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ Fence { predecessor_set: FenceSet, successor_set: FenceSet }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				Fence { predecessor_set: FenceSet, successor_set: FenceSet },
			}
			{
				$self
				$($encode_arms)*
				Self::Fence { predecessor_set, successor_set } => RawInstruction::Fence {
					fm: FenceFm::None,
					predecessor_set,
					successor_set,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				"fence" => {
					let (predecessor_set, successor_set) =
						if let Some(predecessor_set) = $parse_tokens.next() {
							let predecessor_set = predecessor_set.try_into()?;

							let successor_set = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
							let successor_set = successor_set.try_into()?;

							if $parse_tokens.next().is_some() {
								return Err(ParseError::TrailingGarbage { line: $parse_line });
							}

							(
								predecessor_set,
								successor_set,
							)
						}
						else {
							(
								FenceSet::RW,
								FenceSet::RW,
							)
						};
					Self::Fence { predecessor_set, successor_set }
				},
			}
			{
				$f
				$($display_arms)*
				Self::Fence { predecessor_set, successor_set } => write!($f, "fence {predecessor_set}, {successor_set}"),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ FenceTso, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				FenceTso,
			}
			{
				$self
				$($encode_arms)*
				Self::FenceTso => RawInstruction::Fence {
					fm: FenceFm::Tso,
					predecessor_set: FenceSet::RW,
					successor_set: FenceSet::RW,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				"fence.tso" => {
					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::FenceTso
				},
			}
			{
				$f
				$($display_arms)*
				Self::FenceTso => $f.write_str("fence.tso"),
			}
			{ $($rest)* }
		}
	};

	($vis:vis enum $ty:ident { $($rest:tt)* }) => {
		instructions! {
			@inner
			$vis
			$ty
			{ }
			{ self }
			{ line rest }
			{ f }
			{ $($rest)* }
		}
	};
}

instructions! {
	pub enum Instruction {
		#[r("add", Op)]
		Add { dest: Register, src1: Register, src2: Register },

		#[i("addi", OpImm)]
		Addi { dest: Register, src: Register, imm: i32 },

		#[r("and", Op)]
		And { dest: Register, src1: Register, src2: Register },

		#[i("andi", OpImm)]
		Andi { dest: Register, src: Register, imm: i32 },

		#[u("auipc", Auipc)]
		Auipc { dest: Register, imm: i32 },

		#[b("beq", Branch)]
		Beq { src1: Register, src2: Register, offset: i32 },

		#[b("bge", Branch)]
		Bge { src1: Register, src2: Register, offset: i32 },

		#[b("bgeu", Branch)]
		Bgeu { src1: Register, src2: Register, offset: i32 },

		#[b("blt", Branch)]
		Blt { src1: Register, src2: Register, offset: i32 },

		#[b("bltu", Branch)]
		Bltu { src1: Register, src2: Register, offset: i32 },

		#[b("bne", Branch)]
		Bne { src1: Register, src2: Register, offset: i32 },

		#[i("ebreak", System)]
		EBreak,

		#[i("ecall", System)]
		ECall,

		Fence { predecessor_set: FenceSet, successor_set: FenceSet },

		FenceTso,

		#[j("jal", Jal)]
		Jal { dest: Register, offset: i32 },

		#[i("jalr", Jalr)]
		Jalr { dest: Register, base: Register, offset: i32 },

		#[i("lb", Load)]
		Lb { dest: Register, base: Register, offset: i32 },

		#[i("lbu", Load)]
		Lbu { dest: Register, base: Register, offset: i32 },

		#[i("lh", Load)]
		Lh { dest: Register, base: Register, offset: i32 },

		#[i("lhu", Load)]
		Lhu { dest: Register, base: Register, offset: i32 },

		#[u("lui", Lui)]
		Lui { dest: Register, imm: i32 },

		#[i("lw", Load)]
		Lw { dest: Register, base: Register, offset: i32 },

		#[r("or", Op)]
		Or { dest: Register, src1: Register, src2: Register },

		#[i("ori", OpImm)]
		Ori { dest: Register, src: Register, imm: i32 },

		#[s("sb", Store)]
		Sb { base: Register, offset: i32, src: Register },

		#[s("sh", Store)]
		Sh { base: Register, offset: i32, src: Register },

		#[r("sll", Op)]
		Sll { dest: Register, src1: Register, src2: Register },

		#[i("slli", OpImm)]
		Slli { dest: Register, src: Register, shamt: i32 },

		#[r("slt", Op)]
		Slt { dest: Register, src1: Register, src2: Register },

		#[i("slti", OpImm)]
		Slti { dest: Register, src: Register, imm: i32 },

		#[i("sltiu", OpImm)]
		Sltiu { dest: Register, src: Register, imm: i32 },

		#[r("sltu", Op)]
		Sltu { dest: Register, src1: Register, src2: Register },

		#[r("sra", Op)]
		Sra { dest: Register, src1: Register, src2: Register },

		#[i("srai", OpImm)]
		Srai { dest: Register, src: Register, shamt: i32 },

		#[r("srl", Op)]
		Srl { dest: Register, src1: Register, src2: Register },

		#[i("srli", OpImm)]
		Srli { dest: Register, src: Register, shamt: i32 },

		#[r("sub", Op)]
		Sub { dest: Register, src1: Register, src2: Register },

		#[s("sw", Store)]
		Sw { base: Register, offset: i32, src: Register },

		#[r("xor", Op)]
		Xor { dest: Register, src1: Register, src2: Register },

		#[i("xori", OpImm)]
		Xori { dest: Register, src: Register, imm: i32 },
	}
}

struct Tokens<'a> {
	line: &'a [u8],
}

impl<'a> Iterator for Tokens<'a> {
	type Item = &'a [u8];

	fn next(&mut self) -> Option<Self::Item> {
		while let Some((&c, rest)) = self.line.split_first() {
			match c {
				c if c.is_ascii_whitespace() => self.line = rest,

				b',' => self.line = rest,

				b'(' | b')' => {
					let result = &self.line[..(self.line.len() - rest.len())];
					self.line = rest;
					return Some(result);
				},

				b'#' => break,

				_ => {
					let start = self.line;
					self.line = rest;
					loop {
						match self.line.split_first() {
							Some((c, _)) if c.is_ascii_whitespace() => {
								let result = &start[..(start.len() - self.line.len())];
								return Some(result);
							},

							Some((&b',' | &b'(' | &b')' | &b'#', _)) | None => {
								let result = &start[..(start.len() - self.line.len())];
								return Some(result);
							},

							Some((_, rest)) => self.line = rest,
						}
					}
				},
			}
		}

		None
	}
}

pub(crate) fn tokens(line: &[u8]) -> impl Iterator<Item = &[u8]> {
	Tokens { line }
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct Imm(pub(crate) i32);

impl<'a> TryFrom<&'a [u8]> for Imm {
	type Error = ParseError<'a>;

	fn try_from(token: &'a [u8]) -> Result<Self, Self::Error> {
		struct Buf<const N: usize> {
			inner: [core::mem::MaybeUninit<u8>; N],
			len: usize,
		}

		impl<const N: usize> Buf<N> {
			fn new(token: &[u8]) -> Result<Self, ParseError<'_>> {
				let mut result = Self {
					inner: [core::mem::MaybeUninit::uninit(); N],
					len: 0,
				};

				for &b in token {
					if b != b'_' {
						result.inner.get_mut(result.len).ok_or(ParseError::MalformedImmediate { token })?.write(b);
						result.len += 1;
					}
				}

				Ok(result)
			}
		}

		impl<const N: usize> AsRef<[u8]> for Buf<N> {
			fn as_ref(&self) -> &[u8] {
				unsafe {
					// TODO(rustup): Use `MaybeUninit::slice_assume_init_ref` when that is stabilized.
					&*(core::ptr::from_ref(&self.inner[..self.len]) as *const [u8])
				}
			}
		}

		Ok(Imm(
			if let Some(token_) = token.strip_prefix(b"0b") {
				let buf = Buf::<64>::new(token_)?;
				let token_ = core::str::from_utf8(buf.as_ref()).map_err(|_| ParseError::InvalidUtf8 { token })?;
				i32::from_str_radix(token_, 2).map_err(|_| ParseError::MalformedImmediate { token })?
			}
			else if let Some(token_) = token.strip_prefix(b"-0b") {
				let buf = Buf::<64>::new(token_)?;
				let token_ = core::str::from_utf8(buf.as_ref()).map_err(|_| ParseError::InvalidUtf8 { token })?;
				-i32::from_str_radix(token_, 2).map_err(|_| ParseError::MalformedImmediate { token })?
			}
			else if let Some(token_) = token.strip_prefix(b"0x") {
				let buf = Buf::<64>::new(token_)?;
				let token_ = core::str::from_utf8(buf.as_ref()).map_err(|_| ParseError::InvalidUtf8 { token })?;
				// gas requires being able to parse a negative integer specified as positive hex
				u32::from_str_radix(token_, 16).map_err(|_| ParseError::MalformedImmediate { token })? as _
			}
			else if let Some(token_) = token.strip_prefix(b"-0x") {
				let buf = Buf::<64>::new(token_)?;
				let token_ = core::str::from_utf8(buf.as_ref()).map_err(|_| ParseError::InvalidUtf8 { token })?;
				-i32::from_str_radix(token_, 16).map_err(|_| ParseError::MalformedImmediate { token })?
			}
			else {
				let buf = Buf::<64>::new(token)?;
				let token_ = core::str::from_utf8(buf.as_ref()).map_err(|_| ParseError::InvalidUtf8 { token })?;
				token_.parse().map_err(|_| ParseError::MalformedImmediate { token })?
			}
		))
	}
}

fn parse_base_and_offset<'a>(tokens: &mut impl Iterator<Item = &'a [u8]>) -> Option<(Register, i32)> {
	let token1 = tokens.next()?;
	if let Ok(Imm(offset)) = token1.try_into() {
		let token2 = tokens.next()?;
		if let b"(" = token2 {
			let base = tokens.next()?;
			let base = base.try_into().ok()?;

			let b")" = tokens.next()? else { return None; };

			Some((base, offset))
		}
		else {
			let base = token2.try_into().ok()?;

			Some((base, offset))
		}
	}
	else if let b"(" = token1 {
		let offset = 0;

		let base = tokens.next()?;
		let base = base.try_into().ok()?;

		let b")" = tokens.next()? else { return None; };

		Some((base, offset))
	}
	else {
		let base = token1.try_into().ok()?;

		let offset = tokens.next()?;
		let Imm(offset) = offset.try_into().ok()?;

		Some((base, offset))
	}
}

#[derive(Clone, Copy, Debug)]
enum RawInstruction {
	R {
		opcode: OpCode,
		rd: Register,
		funct3: Funct3,
		rs1: Register,
		rs2: Register,
		funct7: Funct7,
	},

	I {
		opcode: OpCode,
		rd: Register,
		funct3: Funct3,
		rs1: Register,
		imm: i32,
	},

	S {
		opcode: OpCode,
		funct3: Funct3,
		rs1: Register,
		rs2: Register,
		imm: i32,
	},

	B {
		opcode: OpCode,
		funct3: Funct3,
		rs1: Register,
		rs2: Register,
		imm: i32,
	},

	U {
		opcode: OpCode,
		rd: Register,
		imm: i32,
	},

	J {
		opcode: OpCode,
		rd: Register,
		imm: i32,
	},

	Fence {
		fm: FenceFm,
		predecessor_set: FenceSet,
		successor_set: FenceSet,
	},
}

impl RawInstruction {
	fn encode(self) -> Result<u32, EncodeError> {
		let encoded = match self {
			Self::R { opcode, rd, funct3, rs1, rs2, funct7 } =>
				opcode.encode() |
					rd.encode_rd() |
					(funct3.encode() << 12) |
					rs1.encode_rs1() |
					rs2.encode_rs2() |
					(funct7.encode() << 25),

			Self::I { opcode, rd, funct3, rs1, imm } => {
				if !can_truncate_high::<12>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				opcode.encode() |
					rd.encode_rd() |
					(funct3.encode() << 12) |
					rs1.encode_rs1() |
					(bit_slice::<0, 12>(imm) << 20)
			},

			Self::S { opcode, funct3, rs1, rs2, imm } => {
				if !can_truncate_high::<12>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				opcode.encode() |
					(bit_slice::<0, 5>(imm) << 7) |
					(funct3.encode() << 12) |
					rs1.encode_rs1() |
					rs2.encode_rs2() |
					(bit_slice::<5, 12>(imm) << 25)
			},

			Self::B { opcode, funct3, rs1, rs2, imm } => {
				if !can_truncate_low::<1>(imm) || !can_truncate_high::<13>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				opcode.encode() |
					(bit_slice::<11, 12>(imm) << 7) |
					(bit_slice::<1, 5>(imm) << 8) |
					(funct3.encode() << 12) |
					rs1.encode_rs1() |
					rs2.encode_rs2() |
					(bit_slice::<5, 11>(imm) << 25) |
					(bit_slice::<12, 13>(imm) << 31)
			},

			Self::U { opcode, rd, imm } => {
				let imm =
					if can_truncate_high::<20>(imm) || (imm as u32 & 0xfff0_0000) == 0 {
						bit_slice::<0, 20>(imm) << 12
					}
					else {
						return Err(EncodeError::ImmediateOverflow);
					};

				opcode.encode() |
					rd.encode_rd() |
					imm
			},

			Self::J { opcode, rd, imm } => {
				if !can_truncate_low::<1>(imm) || !can_truncate_high::<21>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				opcode.encode() |
					rd.encode_rd() |
					(bit_slice::<12, 20>(imm) << 12) |
					(bit_slice::<11, 12>(imm) << 20) |
					(bit_slice::<1, 11>(imm) << 21) |
					(bit_slice::<20, 21>(imm) << 31)
			},

			Self::Fence { fm, predecessor_set, successor_set } =>
				OpCode::MiscMem.encode() |
					(fm.encode() << 28) |
					(predecessor_set.encode() << 24) |
					(successor_set.encode() << 20),
		};
		Ok(encoded)
	}
}

#[derive(Clone, Copy, Debug)]
#[repr(u8)]
enum OpCode {
	Auipc = 0b00101,
	Branch = 0b11000,
	Jal = 0b11011,
	Jalr = 0b11001,
	Load = 0b00000,
	Lui = 0b01101,
	MiscMem = 0b00011,
	Op = 0b01100,
	OpImm = 0b00100,
	Store = 0b01000,
	System = 0b11100,

	// RV64I
	/*
	Op32 = 0b01110,
	OpImm32 = 0b00110,
	*/

	// RV{32,64}A
	/*
	Amo = 0b01011,
	*/

	// RV{32,64}{F,D,Q}
	/*
	LoadFp = 0b00001,
	Madd = 0b10000,
	Msub = 0b10001,
	Nmadd = 0b10011,
	Nmsub = 0b10010,
	OpFp = 0b10100,
	StoreFp = 0b01001,
	*/
}

impl OpCode {
	const fn encode(self) -> u32 {
		const LENGTH_SUFFIX_FIXED_32_BITS: u32 = 0b11;

		(self as u32) << 2 | LENGTH_SUFFIX_FIXED_32_BITS
	}
}

macro_rules! funct {
	(
		$vis:vis enum $ty:ident {
			$($variant:ident = $encoded:literal ,)*
		}
	) => {
		#[derive(Clone, Copy, Debug)]
		$vis enum $ty {
			$($variant ,)*
		}

		impl $ty {
			const fn encode(self) -> u32 {
				match self {
					$(Self::$variant => $encoded ,)*
				}
			}
		}
	};
}

funct! {
	enum Funct3 {
		Add = 0b000,
		Addi = 0b000,
		And = 0b111,
		Andi = 0b111,
		Beq = 0b000,
		Bge = 0b101,
		Bgeu = 0b111,
		Blt = 0b100,
		Bltu = 0b110,
		Bne = 0b001,
		EBreak = 0b000,
		ECall = 0b000,
		Jalr = 0b000,
		Lb = 0b000,
		Lbu = 0b100,
		Lh = 0b001,
		Lhu = 0b101,
		Lw = 0b010,
		Or = 0b110,
		Ori = 0b110,
		Sb = 0b000,
		Sh = 0b001,
		Sll = 0b001,
		Slli = 0b001,
		Slt = 0b010,
		Slti = 0b010,
		Sltiu = 0b011,
		Sltu = 0b011,
		Sra = 0b101,
		Srai = 0b101,
		Srl = 0b101,
		Srli = 0b101,
		Sub = 0b000,
		Sw = 0b010,
		Xor = 0b100,
		Xori = 0b100,
	}
}

funct! {
	enum Funct7 {
		Add = 0b000_0000,
		And = 0b000_0000,
		Or = 0b000_0000,
		Sll = 0b000_0000,
		Slli = 0b000_0000,
		Slt = 0b000_0000,
		Sltu = 0b000_0000,
		Sra = 0b010_0000,
		Srai = 0b010_0000,
		Srl = 0b000_0000,
		Srli = 0b000_0000,
		Sub = 0b010_0000,
		Xor = 0b000_0000,
	}
}

funct! {
	enum Func12 {
		EBreak = 0b0000_0000_0001,
		ECall = 0b0000_0000_0000,
	}
}

funct! {
	enum FenceFm {
		None = 0b0000,
		Tso = 0b1000,
	}
}

#[allow(clippy::struct_excessive_bools)]
#[derive(Clone, Copy, Debug)]
pub struct FenceSet {
	pub i: bool,
	pub o: bool,
	pub r: bool,
	pub w: bool,
}

impl FenceSet {
	const RW: Self = Self { i: false, o: false, r: true, w: true };

	#[allow(clippy::bool_to_int_with_if)]
	fn encode(self) -> u32 {
		(if self.i { 0b1000 } else { 0b0000 }) |
			(if self.o { 0b0100 } else { 0b0000 }) |
			(if self.r { 0b0010 } else { 0b0000 }) |
			(if self.w { 0b0001 } else { 0b0000 })
	}
}

impl core::fmt::Display for FenceSet {
	fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
		if !self.i && !self.o && !self.r && !self.w {
			return f.write_str("0");
		}

		if self.i {
			f.write_str("i")?;
		}

		if self.o {
			f.write_str("o")?;
		}

		if self.r {
			f.write_str("r")?;
		}

		if self.w {
			f.write_str("w")?;
		}

		Ok(())
	}
}

impl<'a> TryFrom<&'a [u8]> for FenceSet {
	type Error = ParseError<'a>;

	fn try_from(token: &'a [u8]) -> Result<Self, Self::Error> {
		let (i, o, r, w) = match token {
			b"0" => (false, false, false, false),
			b"i" => (true, false, false, false),
			b"o" => (false, true, false, false),
			b"r" => (false, false, true, false),
			b"w" => (false, false, false, true),
			b"io" => (true, true, false, false),
			b"ir" => (true, false, true, false),
			b"iw" => (true, false, false, true),
			b"or" => (false, true, true, false),
			b"ow" => (false, true, false, true),
			b"rw" => (false, false, true, true),
			b"ior" => (true, true, true, false),
			b"iow" => (true, true, false, true),
			b"irw" => (true, false, true, true),
			b"orw" => (false, true, true, true),
			b"iorw" => (true, true, true, true),
			_ => return Err(ParseError::MalformedFenceSet { token }),
		};
		Ok(Self { i, o, r, w })
	}
}

pub(crate) const fn can_truncate_high<const N: u8>(i: i32) -> bool {
	i == (i << (32 - N)) >> (32 - N)
}

pub(crate) const fn can_truncate_low<const N: u8>(i: i32) -> bool {
	i == (i >> N) << N
}

pub(crate) const fn bit_slice<const L: u8, const H: u8>(i: i32) -> u32 {
	if H < 32 {
		(i as u32 & ((1 << H) - (1 << L))) >> L
	}
	else {
		(i as u32 & (!((1 << L) - 1))) >> L
	}
}
