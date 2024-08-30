#![allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]

use crate::{Csr, EncodeError, ParseError, Register, SupportedExtensions};

macro_rules! instructions {
	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ }
	) => {
		#[derive(Clone, Copy, Debug)]
		$vis enum $ty {
			$($variants)*
		}

		impl $ty {
			fn encode_full($self, $supported_extensions: SupportedExtensions) -> Result<(u16, Option<u16>), EncodeError> {
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
				$($encode_arms)*
				Self::$variant { dest, src, shamt } => {
					let max_significant_bits = if $supported_extensions.contains(SupportedExtensions::RV64I) { 6 } else { 5 };
					// shamt is always treated as positive
					if shamt & ((1 << max_significant_bits) - 1) != shamt {
						return Err(EncodeError::ImmediateOverflow);
					}

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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, csr: Csr, src: Register }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, csr: Csr, src: Register },
			}
			{
				$self
				$supported_extensions
				$($encode_arms)*
				Self::$variant { dest, csr, src } => RawInstruction::CsrI {
					opcode: OpCode::$opcode,
					rd: dest,
					funct3: Funct3::$variant,
					src: src.encode_5b(),
					csr,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let csr = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let csr = csr.try_into()?;

					let src = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let src = src.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, csr, src }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, csr, src } => write!($f, concat!($asm, " {}, {}, {}"), dest, csr, src),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
		{ $parse_line:ident $parse_tokens:ident $($parse_arms:tt)* }
		{ $f:ident $($display_arms:tt)* }
		{ #[i( $asm:tt , $opcode:tt )] $variant:tt { dest: Register, csr: Csr, imm: i32 }, $($rest:tt)* }
	) => {
		instructions! {
			@inner
			$vis
			$ty
			{
				$($variants)*
				$variant { dest: Register, csr: Csr, imm: i32 },
			}
			{
				$self
				$supported_extensions
				$($encode_arms)*
				Self::$variant { dest, csr, imm } => RawInstruction::CsrI {
					opcode: OpCode::$opcode,
					rd: dest,
					funct3: Funct3::$variant,
					src: imm as u32,
					csr,
				},
			}
			{
				$parse_line
				$parse_tokens
				$($parse_arms)*
				$asm => {
					let dest = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let dest = dest.try_into()?;

					let csr = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let csr = csr.try_into()?;

					let imm = $parse_tokens.next().ok_or(ParseError::TruncatedInstruction { line: $parse_line })?;
					let Imm(imm) = imm.try_into()?;

					if $parse_tokens.next().is_some() {
						return Err(ParseError::TrailingGarbage { line: $parse_line });
					}

					Self::$variant { dest, csr, imm }
				},
			}
			{
				$f
				$($display_arms)*
				Self::$variant { dest, csr, imm } => write!($f, concat!($asm, " {}, {}, {}"), dest, csr, imm),
			}
			{ $($rest)* }
		}
	};

	(
		@inner
		$vis:vis
		$ty:ident
		{ $($variants:tt)* }
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
		{ $self:ident $supported_extensions:ident $($encode_arms:tt)* }
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
				$supported_extensions
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
			{ self supported_extensions }
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

		#[i("addiw", OpImm32)]
		Addiw { dest: Register, src: Register, imm: i32 },

		#[r("addw", Op32)]
		Addw { dest: Register, src1: Register, src2: Register },

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

		#[i("csrrc", System)]
		Csrrc { dest: Register, csr: Csr, src: Register },

		#[i("csrrci", System)]
		Csrrci { dest: Register, csr: Csr, imm: i32 },

		#[i("csrrs", System)]
		Csrrs { dest: Register, csr: Csr, src: Register },

		#[i("csrrsi", System)]
		Csrrsi { dest: Register, csr: Csr, imm: i32 },

		#[i("csrrw", System)]
		Csrrw { dest: Register, csr: Csr, src: Register },

		#[i("csrrwi", System)]
		Csrrwi { dest: Register, csr: Csr, imm: i32 },

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

		#[i("ld", Load)]
		Ld { dest: Register, base: Register, offset: i32 },

		#[i("lh", Load)]
		Lh { dest: Register, base: Register, offset: i32 },

		#[i("lhu", Load)]
		Lhu { dest: Register, base: Register, offset: i32 },

		#[u("lui", Lui)]
		Lui { dest: Register, imm: i32 },

		#[i("lw", Load)]
		Lw { dest: Register, base: Register, offset: i32 },

		#[i("lwu", Load)]
		Lwu { dest: Register, base: Register, offset: i32 },

		#[r("or", Op)]
		Or { dest: Register, src1: Register, src2: Register },

		#[i("ori", OpImm)]
		Ori { dest: Register, src: Register, imm: i32 },

		#[s("sb", Store)]
		Sb { base: Register, offset: i32, src: Register },

		#[s("sd", Store)]
		Sd { base: Register, offset: i32, src: Register },

		#[s("sh", Store)]
		Sh { base: Register, offset: i32, src: Register },

		#[r("sll", Op)]
		Sll { dest: Register, src1: Register, src2: Register },

		#[i("slli", OpImm)]
		Slli { dest: Register, src: Register, shamt: i32 },

		#[i("slliw", OpImm32)]
		Slliw { dest: Register, src: Register, shamt: i32 },

		#[r("sllw", Op32)]
		Sllw { dest: Register, src1: Register, src2: Register },

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

		#[i("sraiw", OpImm32)]
		Sraiw { dest: Register, src: Register, shamt: i32 },

		#[r("sraw", Op32)]
		Sraw { dest: Register, src1: Register, src2: Register },

		#[r("srl", Op)]
		Srl { dest: Register, src1: Register, src2: Register },

		#[i("srli", OpImm)]
		Srli { dest: Register, src: Register, shamt: i32 },

		#[i("srliw", OpImm32)]
		Srliw { dest: Register, src: Register, shamt: i32 },

		#[r("srlw", Op32)]
		Srlw { dest: Register, src1: Register, src2: Register },

		#[r("sub", Op)]
		Sub { dest: Register, src1: Register, src2: Register },

		#[r("subw", Op32)]
		Subw { dest: Register, src1: Register, src2: Register },

		#[s("sw", Store)]
		Sw { base: Register, offset: i32, src: Register },

		#[r("xor", Op)]
		Xor { dest: Register, src1: Register, src2: Register },

		#[i("xori", OpImm)]
		Xori { dest: Register, src: Register, imm: i32 },
	}
}

impl Instruction {
	pub fn encode(self, supported_extensions: SupportedExtensions) -> Result<(u16, Option<u16>), EncodeError> {
		if !supported_extensions.contains(SupportedExtensions::RVC) {
			return self.encode_full(supported_extensions);
		}

		let raw_instruction = match self {
			Self::Add { dest, src1: src, src2: Register::X0 } |
			Self::Add { dest, src1: Register::X0, src2: src } if
				dest != Register::X0 &&
				src != Register::X0
			=> RawInstruction::Cr {
				opcode: OpCodeC::Mv,
				rd_rs1: dest,
				rs2: src,
			},

			Self::Add { dest, src1: src, src2: other } |
			Self::Add { dest, src1: other, src2: src } if
				dest != Register::X0 &&
				src != Register::X0 &&
				other == dest
			=> RawInstruction::Cr {
				opcode: OpCodeC::Add,
				rd_rs1: dest,
				rs2: src,
			},

			// C.NTL.*
			Self::Add { dest: Register::X0, src1: Register::X0, src2: src @ (Register::X2 | Register::X3 | Register::X4 | Register::X5) }
			=> RawInstruction::Cr {
				opcode: OpCodeC::Add,
				rd_rs1: Register::X0,
				rs2: src,
			},

			// C.NOP
			Self::Addi { dest: Register::X0, src: _, imm: 0 }
			=> RawInstruction::Ci {
				opcode: OpCodeC::Addi,
				rd_rs1: Register::X0,
				imm1: 0,
				imm2: 0,
			},

			Self::Addi { dest, src: Register::X0, imm } if
				dest != Register::X0 &&
				can_truncate_high::<6>(imm)
			=> RawInstruction::Ci {
				opcode: OpCodeC::Li,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(imm),
				imm2: bit_slice::<5, 6>(imm),
			},

			Self::Addi { dest: Register::X2, src: Register::X2, imm } if
				imm != 0 &&
				can_truncate_low::<4>(imm) &&
				can_truncate_high::<10>(imm)
			=> {
				let imm1 =
					bit_slice::<5, 6>(imm) |
					(bit_slice::<7, 9>(imm) << 1) |
					(bit_slice::<6, 7>(imm) << 3) |
					(bit_slice::<4, 5>(imm) << 4);
				let imm2 = bit_slice::<9, 10>(imm);
				RawInstruction::Ci {
					opcode: OpCodeC::Addi16Sp,
					rd_rs1: Register::X2,
					imm1,
					imm2
				}
			},

			Self::Addi { dest, src: Register::X2, imm } if
				dest.is_compressible() &&
				imm != 0 &&
				imm & ((1 << 10) - (1 << 2)) == imm
			=> RawInstruction::Ciw {
				opcode: OpCodeC::Addi4Spn,
				rd: dest,
				imm,
			},

			Self::Addi { dest, src, imm: 0 } if
				dest != Register::X0 &&
				src != Register::X0
			=> RawInstruction::Cr {
				opcode: OpCodeC::Mv,
				rd_rs1: dest,
				rs2: src,
			},

			Self::Addi { dest, src, imm } if
				dest != Register::X0 &&
				dest == src &&
				imm != 0 &&
				can_truncate_high::<6>(imm)
			=> RawInstruction::Ci {
				opcode: OpCodeC::Addi,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(imm),
				imm2: bit_slice::<5, 6>(imm),
			},

			Self::Addiw { dest, src, imm } if
				dest != Register::X0 &&
				dest == src &&
				can_truncate_high::<6>(imm)
			=> RawInstruction::Ci {
				opcode: OpCodeC::Addiw,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(imm),
				imm2: bit_slice::<5, 6>(imm),
			},

			Self::Addw { dest, src1: src, src2: other } |
			Self::Addw { dest, src1: other, src2: src } if
				dest.is_compressible() &&
				src.is_compressible() &&
				other == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::Addw,
				rd_rs1: dest,
				rs2: src,
				funct2: Funct2::Addw,
			},

			Self::And { dest, src1: src, src2: other } |
			Self::And { dest, src1: other, src2: src } if
				dest.is_compressible() &&
				src.is_compressible() &&
				other == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::And,
				rd_rs1: dest,
				rs2: src,
				funct2: Funct2::And,
			},

			Self::Andi { dest, src, imm: 0xff } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				dest.is_compressible() &&
				src == dest
			=> RawInstruction::Zcb {
				opcode: OpCodeC::ZextB,
				reg: dest,
				imm1: 0b000,
				imm2: 0b11,
			},

			Self::Andi { dest, src, imm } if
				dest.is_compressible() &&
				src == dest &&
				can_truncate_high::<6>(imm)
			=> RawInstruction::Cb {
				opcode: OpCodeC::Andi,
				rs1: dest,
				imm1: bit_slice::<0, 5>(imm),
				imm2: bit_slice::<5, 6>(imm) << 2,
			},

			Self::Beq { src1: Register::X0, src2: src, offset } |
			Self::Beq { src1: src, src2: Register::X0, offset } if
				src.is_compressible() &&
				can_truncate_low::<1>(offset) &&
				can_truncate_high::<9>(offset)
			=> {
				let imm1 =
					(bit_slice::<5, 6>(offset)) |
					(bit_slice::<1, 3>(offset) << 1) |
					(bit_slice::<6, 8>(offset) << 3);
				let imm2 =
					(bit_slice::<3, 5>(offset)) |
					(bit_slice::<8, 9>(offset) << 2);
				RawInstruction::Cb {
					opcode: OpCodeC::Beqz,
					rs1: src,
					imm1,
					imm2,
				}
			},

			Self::Bne { src1: Register::X0, src2: src, offset } |
			Self::Bne { src1: src, src2: Register::X0, offset } if
				src.is_compressible() &&
				can_truncate_low::<1>(offset) &&
				can_truncate_high::<9>(offset)
			=> {
				let imm1 =
					(bit_slice::<5, 6>(offset)) |
					(bit_slice::<1, 3>(offset) << 1) |
					(bit_slice::<6, 8>(offset) << 3);
				let imm2 =
					(bit_slice::<3, 5>(offset)) |
					(bit_slice::<8, 9>(offset) << 2);
				RawInstruction::Cb {
					opcode: OpCodeC::Bnez,
					rs1: src,
					imm1,
					imm2,
				}
			},

			Self::EBreak => RawInstruction::Cr {
				opcode: OpCodeC::EBreak,
				rd_rs1: Register::X0,
				rs2: Register::X0,
			},

			Self::Jal { dest: Register::X0, offset } if
				can_truncate_low::<1>(offset) &&
				can_truncate_high::<12>(offset)
			=> RawInstruction::Cj {
				opcode: OpCodeC::J,
				imm: offset,
			},

			Self::Jal { dest: Register::X1, offset } if
				!supported_extensions.contains(SupportedExtensions::RV64I) &&
				can_truncate_low::<1>(offset) &&
				can_truncate_high::<12>(offset)
			=> RawInstruction::Cj {
				opcode: OpCodeC::Jal,
				imm: offset,
			},

			Self::Jalr { dest: Register::X0, base, offset: 0 } if
				base != Register::X0
			=> RawInstruction::Cr {
				opcode: OpCodeC::Jr,
				rd_rs1: base,
				rs2: Register::X0,
			},

			Self::Jalr { dest: Register::X1, base, offset: 0 } if
				base != Register::X0
			=> RawInstruction::Cr {
				opcode: OpCodeC::Jalr,
				rd_rs1: base,
				rs2: Register::X0,
			},

			Self::Lbu { dest, base, offset } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				dest.is_compressible() &&
				base.is_compressible() &&
				offset & 0b11 == offset
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Lbu,
				reg: base,
				imm1: dest.encode_3b()?,
				imm2: offset,
			},

			Self::Ld { dest, base: Register::X2, offset } if
				dest != Register::X0 &&
				offset & ((1 << 9) - (1 << 3)) == offset
			=> {
				let imm1 =
					bit_slice::<6, 9>(offset) |
					(bit_slice::<3, 5>(offset) << 3);
				let imm2 = bit_slice::<5, 6>(offset);
				RawInstruction::Ci {
					opcode: OpCodeC::Ldsp,
					rd_rs1: dest,
					imm1,
					imm2,
				}
			},

			Self::Ld { dest, base, offset } if
				dest.is_compressible() &&
				base.is_compressible() &&
				offset & ((1 << 8) - (1 << 3)) == offset
			=> RawInstruction::Cl {
				opcode: OpCodeC::Ld,
				rd: dest,
				rs1: base,
				imm1: bit_slice::<6, 8>(offset),
				imm2: bit_slice::<3, 6>(offset),
			},

			Self::Lh { dest, base, offset } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				dest.is_compressible() &&
				base.is_compressible() &&
				offset & (1 << 1) == offset
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Lh,
				reg: base,
				imm1: dest.encode_3b()?,
				imm2: offset | (1 << 0),
			},

			Self::Lhu { dest, base, offset } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				dest.is_compressible() &&
				base.is_compressible() &&
				offset & (1 << 1) == offset
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Lhu,
				reg: base,
				imm1: dest.encode_3b()?,
				imm2: offset,
			},

			Self::Lui { dest, imm } if
				!matches!(dest, Register::X0 | Register::X2) &&
				imm != 0 &&
				can_truncate_high::<6>(imm)
			=> RawInstruction::Ci {
				opcode: OpCodeC::Lui,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(imm),
				imm2: bit_slice::<5, 6>(imm),
			},

			Self::Lui { dest, imm: 0 } if
				dest != Register::X0
			=> RawInstruction::Ci {
				opcode: OpCodeC::Li,
				rd_rs1: dest,
				imm1: 0,
				imm2: 0,
			},

			Self::Lw { dest, base: Register::X2, offset } if
				dest != Register::X0 &&
				offset & ((1 << 8) - (1 << 2)) == offset
			=> {
				let imm1 =
					bit_slice::<6, 8>(offset) |
					(bit_slice::<2, 5>(offset) << 2);
				let imm2 = bit_slice::<5, 6>(offset);
				RawInstruction::Ci {
					opcode: OpCodeC::Lwsp,
					rd_rs1: dest,
					imm1,
					imm2,
				}
			},

			Self::Lw { dest, base, offset } if
				dest.is_compressible() &&
				base.is_compressible() &&
				offset & ((1 << 7) - (1 << 2)) == offset
			=> {
				let imm1 =
					bit_slice::<6, 7>(offset) |
					(bit_slice::<2, 3>(offset) << 1);
				let imm2 = bit_slice::<3, 6>(offset);
				RawInstruction::Cl {
					opcode: OpCodeC::Lw,
					rd: dest,
					rs1: base,
					imm1,
					imm2,
				}
			},

			Self::Or { dest, src1: src, src2: other } |
			Self::Or { dest, src1: other, src2: src } if
				dest.is_compressible() &&
				src.is_compressible() &&
				other == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::Or,
				rd_rs1: dest,
				rs2: src,
				funct2: Funct2::Or,
			},

			Self::Sb { base, offset, src } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				base.is_compressible() &&
				src.is_compressible() &&
				offset & 0xff == offset
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Sb,
				reg: base,
				imm1: src.encode_3b()?,
				imm2: offset,
			},

			Self::Sd { base: Register::X2, offset, src } if
				offset & 0x1f8 == offset
			=> {
				let imm =
					bit_slice::<6, 9>(offset) |
					(bit_slice::<3, 6>(offset) << 3);
				RawInstruction::Css {
					opcode: OpCodeC::Sdsp,
					rs2: src,
					imm,
				}
			},

			Self::Sd { base, offset, src } if
				base.is_compressible() &&
				src.is_compressible() &&
				offset & ((1 << 8) - (1 << 3)) == offset
			=> RawInstruction::Cs {
				opcode: OpCodeC::Sd,
				rs1: base,
				rs2: src,
				imm1: bit_slice::<6, 8>(offset),
				imm2: bit_slice::<3, 6>(offset),
			},

			Self::Sh { base, offset, src } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				base.is_compressible() &&
				src.is_compressible() &&
				offset & (1 << 1) == offset
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Sh,
				reg: base,
				imm1: src.encode_3b()?,
				imm2: offset,
			},

			Self::Slli { dest, src, shamt } if
				supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest != Register::X0 &&
				dest == src &&
				shamt != 0 &&
				shamt & ((1 << 6) - 1) == shamt
			=> RawInstruction::Ci {
				opcode: OpCodeC::Slli,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: bit_slice::<5, 6>(shamt),
			},

			Self::Slli { dest, src, shamt } if
				!supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest != Register::X0 &&
				dest == src &&
				shamt != 0 &&
				shamt & ((1 << 5) - 1) == shamt
			=> RawInstruction::Ci {
				opcode: OpCodeC::Slli,
				rd_rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: 0,
			},

			Self::Srai { dest, src, shamt } if
				supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest.is_compressible() &&
				src == dest &&
				shamt != 0 &&
				shamt & ((1 << 6) - 1) == shamt
			=> RawInstruction::Cb {
				opcode: OpCodeC::Srai,
				rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: bit_slice::<5, 6>(shamt) << 2,
			},

			Self::Srai { dest, src, shamt } if
				!supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest.is_compressible() &&
				src == dest &&
				shamt != 0 &&
				shamt & ((1 << 5) - 1) == shamt
			=> RawInstruction::Cb {
				opcode: OpCodeC::Srai,
				rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: 0,
			},

			Self::Srli { dest, src, shamt } if
				supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest.is_compressible() &&
				src == dest &&
				shamt != 0 &&
				shamt & ((1 << 6) - 1) == shamt
			=> RawInstruction::Cb {
				opcode: OpCodeC::Srli,
				rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: bit_slice::<5, 6>(shamt) << 2,
			},

			Self::Srli { dest, src, shamt } if
				!supported_extensions.contains(SupportedExtensions::RV64I) &&
				dest.is_compressible() &&
				src == dest &&
				shamt != 0 &&
				shamt & ((1 << 5) - 1) == shamt
			=> RawInstruction::Cb {
				opcode: OpCodeC::Srli,
				rs1: dest,
				imm1: bit_slice::<0, 5>(shamt),
				imm2: 0,
			},

			Self::Sub { dest, src1, src2 } if
				dest.is_compressible() &&
				src2.is_compressible() &&
				src1 == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::Sub,
				rd_rs1: dest,
				rs2: src2,
				funct2: Funct2::Sub,
			},

			Self::Subw { dest, src1: src, src2: other } |
			Self::Subw { dest, src1: other, src2: src } if
				dest.is_compressible() &&
				src.is_compressible() &&
				other == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::Subw,
				rd_rs1: dest,
				rs2: src,
				funct2: Funct2::Subw,
			},

			Self::Sw { base: Register::X2, offset, src } if
				offset & ((1 << 8) - (1 << 2)) == offset
			=> {
				let imm =
					bit_slice::<6, 8>(offset) |
					(bit_slice::<2, 6>(offset) << 2);
				RawInstruction::Css {
					opcode: OpCodeC::Swsp,
					rs2: src,
					imm,
				}
			},

			Self::Sw { base, offset, src } if
				base.is_compressible() &&
				src.is_compressible() &&
				offset & ((1 << 7) - (1 << 2)) == offset
			=> {
				let imm1 =
					bit_slice::<6, 7>(offset) |
					(bit_slice::<2, 3>(offset) << 1);
				let imm2 = bit_slice::<3, 6>(offset);
				RawInstruction::Cs {
					opcode: OpCodeC::Sw,
					rs1: base,
					rs2: src,
					imm1,
					imm2,
				}
			},

			Self::Xor { dest, src1: src, src2: other } |
			Self::Xor { dest, src1: other, src2: src } if
				dest.is_compressible() &&
				src.is_compressible() &&
				other == dest
			=> RawInstruction::Ca {
				opcode: OpCodeC::Xor,
				rd_rs1: dest,
				rs2: src,
				funct2: Funct2::Xor,
			},

			Self::Xori { dest, src, imm: -1 } if
				supported_extensions.contains(SupportedExtensions::ZCB) &&
				dest.is_compressible() &&
				src == dest
			=> RawInstruction::Zcb {
				opcode: OpCodeC::Not,
				reg: dest,
				imm1: 0b101,
				imm2: 0b11,
			},

			_ => return self.encode_full(supported_extensions),
		};

		raw_instruction.encode()
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

pub(crate) fn parse_base_and_offset<'a>(tokens: &mut impl Iterator<Item = &'a [u8]>) -> Option<(Register, i32)> {
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

	CsrI {
		opcode: OpCode,
		rd: Register,
		funct3: Funct3,
		src: u32,
		csr: Csr,
	},

	Cr {
		opcode: OpCodeC,
		rd_rs1: Register,
		rs2: Register,
	},

	Ci {
		opcode: OpCodeC,
		rd_rs1: Register,
		imm1: u32,
		imm2: u32,
	},

	Cl {
		opcode: OpCodeC,
		rd: Register,
		rs1: Register,
		imm1: u32,
		imm2: u32,
	},

	Cs {
		opcode: OpCodeC,
		rs1: Register,
		rs2: Register,
		imm1: u32,
		imm2: u32,
	},

	Css {
		opcode: OpCodeC,
		rs2: Register,
		imm: u32,
	},

	Ciw {
		opcode: OpCodeC,
		rd: Register,
		imm: i32,
	},

	Ca {
		opcode: OpCodeC,
		rd_rs1: Register,
		rs2: Register,
		funct2: Funct2,
	},

	Cb {
		opcode: OpCodeC,
		rs1: Register,
		imm1: u32,
		imm2: u32,
	},

	Cj {
		opcode: OpCodeC,
		imm: i32,
	},

	Zcb {
		opcode: OpCodeC,
		reg: Register,
		imm1: u32,
		imm2: i32,
	},
}

impl RawInstruction {
	fn encode(self) -> Result<(u16, Option<u16>), EncodeError> {
		#[derive(Clone, Copy, Debug)]
		enum Encoded {
			Full(u32),
			Compressed(u32),
		}

		impl Encoded {
			fn into_parts(self) -> (u16, Option<u16>) {
				match self {
					Self::Full(encoded) => {
						const LENGTH_SUFFIX_FIXED_32_BITS: u16 = 0b11;

						let lo = (encoded & 0x0000_FFFF) as u16 | LENGTH_SUFFIX_FIXED_32_BITS;
						let hi = (encoded >> 16) as u16;
						(lo, Some(hi))
					},
					Self::Compressed(encoded) => {
						let lo = (encoded & 0x0000_FFFF) as u16;
						let hi = (encoded >> 16) as u16;
						assert_eq!(hi, 0);
						(lo, None)
					},
				}
			}
		}

		let encoded = match self {
			Self::R { opcode, rd, funct3, rs1, rs2, funct7 } =>
				Encoded::Full(
					opcode.encode() |
					rd.encode_rd_5b() |
					(funct3.encode() << 12) |
					rs1.encode_rs1_5b() |
					rs2.encode_rs2_5b() |
					(funct7.encode() << 25)
				),

			Self::I { opcode, rd, funct3, rs1, imm } => {
				if !can_truncate_high::<12>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Full(
					opcode.encode() |
					rd.encode_rd_5b() |
					(funct3.encode() << 12) |
					rs1.encode_rs1_5b() |
					(bit_slice::<0, 12>(imm) << 20)
				)
			},

			Self::S { opcode, funct3, rs1, rs2, imm } => {
				if !can_truncate_high::<12>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Full(
					opcode.encode() |
					(bit_slice::<0, 5>(imm) << 7) |
					(funct3.encode() << 12) |
					rs1.encode_rs1_5b() |
					rs2.encode_rs2_5b() |
					(bit_slice::<5, 12>(imm) << 25)
				)
			},

			Self::B { opcode, funct3, rs1, rs2, imm } => {
				if !can_truncate_low::<1>(imm) || !can_truncate_high::<13>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Full(
					opcode.encode() |
					(bit_slice::<11, 12>(imm) << 7) |
					(bit_slice::<1, 5>(imm) << 8) |
					(funct3.encode() << 12) |
					rs1.encode_rs1_5b() |
					rs2.encode_rs2_5b() |
					(bit_slice::<5, 11>(imm) << 25) |
					(bit_slice::<12, 13>(imm) << 31)
				)
			},

			Self::U { opcode, rd, imm } => {
				let imm =
					if can_truncate_high::<20>(imm) || (imm as u32 & 0xfff0_0000) == 0 {
						bit_slice::<0, 20>(imm) << 12
					}
					else {
						return Err(EncodeError::ImmediateOverflow);
					};

				Encoded::Full(
					opcode.encode() |
					rd.encode_rd_5b() |
					imm
				)
			},

			Self::J { opcode, rd, imm } => {
				if !can_truncate_low::<1>(imm) || !can_truncate_high::<21>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Full(
					opcode.encode() |
					rd.encode_rd_5b() |
					(bit_slice::<12, 20>(imm) << 12) |
					(bit_slice::<11, 12>(imm) << 20) |
					(bit_slice::<1, 11>(imm) << 21) |
					(bit_slice::<20, 21>(imm) << 31)
				)
			},

			Self::Fence { fm, predecessor_set, successor_set } =>
				Encoded::Full(
					OpCode::MiscMem.encode() |
					(fm.encode() << 28) |
					(predecessor_set.encode() << 24) |
					(successor_set.encode() << 20)
				),

			Self::CsrI { opcode, rd, funct3, src, csr } => {
				if src & ((1 << 5) - 1) != src {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Full(
					opcode.encode() |
					rd.encode_rd_5b() |
					(funct3.encode() << 12) |
					(src << 15) |
					csr.encode_12b()
				)
			},

			Self::Cr { opcode, rd_rs1, rs2 } => Encoded::Compressed(
				opcode.encode() |
				(rs2.encode_5b() << 2) |
				rd_rs1.encode_rd_5b()
			),

			Self::Ci { opcode, rd_rs1, imm1, imm2 } => Encoded::Compressed(
				opcode.encode() |
				(imm1 << 2) |
				rd_rs1.encode_rd_5b() |
				(imm2 << 12)
			),

			Self::Cl { opcode, rd, rs1, imm1, imm2 } => Encoded::Compressed(
				opcode.encode() |
				(rd.encode_3b()? << 2) |
				(imm1 << 5) |
				(rs1.encode_3b()? << 7) |
				(imm2 << 10)
			),

			Self::Cs { opcode, rs1, rs2, imm1, imm2 } => Encoded::Compressed(
				opcode.encode() |
				(rs2.encode_3b()? << 2) |
				(imm1 << 5) |
				(rs1.encode_3b()? << 7) |
				(imm2 << 10)
			),

			Self::Css { opcode, rs2, imm } => Encoded::Compressed(
				opcode.encode() |
				(rs2.encode_5b() << 2) |
				(imm << 7)
			),

			Self::Ciw { opcode, rd, imm } => Encoded::Compressed(
				opcode.encode() |
				(rd.encode_3b()? << 2) |
				(bit_slice::<3, 4>(imm) << 5) |
				(bit_slice::<2, 3>(imm) << 6) |
				(bit_slice::<6, 10>(imm) << 7) |
				(bit_slice::<4, 6>(imm) << 11)
			),

			Self::Ca { opcode, rd_rs1, rs2, funct2 } => Encoded::Compressed(
				opcode.encode() |
				(rs2.encode_3b()? << 2) |
				(funct2.encode() << 5) |
				(rd_rs1.encode_3b()? << 7)
			),

			Self::Cb { opcode, rs1, imm1, imm2 } => Encoded::Compressed(
				opcode.encode() |
				(imm1 << 2) |
				(rs1.encode_3b()? << 7) |
				(imm2 << 10)
			),

			Self::Cj { opcode, imm } => {
				if !can_truncate_low::<1>(imm) || !can_truncate_high::<12>(imm) {
					return Err(EncodeError::ImmediateOverflow);
				}

				Encoded::Compressed(
					opcode.encode() |
					(bit_slice::<1, 4>(imm) << 3) |
					(bit_slice::<4, 5>(imm) << 11) |
					(bit_slice::<5, 6>(imm) << 2) |
					(bit_slice::<6, 7>(imm) << 7) |
					(bit_slice::<7, 8>(imm) << 6) |
					(bit_slice::<8, 10>(imm) << 9) |
					(bit_slice::<10, 11>(imm) << 8) |
					(bit_slice::<11, 12>(imm) << 12)
				)
			},

			Self::Zcb { opcode, reg, imm1, imm2 } => Encoded::Compressed(
				opcode.encode() |
				((imm1 & 0x7) << 2) |
				(bit_slice::<1, 2>(imm2) << 5) |
				(bit_slice::<0, 1>(imm2) << 6) |
				(reg.encode_3b()? << 7)
			),
		};
		Ok(encoded.into_parts())
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
	Op32 = 0b01110,
	OpImm = 0b00100,
	OpImm32 = 0b00110,
	Store = 0b01000,
	System = 0b11100,

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
		(self as u32) << 2
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
		Addiw = 0b000,
		Addw = 0b000,
		And = 0b111,
		Andi = 0b111,
		Beq = 0b000,
		Bge = 0b101,
		Bgeu = 0b111,
		Blt = 0b100,
		Bltu = 0b110,
		Bne = 0b001,
		Csrrc = 0b011,
		Csrrci = 0b111,
		Csrrs = 0b010,
		Csrrsi = 0b110,
		Csrrw = 0b001,
		Csrrwi = 0b101,
		EBreak = 0b000,
		ECall = 0b000,
		Jalr = 0b000,
		Lb = 0b000,
		Lbu = 0b100,
		Ld = 0b011,
		Lh = 0b001,
		Lhu = 0b101,
		Lw = 0b010,
		Lwu = 0b110,
		Or = 0b110,
		Ori = 0b110,
		Sb = 0b000,
		Sd = 0b011,
		Sh = 0b001,
		Sll = 0b001,
		Slli = 0b001,
		Slliw = 0b001,
		Sllw = 0b001,
		Slt = 0b010,
		Slti = 0b010,
		Sltiu = 0b011,
		Sltu = 0b011,
		Sra = 0b101,
		Srai = 0b101,
		Sraiw = 0b101,
		Sraw = 0b101,
		Srl = 0b101,
		Srli = 0b101,
		Srliw = 0b101,
		Srlw = 0b101,
		Sub = 0b000,
		Subw = 0b000,
		Sw = 0b010,
		Xor = 0b100,
		Xori = 0b100,
	}
}

funct! {
	enum Funct7 {
		Add = 0b000_0000,
		Addw = 0b000_0000,
		And = 0b000_0000,
		Or = 0b000_0000,
		Sll = 0b000_0000,
		Slli = 0b000_0000,
		Slliw = 0b000_0000,
		Sllw = 0b000_0000,
		Slt = 0b000_0000,
		Sltu = 0b000_0000,
		Sra = 0b010_0000,
		Srai = 0b010_0000,
		Sraiw = 0b010_0000,
		Sraw = 0b010_0000,
		Srl = 0b000_0000,
		Srli = 0b000_0000,
		Srliw = 0b000_0000,
		Srlw = 0b000_0000,
		Sub = 0b010_0000,
		Subw = 0b010_0000,
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

macro_rules! opcodec {
	(
		$vis:vis enum $ty:ident {
			$($variant:ident = ( $quadrant:ident, $funct6:literal ) ,)*
		}
	) => {
		#[allow(clippy::unreadable_literal)]
		#[derive(Clone, Copy, Debug)]
		$vis enum $ty {
			$($variant ,)*
		}

		impl $ty {
			const fn encode(self) -> u32 {
				#[allow(clippy::unreadable_literal)]
				let (quadrant, funct6) = match self {
					$(Self::$variant => (OpCodeCQuadrant::$quadrant, $funct6) ,)*
				};
				(quadrant as u32) | (funct6 << 10)
			}
		}
	};
}

#[derive(Clone, Copy, Debug)]
enum OpCodeCQuadrant {
	C0 = 0b00,
	C1 = 0b01,
	C2 = 0b10,
}

opcodec! {
	enum OpCodeC {
		Add = (C2, 0b100_100),
		Addi = (C1, 0b000_000),
		Addiw = (C1, 0b001_000),
		Addi4Spn = (C0, 0b000_000),
		Addi16Sp = (C1, 0b011_000),
		Addw = (C1, 0b100_111),
		And = (C1, 0b100_011),
		Andi = (C1, 0b100_010),
		Beqz = (C1, 0b110_000),
		Bnez = (C1, 0b111_000),
		EBreak = (C2, 0b100_100),
		J = (C1, 0b101_000),
		Jal = (C1, 0b001_000),
		Jalr = (C2, 0b100_100),
		Jr = (C2, 0b100_000),
		Lbu = (C0, 0b100_000),
		Ld = (C0, 0b011_000),
		Ldsp = (C2, 0b011_000),
		Lh = (C0, 0b100_001),
		Lhu = (C0, 0b100_001),
		Li = (C1, 0b010_000),
		Lui = (C1, 0b011_000),
		Lw = (C0, 0b010_000),
		Lwsp = (C2, 0b010_000),
		Mv = (C2, 0b100_000),
		Not = (C1, 0b100_111),
		Or = (C1, 0b100_011),
		Sb = (C0, 0b100_010),
		Sd = (C0, 0b111_000),
		Sdsp = (C2, 0b111_000),
		Sh = (C0, 0b100_011),
		Slli = (C2, 0b000_000),
		Srai = (C1, 0b100_001),
		Srli = (C1, 0b100_000),
		Subw = (C1, 0b100_111),
		Sw = (C0, 0b110_000),
		Swsp = (C2, 0b110_000),
		Sub = (C1, 0b100_011),
		Xor = (C1, 0b100_011),
		ZextB = (C1, 0b100_111),
	}
}

funct! {
	enum Funct2 {
		Addw = 0b01,
		And = 0b11,
		Or = 0b10,
		Sub = 0b00,
		Subw = 0b00,
		Xor = 0b01,
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
