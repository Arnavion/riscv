use crate::{
	Csr,
	FenceSet,
	Instruction,
	instruction::{Imm, bit_slice, can_truncate_high, can_truncate_low, parse_base_and_offset, tokens},
	ParseError,
	Register,
	SmallIterator,
	SupportedExtensions,
};

#[allow(clippy::cast_possible_wrap, clippy::cast_sign_loss)]
pub(crate) fn parse(
	line: &[u8],
	supported_extensions: SupportedExtensions,
) -> Result<SmallIterator<Instruction>, ParseError<'_>> {
	let mut tokens = tokens(line);

	let Some(token) = tokens.next() else {
		return Ok(SmallIterator::Empty);
	};
	let token = core::str::from_utf8(token).map_err(|_| ParseError::InvalidUtf8 { token })?;

	Ok(match token {
		"addi4spn" | "c.addi4spn" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src @ Register::X2 = src.try_into()? else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "src", line });
			};

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Addi { dest, src, imm })
		},

		"addi16sp" | "c.addi16sp" => {
			let reg = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let reg @ Register::X2 = reg.try_into()? else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "reg", line });
			};

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Addi { dest: reg, src: reg, imm })
		},

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

		"csrc" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrc { dest: Register::X0, csr, src })
		},

		"csrci" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrci { dest: Register::X0, csr, imm })
		},

		"csrr" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr, src: Register::X0 })
		},

		"csrs" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest: Register::X0, csr, src })
		},

		"csrsi" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrsi { dest: Register::X0, csr, imm })
		},

		"csrw" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrw { dest: Register::X0, csr, src })
		},

		"csrwi" => {
			let csr = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let csr = csr.try_into()?;

			let imm = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let Imm(imm) = imm.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrwi { dest: Register::X0, csr, imm })
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

		"ld" => {
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
				Instruction::Ld { dest, base: dest, offset: offset2 },
			)
		},

		"ldsp" | "c.ldsp" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let Some((base, offset)) = parse_base_and_offset(&mut tokens) else {
				return Err(ParseError::MalformedInstruction { line });
			};
			let base @ Register::X2 = base else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "base", line });
			};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Ld { dest, base, offset })
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

			if can_truncate_low::<12>(imm) && can_truncate_high::<32>(imm) {
				SmallIterator::One(Instruction::Lui { dest, imm: imm >> 12 })
			}
			else if can_truncate_high::<12>(imm) {
				SmallIterator::One(Instruction::Addi { dest, src: Register::X0, imm })
			}
			else if can_truncate_high::<32>(imm) {
				let (imm1, imm2) = hi_lo(imm);
				SmallIterator::Two(
					Instruction::Lui { dest, imm: imm1 },
					if supported_extensions.contains(SupportedExtensions::RV64I) {
						Instruction::Addiw { dest, src: dest, imm: imm2 }
					}
					else {
						Instruction::Addi { dest, src: dest, imm: imm2 }
					}
				)
			}
			else {
				return Err(ParseError::ImmediateOverflow { line });
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

		"lwu" => {
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
				Instruction::Lwu { dest, base: dest, offset: offset2 },
			)
		},

		"lwsp" | "c.lwsp" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let Some((base, offset)) = parse_base_and_offset(&mut tokens) else {
				return Err(ParseError::MalformedInstruction { line });
			};
			let base @ Register::X2 = base else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "base", line });
			};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Lw { dest, base, offset })
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

		"negw" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Subw { dest, src1: Register::X0, src2: src })
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

		"rdcycle" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::Cycle, src: Register::X0 })
		},

		"rdcycleh" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::CycleH, src: Register::X0 })
		},

		"rdinstret" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::InstRet, src: Register::X0 })
		},

		"rdinstreth" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::InstRetH, src: Register::X0 })
		},

		"rdtime" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::Time, src: Register::X0 })
		},

		"rdtimeh" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest = dest.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrs { dest, csr: Csr::TimeH, src: Register::X0 })
		},

		"ret" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Jalr { dest: Register::X0, base: Register::X1, offset: 0 })
		},

		"sdsp" | "c.sdsp" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let Some((base, offset)) = parse_base_and_offset(&mut tokens) else {
				return Err(ParseError::MalformedInstruction { line });
			};
			let base @ Register::X2 = base else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "base", line });
			};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Sd { base, offset, src })
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

			let xlen = if supported_extensions.contains(SupportedExtensions::RV64I) { 64 } else { 32 };

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

			let xlen = if supported_extensions.contains(SupportedExtensions::RV64I) { 64 } else { 32 };

			SmallIterator::Two(
				Instruction::Slli { dest, src, shamt: xlen - 16 },
				Instruction::Srai { dest, src: dest, shamt: xlen - 16 },
			)
		},

		"sext.w" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Addiw { dest, src, imm: 0 })
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

		"swsp" | "c.swsp" => {
			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src = src.try_into()?;

			let Some((base, offset)) = parse_base_and_offset(&mut tokens) else {
				return Err(ParseError::MalformedInstruction { line });
			};
			let base @ Register::X2 = base else {
				return Err(ParseError::SpInstructionRegIsNotX2 { pos: "base", line });
			};

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Sw { base, offset, src })
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

		"unimp" => {
			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			SmallIterator::One(Instruction::Csrrw { dest: Register::X0, csr: Csr::Cycle, src: Register::X0 })
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

			let xlen = if supported_extensions.contains(SupportedExtensions::RV64I) { 64 } else { 32 };

			SmallIterator::Two(
				Instruction::Slli { dest, src, shamt: xlen - 16 },
				Instruction::Srli { dest, src: dest, shamt: xlen - 16 },
			)
		},

		"zext.w" => {
			let dest = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let dest: Register = dest.try_into()?;

			let src = tokens.next().ok_or(ParseError::TruncatedInstruction { line })?;
			let src: Register = src.try_into()?;

			if tokens.next().is_some() {
				return Err(ParseError::TrailingGarbage { line });
			}

			if supported_extensions.contains(SupportedExtensions::RV64I) {
				SmallIterator::Two(
					Instruction::Slli { dest, src, shamt: 32 },
					Instruction::Srli { dest, src: dest, shamt: 32 },
				)
			}
			else {
				SmallIterator::One(Instruction::Addi { dest, src, imm: 0 })
			}
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
