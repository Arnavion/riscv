#![allow(clippy::unreadable_literal)]

use crate::{
	csrs::Csr,
	memory::{LoadOp, StoreOp},
	x_regs::XReg,
};

#[derive(Clone, Copy, Debug)]
pub(crate) enum Instruction {
	Abs { rd: XReg, rs: XReg },
	Auipc { rd: XReg, imm: i64 },
	Branch { op: BranchOp, rs1: XReg, rs2: XReg, imm: i64 },
	Csrrw { rd: XReg, csr: Csr, rs1: XReg },
	Csrrwi { rd: XReg, csr: Csr, imm: i64 },
	Csrrs { rd: XReg, csr: Csr, rs1: XReg },
	Csrrsi { rd: XReg, csr: Csr, imm: i64 },
	Csrrc { rd: XReg, csr: Csr, rs1: XReg },
	Csrrci { rd: XReg, csr: Csr, imm: i64 },
	Ebreak,
	Fence,
	Jal { rd: XReg, imm: i64 },
	Jalr { rd: XReg, rs1: XReg, imm: i64 },
	Load { op: LoadOp, rd: XReg, base: MemoryBase, offset: MemoryOffset },
	Lui { rd: XReg, imm: i64 },
	Op { op: OpOp, rd: XReg, rs1: XReg, rs2: XReg },
	Op32 { op: Op32Op, rd: XReg, rs1: XReg, rs2: XReg },
	OpImm { op: OpImmOp, rd: XReg, rs1: XReg, imm: i64 },
	OpImm32 { op: OpImm32Op, rd: XReg, rs1: XReg, imm: i64 },
	Store { op: StoreOp, rs1: XReg, rs2: XReg, imm: i64 },
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum MemoryBase {
	XReg(XReg),
	XRegSh1(XReg),
	XRegSh2(XReg),
	XRegSh3(XReg),
	Pc,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum MemoryOffset {
	Imm(i64),
	XReg(XReg),
}

macro_rules! decode_imm {
	(
		@inner
		$inst:tt u _
		{ $($result:tt)* }
		{ }
	) => {
		{ let $inst = u64::from($inst); u64::from($($result)*).cast_signed() }
	};

	(
		@inner
		$inst:tt i $ext_pos:tt
		{ $($result:tt)* }
		{ }
	) => {
		{ let $inst = u64::from($inst); (u64::from($($result)*).cast_signed() << (63 - $ext_pos)) >> (63 - $ext_pos) }
	};

	(
		@inner
		$inst:tt $ext_ty:tt $ext_pos:tt
		{ $($result:tt)* }
		{ [$($i:tt)*] => $j:tt : $($rest:tt)* }
	) => {
		decode_imm! {
			@inner
			$inst $ext_ty $ext_pos
			{ $($result)* | ((($inst >> ($($i)*)) & 1) << $j) }
			{ [$($i)* + 1] => $($rest)* }
		}
	};

	(
		@inner
		$inst:tt $ext_ty:tt $ext_pos:tt
		{ $($result:tt)* }
		{ [$($i:tt)*] => $j:tt , $($maps:tt)* }
	) => {
		decode_imm! {
			@inner
			$inst $ext_ty $ext_pos
			{ $($result)* | ((($inst >> ($($i)*)) & 1) << $j) }
			{ $($maps)* }
		}
	};

	($inst:tt, $ext_ty:tt $ext_pos:tt, $($maps:tt)*) => {
		decode_imm! {
			@inner
			$inst $ext_ty $ext_pos
			{ 0 }
			{ $($maps)* }
		}
	};
}

impl Instruction {
	pub(crate) fn decode(inst: u32) -> Result<(Self, i64), ()> {
		Ok(match inst & 0b11 {
			0b00 => {
				#[allow(clippy::cast_possible_truncation)]
				let inst = inst as u16;

				let inst = match (inst >> 13) & 0b111 {
					0b000 => {
						#[allow(clippy::verbose_bit_mask)]
						if (inst >> 2) & 0x7ff == 0 {
							return Err(());
						}

						let rd = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[5] => 3:2:6:7:8:9:4:5,
						);

						Instruction::OpImm { op: OpImmOp::Addi, rd, rs1: XReg::X2, imm }
					},

					0b010 => {
						let rd = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[5] => 6:2,
							[10] => 3:4:5,
						);

						Instruction::Load { op: LoadOp::Word, rd, base: MemoryBase::XReg(rs1), offset: MemoryOffset::Imm(imm) }
					},

					0b011 => {
						let rd = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[5] => 6:7,
							[10] => 3:4:5,
						);

						Instruction::Load { op: LoadOp::DoubleWord, rd, base: MemoryBase::XReg(rs1), offset: MemoryOffset::Imm(imm) }
					},

					0b100 => {
						let rd_rs2 = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");
						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						match (inst >> 10) & 0b111 {
							0b000 => {
								let imm = decode_imm!(
									inst, u _,
									[5] => 1:0,
								);

								Instruction::Load { op: LoadOp::ByteUnsigned, rd: rd_rs2, base: MemoryBase::XReg(rs1), offset: MemoryOffset::Imm(imm) }
							},

							0b001 => {
								let op = if (inst >> 6) & 0b1 == 0 { LoadOp::HalfWordUnsigned } else { LoadOp::HalfWord };

								let imm = decode_imm!(
									inst, u _,
									[5] => 1,
								);

								Instruction::Load { op, rd: rd_rs2, base: MemoryBase::XReg(rs1), offset: MemoryOffset::Imm(imm) }
							},

							0b010 => {
								let imm = decode_imm!(
									inst, u _,
									[5] => 1:0,
								);

								Instruction::Store { op: StoreOp::Byte, rs1, rs2: rd_rs2, imm }
							},

							0b011 => {
								if (inst >> 6) & 1 != 0 {
									return Err(());
								}

								let imm = decode_imm!(
									inst, u _,
									[5] => 1,
								);

								Instruction::Store { op: StoreOp::HalfWord, rs1, rs2: rd_rs2, imm }
							},

							_ => return Err(()),
						}
					},

					0b110 => {
						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let rs2 = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[5] => 6:2,
							[10] => 3:4:5,
						);

						Instruction::Store { op: StoreOp::Word, rs1, rs2, imm }
					},

					0b111 => {
						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let rs2 = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[5] => 6:7,
							[10] => 3:4:5,
						);

						Instruction::Store { op: StoreOp::DoubleWord, rs1, rs2, imm }
					},

					_ => return Err(()),
				};
				(inst, 2)
			},

			0b01 => {
				#[allow(clippy::cast_possible_truncation)]
				let inst = inst as u16;

				let inst = match (inst >> 13) & 0b111 {
					0b000 => {
						let rd_rs1 = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, i 5,
							[2] => 0:1:2:3:4,
							[12] => 5,
						);

						Instruction::OpImm { op: OpImmOp::Addi, rd: rd_rs1, rs1: rd_rs1, imm }
					},

					0b001 => {
						let rd_rs1 = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");
						if rd_rs1 == XReg::X0 {
							return Err(());
						}

						let imm = decode_imm!(
							inst, i 5,
							[2] => 0:1:2:3:4,
							[12] => 5,
						);

						Instruction::OpImm32 { op: OpImm32Op::Addiw, rd: rd_rs1, rs1: rd_rs1, imm }
					},

					0b010 => {
						let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, i 5,
							[2] => 0:1:2:3:4,
							[12] => 5,
						);

						Instruction::OpImm { op: OpImmOp::Addi, rd, rs1: XReg::X0, imm }
					},

					0b011 => {
						let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						if rd == XReg::X2 {
							let imm = decode_imm!(
								inst, i 9,
								[2] => 5:7:8:6:4,
								[12] => 9,
							);

							Instruction::OpImm { op: OpImmOp::Addi, rd: XReg::X2, rs1: XReg::X2, imm }
						}
						else {
							let imm = decode_imm!(
								inst, i 17,
								[2] => 12:13:14:15:16,
								[12] => 17,
							);

							Instruction::Lui { rd, imm }
						}
					},

					0b100 => {
						let rd_rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						match (inst >> 10) & 0b11 {
							0b00 => {
								let imm = decode_imm!(
									inst, u _,
									[2] => 0:1:2:3:4,
									[12] => 5,
								);

								Instruction::OpImm { op: OpImmOp::Srli, rd: rd_rs1, rs1: rd_rs1, imm }
							},

							0b01 => {
								let imm = decode_imm!(
									inst, u _,
									[2] => 0:1:2:3:4,
									[12] => 5,
								);

								Instruction::OpImm { op: OpImmOp::Srai, rd: rd_rs1, rs1: rd_rs1, imm }
							},

							0b10 => {
								let imm = decode_imm!(
									inst, i 5,
									[2] => 0:1:2:3:4,
									[12] => 5,
								);

								Instruction::OpImm { op: OpImmOp::Andi, rd: rd_rs1, rs1: rd_rs1, imm }
							},

							0b11 => {
								let rs2 = (((inst >> 2) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

								match (((inst >> 12) & 0b1) << 2) | ((inst >> 5) & 0b11) {
									0b000 => Instruction::Op { op: OpOp::Sub, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b001 => Instruction::Op { op: OpOp::Xor, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b010 => Instruction::Op { op: OpOp::Or, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b011 => Instruction::Op { op: OpOp::And, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b100 => Instruction::Op32 { op: Op32Op::Subw, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b101 => Instruction::Op32 { op: Op32Op::Addw, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b110 => Instruction::Op { op: OpOp::Mul, rd: rd_rs1, rs1: rd_rs1, rs2 },
									0b111 => match (inst >> 2) & 0b111 {
										0b000 => Instruction::OpImm { op: OpImmOp::Andi, rd: rd_rs1, rs1: rd_rs1, imm: 0xff },
										0b001 => Instruction::OpImm { op: OpImmOp::SextB, rd: rd_rs1, rs1: rd_rs1, imm: 0 },
										0b010 => Instruction::Op32 { op: Op32Op::ZextH, rd: rd_rs1, rs1: rd_rs1, rs2: XReg::X0 },
										0b011 => Instruction::OpImm { op: OpImmOp::SextH, rd: rd_rs1, rs1: rd_rs1, imm: 0 },
										0b100 => Instruction::Op32 { op: Op32Op::AddUw, rd: rd_rs1, rs1: rd_rs1, rs2: XReg::X0 },
										0b101 => Instruction::OpImm { op: OpImmOp::Xori, rd: rd_rs1, rs1: rd_rs1, imm: -1 },
										_ => return Err(()),
									},
									_ => unreachable!(),
								}
							},

							_ => unreachable!(),
						}
					},

					0b101 => {
						let imm = decode_imm! {
							inst, i 11,
							[2] => 5:1:2:3:7:6:10:8:9:4:11,
						};

						Instruction::Jal { rd: XReg::X0, imm }
					},

					0b110 => {
						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm! {
							inst, i 8,
							[2] => 5:1:2:6:7,
							[10] => 3:4:8,
						};

						Instruction::Branch { op: BranchOp::Equal, rs1, rs2: XReg::X0, imm }
					},

					0b111 => {
						let rs1 = (((inst >> 7) & 0b111) | 0b01000).try_into().expect("guaranteed to be in range");

						let imm = decode_imm! {
							inst, i 8,
							[2] => 5:1:2:6:7,
							[10] => 3:4:8,
						};

						Instruction::Branch { op: BranchOp::NotEqual, rs1, rs2: XReg::X0, imm }
					},

					_ => unreachable!(),
				};
				(inst, 2)
			},

			0b10 => {
				#[allow(clippy::cast_possible_truncation)]
				let inst = inst as u16;

				let inst = match (inst >> 13) & 0b111 {
					0b000 => {
						let rd_rs1 = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[2] => 0:1:2:3:4,
							[12] => 5,
						);

						Instruction::OpImm { op: OpImmOp::Slli, rd: rd_rs1, rs1: rd_rs1, imm }
					},

					0b010 => {
						let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[2] => 6:7:2:3:4,
							[12] => 5,
						);

						Instruction::Load { op: LoadOp::Word, rd, base: MemoryBase::XReg(XReg::X2), offset: MemoryOffset::Imm(imm) }
					},

					0b011 => {
						let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[2] => 6:7:8:3:4,
							[12] => 5,
						);

						Instruction::Load { op: LoadOp::DoubleWord, rd, base: MemoryBase::XReg(XReg::X2), offset: MemoryOffset::Imm(imm) }
					},

					#[allow(clippy::verbose_bit_mask)]
					0b100 => match ((inst >> 7) & 0x1f == 0, (inst >> 2) & 0x1f == 0) {
						(true, true) => {
							if (inst >> 12) & 0b1 == 0 {
								return Err(());
							}
							Instruction::Ebreak
						},

						(false, true) => {
							let rd = ((inst >> 12) & 0b1).try_into().expect("guaranted to be in range");

							let rs1 = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

							Instruction::Jalr { rd, rs1, imm: 0 }
						},

						(false, false) => {
							let rd_rs1 = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

							let rs2 = ((inst >> 2) & 0x1f).try_into().expect("guaranteed to be in range");

							if (inst >> 12) & 0b1 == 0 {
								Instruction::Op { op: OpOp::Add, rd: rd_rs1, rs1: XReg::X0, rs2 }
							}
							else {
								Instruction::Op { op: OpOp::Add, rd: rd_rs1, rs1: rd_rs1, rs2 }
							}
						},

						(true, false) => return Err(()),
					},

					0b110 => {
						let rs2 = ((inst >> 2) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[7] => 6:7:2:3:4:5,
						);

						Instruction::Store { op: StoreOp::Word, rs1: XReg::X2, rs2, imm }
					},

					0b111 => {
						let rs2 = ((inst >> 2) & 0x1f).try_into().expect("guaranteed to be in range");

						let imm = decode_imm!(
							inst, u _,
							[7] => 6:7:8:3:4:5,
						);

						Instruction::Store { op: StoreOp::DoubleWord, rs1: XReg::X2, rs2, imm }
					},

					_ => return Err(()),
				};
				(inst, 2)
			},

			0b11 => {
				let inst = match (inst >> 2) & 0x1f {
					0b00000 => {
						let FormattedInstructionI { rd, rs1, funct3, imm } = inst.into();
						let op = funct3.try_into()?;
						Instruction::Load { op, rd, base: MemoryBase::XReg(rs1), offset: MemoryOffset::Imm(imm) }
					},

					0b00011 => Instruction::Fence,

					0b00100 => {
						let FormattedInstructionI { rd, rs1, funct3, imm } = inst.into();
						let op = (funct3, imm).try_into()?;
						Instruction::OpImm { op, rd, rs1, imm }
					},

					0b00101 => {
						let FormattedInstructionU { rd, imm } = inst.into();
						Instruction::Auipc { rd, imm }
					},

					0b00110 => {
						let FormattedInstructionI { rd, rs1, funct3, imm } = inst.into();
						let op = (funct3, imm).try_into()?;
						Instruction::OpImm32 { op, rd, rs1, imm }
					},

					0b01000 => {
						let FormattedInstructionS { rs1, rs2, funct3, imm } = inst.into();
						let op = funct3.try_into()?;
						Instruction::Store { op, rs1, rs2, imm }
					},

					0b01100 => {
						let FormattedInstructionR { rd, rs1, rs2, funct3, funct7 } = inst.into();
						let op = (funct3, funct7).try_into()?;
						Instruction::Op { op, rd, rs1, rs2 }
					},

					0b01101 => {
						let FormattedInstructionU { rd, imm } = inst.into();
						Instruction::Lui { rd, imm }
					},

					0b01110 => {
						let FormattedInstructionR { rd, rs1, rs2, funct3, funct7 } = inst.into();
						let op = (funct3, funct7, rs2.into()).try_into()?;
						Instruction::Op32 { op, rd, rs1, rs2 }
					},

					0b11000 => {
						let FormattedInstructionB { rs1, rs2, funct3, imm } = inst.into();
						let op = funct3.try_into()?;
						Instruction::Branch { op, rs1, rs2, imm }
					},

					0b11001 => {
						let FormattedInstructionI { rd, rs1, funct3, imm } = inst.into();
						match funct3 {
							0b000 => Instruction::Jalr { rd, rs1, imm },
							_ => return Err(()),
						}
					},

					0b11100 => {
						let funct3 = (inst >> 12) & 0x7;
						match funct3 {
							0b000 => Instruction::Ebreak,

							0b001 => Instruction::Csrrw {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								rs1: ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range"),
							},

							0b010 => Instruction::Csrrs {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								rs1: ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range"),
							},

							0b011 => Instruction::Csrrc {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								rs1: ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range"),
							},

							0b101 => Instruction::Csrrwi {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								imm: ((inst >> 15) & 0x1f).into(),
							},

							0b110 => Instruction::Csrrsi {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								imm: ((inst >> 15) & 0x1f).into(),
							},

							0b111 => Instruction::Csrrci {
								rd: ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range"),
								csr: ((inst >> 20) & 0xfff).try_into().expect("unimplemented CSR"),
								imm: ((inst >> 15) & 0x1f).into(),
							},

							_ => return Err(()),
						}
					},

					0b11011 => {
						let FormattedInstructionJ { rd, imm } = inst.into();
						Instruction::Jal { rd, imm }
					},

					_ => return Err(()),
				};

				(inst, 4)
			},

			_ => unreachable!(),
		})
	}
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum OpOp {
	Add,
	And,
	Andn,
	Bclr,
	Bext,
	Binv,
	Bset,
	CzeroEqz,
	CzeroNez,
	Max,
	Maxu,
	Min,
	Minu,
	Mul,
	Mulh,
	Mulhsu,
	Mulhu,
	Or,
	Orn,
	Rol,
	Ror,
	Sh1add,
	Sh2add,
	Sh3add,
	Sll,
	Slt,
	Sltu,
	Sra,
	Srl,
	Sub,
	Xnor,
	Xor,
}

impl TryFrom<(u8, u8)> for OpOp {
	type Error = ();

	fn try_from((funct3, funct7): (u8, u8)) -> Result<Self, Self::Error> {
		Ok(match (funct3, funct7) {
			(0b000, 0b0000000) => Self::Add,
			(0b000, 0b0000001) => Self::Mul,
			(0b000, 0b0100000) => Self::Sub,
			(0b001, 0b0000000) => Self::Sll,
			(0b001, 0b0000001) => Self::Mulh,
			(0b001, 0b0010100) => Self::Bset,
			(0b001, 0b0100100) => Self::Bclr,
			(0b001, 0b0110000) => Self::Rol,
			(0b001, 0b0110100) => Self::Binv,
			(0b010, 0b0000000) => Self::Slt,
			(0b010, 0b0000001) => Self::Mulhsu,
			(0b010, 0b0010000) => Self::Sh1add,
			(0b011, 0b0000000) => Self::Sltu,
			(0b011, 0b0000001) => Self::Mulhu,
			(0b100, 0b0000000) => Self::Xor,
			(0b100, 0b0000101) => Self::Min,
			(0b100, 0b0010000) => Self::Sh2add,
			(0b100, 0b0100000) => Self::Xnor,
			(0b101, 0b0000000) => Self::Srl,
			(0b101, 0b0000101) => Self::Minu,
			(0b101, 0b0000111) => Self::CzeroEqz,
			(0b101, 0b0100000) => Self::Sra,
			(0b101, 0b0100100) => Self::Bext,
			(0b101, 0b0110000) => Self::Ror,
			(0b110, 0b0000000) => Self::Or,
			(0b110, 0b0000101) => Self::Max,
			(0b110, 0b0010000) => Self::Sh3add,
			(0b110, 0b0100000) => Self::Orn,
			(0b111, 0b0000000) => Self::And,
			(0b111, 0b0000101) => Self::Maxu,
			(0b111, 0b0000111) => Self::CzeroNez,
			(0b111, 0b0100000) => Self::Andn,
			_ => return Err(()),
		})
	}
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum Op32Op {
	AddUw,
	Addw,
	Mulw,
	Rolw,
	Rorw,
	Sh1addUw,
	Sh2addUw,
	Sh3addUw,
	Sllw,
	Sraw,
	Srlw,
	Subw,
	ZextH,
}

impl TryFrom<(u8, u8, u8)> for Op32Op {
	type Error = ();

	fn try_from((funct3, funct7, funct5): (u8, u8, u8)) -> Result<Self, Self::Error> {
		Ok(match (funct3, funct7) {
			(0b000, 0b0000000) => Self::Addw,
			(0b000, 0b0000001) => Self::Mulw,
			(0b000, 0b0000100) => Self::AddUw,
			(0b000, 0b0100000) => Self::Subw,
			(0b001, 0b0000000) => Self::Sllw,
			(0b001, 0b0110000) => Self::Rolw,
			(0b010, 0b0010000) => Self::Sh1addUw,
			(0b100, 0b0000100) => match funct5 {
				0b00000 => Self::ZextH,
				_ => return Err(()),
			},
			(0b100, 0b0010000) => Self::Sh2addUw,
			(0b101, 0b0000000) => Self::Srlw,
			(0b101, 0b0100000) => Self::Sraw,
			(0b101, 0b0110000) => Self::Rorw,
			(0b110, 0b0010000) => Self::Sh3addUw,
			_ => return Err(()),
		})
	}
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum OpImmOp {
	Addi,
	Andi,
	Bclri,
	Bexti,
	Binvi,
	Bseti,
	Clz,
	Cpop,
	Ctz,
	OrcB,
	Ori,
	Rev8,
	Rori,
	SextB,
	SextH,
	Slli,
	Slti,
	Sltiu,
	Srai,
	Srli,
	Xori,
}

impl TryFrom<(u8, i64)> for OpImmOp {
	type Error = ();

	fn try_from((funct3, imm): (u8, i64)) -> Result<Self, Self::Error> {
		Ok(match funct3 {
			0b000 => Self::Addi,
			0b001 => match (imm >> 6) & 0x3f {
				0b000000 => Self::Slli,
				0b001010 => Self::Bseti,
				0b010010 => Self::Bclri,
				0b011000 => match imm & 0x3f {
					0b000000 => Self::Clz,
					0b000001 => Self::Ctz,
					0b000010 => Self::Cpop,
					0b000100 => Self::SextB,
					0b000101 => Self::SextH,
					_ => return Err(()),
				},
				0b011010 => Self::Binvi,
				_ => return Err(()),
			},
			0b010 => Self::Slti,
			0b011 => Self::Sltiu,
			0b100 => Self::Xori,
			0b101 => match (imm >> 6) & 0x3f {
				0b000000 => Self::Srli,
				0b001010 => match imm & 0x3f {
					0b000111 => Self::OrcB,
					_ => return Err(()),
				},
				0b010000 => Self::Srai,
				0b010010 => Self::Bexti,
				0b011000 => Self::Rori,
				0b011010 => match imm & 0x3f {
					0b111000 => Self::Rev8,
					_ => return Err(()),
				},
				_ => return Err(()),
			},
			0b110 => Self::Ori,
			0b111 => Self::Andi,
			_ => return Err(()),
		})
	}
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum OpImm32Op {
	Addiw,
	Clzw,
	Cpopw,
	Ctzw,
	Roriw,
	SlliUw,
	Slliw,
	Sraiw,
	Srliw,
}

impl TryFrom<(u8, i64)> for OpImm32Op {
	type Error = ();

	fn try_from((funct3, imm): (u8, i64)) -> Result<Self, Self::Error> {
		Ok(match funct3 {
			0b000 => Self::Addiw,
			0b001 => match (imm >> 5) & 0x7f {
				0b0000000 => Self::Slliw,
				0b0000100 |
				0b0000101 => Self::SlliUw,
				0b0110000 => match imm & 0x1f {
					0b00000 => Self::Clzw,
					0b00001 => Self::Ctzw,
					0b00010 => Self::Cpopw,
					_ => return Err(()),
				},
				_ => return Err(()),
			},
			0b101 => match (imm >> 5) & 0x7f {
				0b0000000 => Self::Srliw,
				0b0100000 => Self::Sraiw,
				0b0110000 => Self::Roriw,
				_ => return Err(()),
			},
			_ => return Err(()),
		})
	}
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum BranchOp {
	Equal,
	NotEqual,
	LessThan,
	GreaterThanOrEqual,
	LessThanUnsigned,
	GreaterThanOrEqualUnsigned,
}

impl BranchOp {
	pub(crate) fn exec(self, arg1: i64, arg2: i64) -> bool {
		match self {
			Self::Equal => arg1 == arg2,
			Self::NotEqual => arg1 != arg2,
			Self::LessThan => arg1 < arg2,
			Self::GreaterThanOrEqual => arg1 >= arg2,
			Self::LessThanUnsigned => arg1.cast_unsigned() < arg2.cast_unsigned(),
			Self::GreaterThanOrEqualUnsigned => arg1.cast_unsigned() >= arg2.cast_unsigned(),
		}
	}
}

impl TryFrom<u8> for BranchOp {
	type Error = ();

	fn try_from(funct3: u8) -> Result<Self, Self::Error> {
		Ok(match funct3 {
			0b000 => Self::Equal,
			0b001 => Self::NotEqual,
			0b100 => Self::LessThan,
			0b101 => Self::GreaterThanOrEqual,
			0b110 => Self::LessThanUnsigned,
			0b111 => Self::GreaterThanOrEqualUnsigned,
			_ => return Err(()),
		})
	}
}

struct FormattedInstructionR {
	rd: XReg,
	rs1: XReg,
	rs2: XReg,
	funct3: u8,
	funct7: u8,
}

impl From<u32> for FormattedInstructionR {
	fn from(inst: u32) -> Self {
		let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

		let rs1 = ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range");

		let rs2 = ((inst >> 20) & 0x1f).try_into().expect("guaranteed to be in range");

		let funct3 = ((inst >> 12) & 0x7).try_into().expect("guaranteed to be in range");

		let funct7 = ((inst >> 25) & 0x3f).try_into().expect("guaranteed to be in range");

		Self { rd, rs1, rs2, funct3, funct7 }
	}
}

struct FormattedInstructionI {
	rd: XReg,
	rs1: XReg,
	funct3: u8,
	imm: i64,
}

impl From<u32> for FormattedInstructionI {
	fn from(inst: u32) -> Self {
		let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

		let rs1 = ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range");

		let funct3 = ((inst >> 12) & 0x7).try_into().expect("guaranteed to be in range");

		let imm = inst & (0xfff_u32 << 20);
		let imm = (imm.cast_signed() >> 20).into();

		Self { rd, rs1, funct3, imm }
	}
}

struct FormattedInstructionS {
	rs1: XReg,
	rs2: XReg,
	funct3: u8,
	imm: i64,
}

impl From<u32> for FormattedInstructionS {
	fn from(inst: u32) -> Self {
		let rs1 = ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range");

		let rs2 = ((inst >> 20) & 0x1f).try_into().expect("guaranteed to be in range");

		let funct3 = ((inst >> 12) & 0x7).try_into().expect("guaranteed to be in range");

		let imm =
			(inst & (0x7f << 25)) |
			((inst & (0x1f << 7)) << 13);
		let imm = (imm.cast_signed() >> 20).into();

		Self { rs1, rs2, funct3, imm }
	}
}

struct FormattedInstructionB {
	rs1: XReg,
	rs2: XReg,
	funct3: u8,
	imm: i64,
}

impl From<u32> for FormattedInstructionB {
	fn from(inst: u32) -> Self {
		let rs1 = ((inst >> 15) & 0x1f).try_into().expect("guaranteed to be in range");

		let rs2 = ((inst >> 20) & 0x1f).try_into().expect("guaranteed to be in range");

		let funct3 = ((inst >> 12) & 0x7).try_into().expect("guaranteed to be in range");

		let imm =
			(inst & (0x1 << 31)) |
			((inst & (0x3f << 25)) >> 1) |
			((inst & (0xf << 8)) << 12) |
			((inst & (0x1 << 7)) << 23);
		let imm = (imm.cast_signed() >> 19).into();

		Self { rs1, rs2, funct3, imm }
	}
}

struct FormattedInstructionU {
	rd: XReg,
	imm: i64,
}

impl From<u32> for FormattedInstructionU {
	fn from(inst: u32) -> Self {
		let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

		let imm = inst & (0xfffff_u32 << 12);
		let imm = imm.cast_signed().into();

		Self { rd, imm }
	}
}

struct FormattedInstructionJ {
	rd: XReg,
	imm: i64,
}

impl From<u32> for FormattedInstructionJ {
	fn from(inst: u32) -> Self {
		let rd = ((inst >> 7) & 0x1f).try_into().expect("guaranteed to be in range");

		let imm =
			(inst & (0x1 << 31)) |
			((inst & (0x3ff << 21)) >> 9) |
			((inst & (0x1 << 20)) << 2) |
			((inst & (0xff << 12)) << 11);
		let imm = (imm.cast_signed() >> 11).into();

		Self { rd, imm }
	}
}
