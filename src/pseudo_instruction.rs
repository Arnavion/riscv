use crate::{
	FenceSet,
	Instruction,
	instruction::{Imm, bit_slice, can_truncate_high, can_truncate_low, tokens},
	ParseError,
	Register,
	SmallIterator,
};

#[allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]
pub(crate) fn parse(line: &str) -> Result<SmallIterator<Instruction>, ParseError<'_>> {
	let mut tokens = tokens(line.as_bytes());

	let Some(token) = tokens.next() else {
		return Ok(SmallIterator::Empty);
	};
	let token = core::str::from_utf8(token).map_err(|_| ParseError::InvalidUtf8 { token })?;

	Ok(match token {
		"beqz" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Beq { src1: src, src2: Register::X0, offset })
		},

		"bgez" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bge { src1: src, src2: Register::X0, offset })
		},

		"bgt" => {
			let src1 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src1 = src1.try_into()?;

			let src2 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src2 = src2.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Blt { src1: src2, src2: src1, offset })
		},

		"bgtu" => {
			let src1 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src1 = src1.try_into()?;

			let src2 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src2 = src2.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bltu { src1: src2, src2: src1, offset })
		},

		"bgtz" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Blt { src1: Register::X0, src2: src, offset })
		},

		"ble" => {
			let src1 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src1 = src1.try_into()?;

			let src2 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src2 = src2.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bge { src1: src2, src2: src1, offset })
		},

		"bleu" => {
			let src1 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src1 = src1.try_into()?;

			let src2 = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src2 = src2.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bgeu { src1: src2, src2: src1, offset })
		},

		"blez" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bge { src1: Register::X0, src2: src, offset })
		},

		"bltz" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Blt { src1: src, src2: Register::X0, offset })
		},

		"bnez" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Bne { src1: src, src2: Register::X0, offset })
		},

		"call" => {
			let token = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let (dest, offset) =
				if let Ok(Imm(offset)) = token.try_into() {
					(Register::X1, offset)
				}
				else {
					let dest = token.try_into()?;
					let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
					let Imm(offset) = offset.try_into()?;
					(dest, offset)
				};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Jalr { dest, base: dest, offset: offset2 },
			)
		},

		"j" => {
			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jal { dest: Register::X0, offset })
		},

		"jal" => {
			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jal { dest: Register::X1, offset })
		},

		"jalr" => {
			let token = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let (dest, base, offset) =
				if let Ok(Imm(offset)) = token.try_into() {
					let b"(" = tokens.next().ok_or(ParseError::TruncatedInstruction { line })? else {
						return Err(ParseError::MalformedInstruction { line });
					};

					let base = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
					let base = base.try_into()?;

					let b")" = tokens.next().ok_or(ParseError::TruncatedInstruction { line })? else {
						return Err(ParseError::MalformedInstruction { line });
					};

					(Register::X1, base, offset)
				}
				else if let b"(" = token {
					let base = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
					let base = base.try_into()?;

					let b")" = tokens.next().ok_or(ParseError::TruncatedInstruction { line })? else {
						return Err(ParseError::MalformedInstruction { line });
					};

					(Register::X1, base, 0)
				}
				else {
					let reg = token.try_into()?;

					if let Some(base) = tokens.next() {
						let base = base.try_into()?;
						(reg, base, 0)
					}
					else {
						(Register::X1, reg, 0)
					}
				};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jalr { dest, base, offset })
		},

		"jr" => {
			let base = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let base = base.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jalr { dest: Register::X0, base, offset: 0 })
		},

		"jump" => {
			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			let scratch = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let scratch = scratch.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest: scratch, imm: offset1 },
				Instruction::Jalr { dest: Register::X0, base: scratch, offset: offset2 },
			)
		},

		"lb" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Lb { dest, base: dest, offset: offset2 },
			)
		},

		"lbu" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Lbu { dest, base: dest, offset: offset2 },
			)
		},

		"lh" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Lh { dest, base: dest, offset: offset2 },
			)
		},

		"lhu" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Lhu { dest, base: dest, offset: offset2 },
			)
		},

		"li" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if can_truncate_low::<12>(imm) {
				SmallIterator::One(Instruction::Lui { dest, imm: imm >> 12 })
			}
			else if can_truncate_high::<12>(imm) {
				SmallIterator::One(Instruction::Addi { dest, src: Register::X0, imm })
			}
			else {
				let (imm1, imm2) = hi_lo(imm);
				SmallIterator::Two(
					Instruction::Lui { dest, imm: imm1 },
					Instruction::Addi { dest, src: dest, imm: imm2 },
				)
			}
		},

		"lla" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Addi { dest, src: dest, imm: offset2 },
			)
		},

		"lw" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest, imm: offset1 },
				Instruction::Lw { dest, base: dest, offset: offset2 },
			)
		},

		"mv" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Addi { dest, src, imm: 0 })
		},

		"neg" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Sub { dest, src1: Register::X0, src2: src })
		},

		"nop" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Addi { dest: Register::X0, src: Register::X0, imm: 0 })
		},

		"not" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Xori { dest, src, imm: -1 })
		},

		"ntl.all" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Add { dest: Register::X0, src1: Register::X0, src2: Register::X5 })
		},

		"ntl.pall" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Add { dest: Register::X0, src1: Register::X0, src2: Register::X3 })
		},

		"ntl.p1" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Add { dest: Register::X0, src1: Register::X0, src2: Register::X2 })
		},

		"ntl.s1" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Add { dest: Register::X0, src1: Register::X0, src2: Register::X4 })
		},

		"pause" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Fence {
				predecessor_set: FenceSet { i: false, o: false, r: false, w: true },
				successor_set: FenceSet { i: false, o: false, r: false, w: false },
			})
		},

		"ret" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jalr { dest: Register::X0, base: Register::X1, offset: 0 })
		},

		"seqz" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Sltiu { dest, src, imm: 1 })
		},

		"sext.b" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let xlen = 32;

			SmallIterator::Two(
				Instruction::Slli { dest, src, shamt: xlen - 8 },
				Instruction::Srai { dest, src: dest, shamt: xlen - 8 },
			)
		},

		"sext.h" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let xlen = 32;

			SmallIterator::Two(
				Instruction::Slli { dest, src, shamt: xlen - 16 },
				Instruction::Srai { dest, src: dest, shamt: xlen - 16 },
			)
		},

		"sgtz" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Slt { dest, src1: Register::X0, src2: src })
		},

		"sltz" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Slt { dest, src1: src, src2: Register::X0 })
		},

		"snez" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Sltu { dest, src1: Register::X0, src2: src })
		},

		"tail" => {
			let offset = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(offset) = offset.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let (offset1, offset2) = hi_lo(offset);

			SmallIterator::Two(
				Instruction::Auipc { dest: Register::X6, imm: offset1 },
				Instruction::Jalr { dest: Register::X0, base: Register::X6, offset: offset2 },
			)
		},

		"zext.b" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Andi { dest, src, imm: 0xff })
		},

		"zext.h" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			let xlen = 32;

			SmallIterator::Two(
				Instruction::Slli { dest, src, shamt: xlen - 16 },
				Instruction::Srli { dest, src: dest, shamt: xlen - 16 },
			)
		},

		_ => return Err(ParseError::UnknownInstruction { line }),
	})
}

#[allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]
fn hi_lo(imm: i32) -> (i32, i32) {
	let mut imm1 = bit_slice::<12, 32>(imm) as i32;
	let imm2 = (imm << (32 - 12)) >> (32 - 12);
	if imm2 < 0 {
		imm1 = imm1.wrapping_add(1) & 0xfffff;
	}
	(imm1, imm2)
}
