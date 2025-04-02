#![allow(clippy::unreadable_literal)]

use crate::{
	RegisterValue,
	csrs::{Csr, Csrs},
	instruction::{
		Instruction,
		BranchOp,
		OpOp, Op32Op,
		OpImmOp, OpImm32Op,
		MemoryBase, MemoryOffset,
	},
	memory::{LoadOp, StoreOp},
	multiplier::I132,
	tag::{Tag, OneTickTags4},
	x_regs::{XReg, XRegs},
};

#[derive(Clone, Copy, Debug)]
pub(crate) enum Ucode {
	BinaryOp { op: BinaryOp, rd: (XReg, Tag, Option<i64>), rs1: RegisterValue, rs2: RegisterValue },
	Csel { rd: (XReg, Tag, Option<i64>), rcond: RegisterValue, rs_eqz: RegisterValue, rs_nez: RegisterValue },
	Ebreak,
	Fence,
	Jump { pc: RegisterValue, predicted_next_pc: i64 },
	Mul { op: MulOp, rd: (XReg, Tag, Option<i64>), rs1: RegisterValue, rs2: RegisterValue, state: Option<(u8, I132)> },
	Mv { rd: (XReg, Tag), value: RegisterValue },
	MvCsr { csr: (Csr, Tag), value: RegisterValue },
	Load { op: LoadOp, rd: (XReg, Tag, Option<i64>), addr: RegisterValue },
	Store { op: StoreOp, addr: RegisterValue, value: RegisterValue },
	UnaryOp { op: UnaryOp, rd: (XReg, Tag, Option<i64>), rs: RegisterValue },
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum UnaryOp {
	Cpop,
	Cpopw,
	OrcB,
	SextB,
	SextH,
	SextW,
	ZextB,
	ZextH,
	ZextW,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum BinaryOp {
	Add,
	AddUw,
	Addw,
	And,
	Andn,
	Grev,
	Or,
	Orn,
	Rol,
	Rolw,
	Ror,
	Rorw,
	Sh1add,
	Sh1addUw,
	Sh2add,
	Sh2addUw,
	Sh3add,
	Sh3addUw,
	Sll,
	SllUw,
	Sllw,
	Slt,
	Sltu,
	Sra,
	Sraw,
	Srl,
	Srlw,
	Sub,
	Subw,
	Xnor,
	Xor,
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum MulOp {
	Mul,
	Mulh,
	Mulhsu,
	Mulhu,
	Mulw,
}

impl Ucode {
	pub(crate) fn new(
		inst: Instruction,
		pc: i64,
		next_inst_pc: i64,
		predicted_next_pc: i64,
		x_regs: &mut XRegs,
		csrs: &mut Csrs,
		tags: OneTickTags4,
	) -> Option<(Self, Option<(Self, Option<(Self, Option<Self>)>)>)> {
		fn try_rename_x_reg(
			rd: XReg,
			x_regs: &mut XRegs,
			tag: Tag,
		) -> Option<(XReg, Tag, Option<i64>)> {
			x_regs.rename(rd, tag).then_some((rd, tag, None))
		}

		fn assign_x_reg(
			rd: XReg,
			rs: RegisterValue,
			x_regs: &mut XRegs,
			tag: Tag,
		) -> Option<Ucode> {
			match rs {
				RegisterValue::Value(value) => {
					let (rd, tag, _) = try_rename_x_reg(rd, x_regs, tag)?;
					Some(Ucode::Mv { rd: (rd, tag), value: RegisterValue::Value(value) })
				},

				RegisterValue::Tag(tag) =>
					if x_regs.rename(rd, tag) {
						Some(Ucode::Mv { rd: (rd, tag), value: RegisterValue::Tag(tag) })
					}
					else {
						None
					},
			}
		}

		fn try_rename_csr(
			csr: Csr,
			csrs: &mut Csrs,
			tag: Tag,
		) -> Option<(Csr, Tag)> {
			csrs.rename(csr, tag).then_some((csr, tag))
		}

		fn assign_csr(
			csr: Csr,
			rs: RegisterValue,
			csr_load_value_and_op: Option<(RegisterValue, BinaryOp, Tag)>,
			csrs: &mut Csrs,
			tag_licsr: Tag,
		) -> Option<(Ucode, Option<Ucode>)> {
			if let Some((csr_load_value, op, tag_op)) = csr_load_value_and_op {
				let csr = try_rename_csr(csr, csrs, tag_licsr)?;
				Some((
					Ucode::BinaryOp { op, rd: (XReg::X0, tag_op, None), rs1: csr_load_value, rs2: rs },
					Some(Ucode::MvCsr { csr, value: RegisterValue::Tag(tag_op) }),
				))
			}
			else {
				match rs {
					RegisterValue::Value(_) => {
						let csr = try_rename_csr(csr, csrs, tag_licsr)?;
						Some((
							Ucode::MvCsr { csr, value: rs },
							None,
						))
					},

					RegisterValue::Tag(tag) =>
						if csrs.rename(csr, tag) {
							Some((
								Ucode::MvCsr { csr: (csr, tag), value: rs },
								None
							))
						}
						else {
							None
						},
				}
			}
		}

		#[allow(clippy::match_same_arms)]
		match inst {
			Instruction::Abs { rd, rs } => {
				let rs = x_regs.load(rs);
				let (tag_czero, tags) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_czero)?;

				let (tag_sltz, tags) = tags.allocate();
				let inst_sltz = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag_sltz, None), rs1: rs, rs2: RegisterValue::Value(0) };

				let (tag_neg, _) = tags.allocate();
				let inst_neg = Self::BinaryOp { op: BinaryOp::Sub, rd: (XReg::X0, tag_neg, None), rs1: RegisterValue::Value(0), rs2: rs };

				let inst_czero = Self::Csel { rd, rcond: RegisterValue::Tag(tag_sltz), rs_eqz: rs, rs_nez: RegisterValue::Tag(tag_neg) };

				Some((inst_sltz, Some((inst_neg, Some((inst_czero, None))))))
			},

			Instruction::Auipc { rd, imm: 0 } => {
				let (tag_li, _) = tags.allocate();
				let inst_li = assign_x_reg(rd, RegisterValue::Value(pc), x_regs, tag_li)?;
				Some((inst_li, None))
			},

			Instruction::Auipc { rd, imm } => {
				let (tag_add, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_add)?;
				Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) }, None))
			},

			Instruction::Branch { op, rs1, rs2, imm } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);

				let (tag_op, tags) = tags.allocate();
				let (tag_add, tags) = tags.allocate();
				let (op, rs_eqz, rs_nez) = match op {
					BranchOp::Equal => (BinaryOp::Xor, RegisterValue::Tag(tag_add), RegisterValue::Value(next_inst_pc)),
					BranchOp::NotEqual => (BinaryOp::Xor, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag_add)),
					BranchOp::LessThan => (BinaryOp::Slt, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag_add)),
					BranchOp::GreaterThanOrEqual => (BinaryOp::Slt, RegisterValue::Tag(tag_add), RegisterValue::Value(next_inst_pc)),
					BranchOp::LessThanUnsigned => (BinaryOp::Sltu, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag_add)),
					BranchOp::GreaterThanOrEqualUnsigned => (BinaryOp::Sltu, RegisterValue::Tag(tag_add), RegisterValue::Value(next_inst_pc)),
				};

				let inst_op = Self::BinaryOp { op, rd: (XReg::X0, tag_op, None), rs1, rs2 };

				let inst_add = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_add, None), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) };

				let (tag_czero, _) = tags.allocate();
				let inst_czero = Self::Csel { rd: (XReg::X0, tag_czero, None), rcond: RegisterValue::Tag(tag_op), rs_eqz, rs_nez };

				let inst_jump = Self::Jump { pc: RegisterValue::Tag(tag_czero), predicted_next_pc };

				Some((inst_op, Some((inst_add, Some((inst_czero, Some(inst_jump)))))))
			},

			Instruction::Csrrw { rd, rs1, csr } => {
				let rs1 = x_regs.load(rs1);
				let (tag_li, tags) = tags.allocate();
				let inst_li =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_x_reg(rd, csr_load_value, x_regs, tag_li)
					};

				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr = assign_csr(
					csr,
					rs1,
					None,
					csrs,
					tag_licsr,
				);

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Csrrwi { rd, imm, csr } => {
				let (tag_li, tags) = tags.allocate();
				let inst_li =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_x_reg(rd, csr_load_value, x_regs, tag_li)
					};

				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr = assign_csr(
					csr,
					RegisterValue::Value(imm),
					None,
					csrs,
					tag_licsr,
				);

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Csrrs { rd, rs1, csr } => {
				let rs1 =
					if rs1 == XReg::X0 {
						None
					}
					else {
						Some(x_regs.load(rs1))
					};
				let csr_load_value = csrs.load(csr);

				let (tag_li, tags) = tags.allocate();
				let inst_li = assign_x_reg(rd, csr_load_value, x_regs, tag_li);

				let (tag_op, tags) = tags.allocate();
				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr = rs1.and_then(|rs1| assign_csr(
					csr,
					rs1,
					Some((csr_load_value, BinaryOp::Or, tag_op)),
					csrs,
					tag_licsr,
				));

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Csrrsi { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let (tag_li, tags) = tags.allocate();
				let inst_li = assign_x_reg(rd, csr_load_value, x_regs, tag_li);

				let (tag_op, tags) = tags.allocate();
				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr =
					if imm == 0 {
						None
					}
					else {
						assign_csr(
							csr,
							RegisterValue::Value(imm),
							Some((csr_load_value, BinaryOp::Or, tag_op)),
							csrs,
							tag_licsr,
						)
					};

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Csrrc { rd, rs1, csr } => {
				let rs1 =
					if rs1 == XReg::X0 {
						None
					}
					else {
						Some(x_regs.load(rs1))
					};
				let csr_load_value = csrs.load(csr);

				let (tag_li, tags) = tags.allocate();
				let inst_li = assign_x_reg(rd, csr_load_value, x_regs, tag_li);

				let (tag_op, tags) = tags.allocate();
				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr = rs1.and_then(|rs1| assign_csr(
					csr,
					rs1,
					Some((csr_load_value, BinaryOp::Andn, tag_op)),
					csrs,
					tag_licsr,
				));

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Csrrci { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let (tag_li, tags) = tags.allocate();
				let inst_li = assign_x_reg(rd, csr_load_value, x_regs, tag_li);

				let (tag_op, tags) = tags.allocate();
				let (tag_licsr, _) = tags.allocate();
				let inst_assign_csr =
					if imm == 0 {
						None
					}
					else {
						assign_csr(
							csr,
							RegisterValue::Value(imm),
							Some((csr_load_value, BinaryOp::Andn, tag_op)),
							csrs,
							tag_licsr,
						)
					};

				match (inst_li, inst_assign_csr) {
					(None, None) => None,
					(None, Some((inst_licsr, None))) => Some((inst_licsr, None)),
					(None, Some((inst_op, Some(inst_licsr)))) => Some((inst_op, Some((inst_licsr, None)))),
					(Some(inst_li), None) => Some((inst_li, None)),
					(Some(inst_li), Some((inst_licsr, None))) => Some((inst_li, Some((inst_licsr, None)))),
					(Some(inst_li), Some((inst_op, Some(inst_licsr)))) => Some((inst_li, Some((inst_op, Some((inst_licsr, None)))))),
				}
			},

			Instruction::Ebreak => Some((Self::Ebreak, None)),

			Instruction::Fence => Some((Self::Fence, None)),

			Instruction::Jal { rd, imm: _ } => {
				// `predicted_next_pc` is already correct
				let inst_jump = Self::Jump { pc: RegisterValue::Value(predicted_next_pc), predicted_next_pc };
				let (tag_next_inst_pc, _) = tags.allocate();
				let inst_next_inst_pc = assign_x_reg(rd, RegisterValue::Value(next_inst_pc), x_regs, tag_next_inst_pc);
				match inst_next_inst_pc {
					None => Some((inst_jump, None)),
					Some(inst_next_inst_pc) => Some((inst_next_inst_pc, Some((inst_jump, None)))),
				}
			},

			// ret
			Instruction::Jalr { rd, rs1, imm: 0 } => {
				let rs1 = x_regs.load(rs1);

				let (tag_next_inst_pc, _) = tags.allocate();
				let inst_next_inst_pc = assign_x_reg(rd, RegisterValue::Value(next_inst_pc), x_regs, tag_next_inst_pc);

				let inst_jump = Self::Jump { pc: rs1, predicted_next_pc };

				match inst_next_inst_pc {
					None => Some((inst_jump, None)),
					Some(inst_next_inst_pc) => Some((inst_next_inst_pc, Some((inst_jump, None)))),
				}
			},

			Instruction::Jalr { rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let (tag_pc, tags) = tags.allocate();
				let inst_pc = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_pc, None), rs1, rs2: RegisterValue::Value(imm) };

				let (tag_next_inst_pc, _) = tags.allocate();
				let inst_next_inst_pc = assign_x_reg(rd, RegisterValue::Value(next_inst_pc), x_regs, tag_next_inst_pc);

				let inst_jump = Self::Jump { pc: RegisterValue::Tag(tag_pc), predicted_next_pc };

				match inst_next_inst_pc {
					None => Some((inst_pc, Some((inst_jump, None)))),
					Some(inst_next_inst_pc) => Some((inst_pc, Some((inst_next_inst_pc, Some((inst_jump, None)))))),
				}
			},

			Instruction::Load { op, rd, base: MemoryBase::XReg(base), offset: MemoryOffset::Imm(0) } => {
				let base = x_regs.load(base);
				let (tag_load, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_load)?;
				Some((Self::Load { op, rd, addr: base }, None))
			},

			Instruction::Load { op, rd, base, offset } => {
				let (addr_op, base) = match base {
					MemoryBase::XReg(base) => (BinaryOp::Add, x_regs.load(base)),
					MemoryBase::XRegSh1(base) => (BinaryOp::Sh1add, x_regs.load(base)),
					MemoryBase::XRegSh2(base) => (BinaryOp::Sh2add, x_regs.load(base)),
					MemoryBase::XRegSh3(base) => (BinaryOp::Sh3add, x_regs.load(base)),
					MemoryBase::Pc => (BinaryOp::Add, RegisterValue::Value(pc)),
				};

				let offset = match offset {
					MemoryOffset::Imm(offset) => RegisterValue::Value(offset),
					MemoryOffset::XReg(offset) => x_regs.load(offset),
				};

				let (tag_addr, tags) = tags.allocate();
				let inst_addr = Self::BinaryOp { op: addr_op, rd: (XReg::X0, tag_addr, None), rs1: base, rs2: offset };

				let (tag_load, _) = tags.allocate();
				// Must not skip performing the load even if rd is x0,
				// because the load has side effects.
				_ = x_regs.rename(rd, tag_load);
				let inst_load = Self::Load { op, rd: (rd, tag_load, None), addr: RegisterValue::Tag(tag_addr) };

				Some((inst_addr, Some((inst_load, None))))
			},

			Instruction::Lui { rd, imm } => {
				let (tag_li, _) = tags.allocate();
				let inst_li = assign_x_reg(rd, RegisterValue::Value(imm), x_regs, tag_li)?;
				Some((inst_li, None))
			},

			// c.mv
			Instruction::Op { op: OpOp::Add, rd, rs1: XReg::X0, rs2 } => {
				let rs2 = x_regs.load(rs2);
				let (tag_li, _) = tags.allocate();
				let inst_li = assign_x_reg(rd, rs2, x_regs, tag_li)?;
				Some((inst_li, None))
			},

			Instruction::Op { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let (tag_op, tags) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_op)?;
				match op {
					OpOp::Add => Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1, rs2 }, None)),

					OpOp::And => Some((Self::BinaryOp { op: BinaryOp::And, rd, rs1, rs2 }, None)),

					OpOp::Andn => Some((Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2 }, None)),

					OpOp::Bclr => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2 };
						let inst_op = Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpOp::Bext => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Srl, rd: (XReg::X0, tag_shift, None), rs1, rs2 };
						let inst_op = Self::BinaryOp { op: BinaryOp::And, rd, rs1: RegisterValue::Tag(tag_shift), rs2: RegisterValue::Value(1) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpOp::Binv => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2 };
						let inst_op = Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpOp::Bset => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2 };
						let inst_op = Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpOp::CzeroEqz => Some((Self::Csel { rd, rcond: rs2, rs_eqz: RegisterValue::Value(0), rs_nez: rs1 }, None)),

					OpOp::CzeroNez => Some((Self::Csel { rd, rcond: rs2, rs_eqz: rs1, rs_nez: RegisterValue::Value(0) }, None)),

					OpOp::Max => {
						let (tag_slt, _) = tags.allocate();
						let inst_slt = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag_slt, None), rs1, rs2 };
						let inst_czero = Self::Csel { rd, rcond: RegisterValue::Tag(tag_slt), rs_eqz: rs1, rs_nez: rs2 };
						Some((inst_slt, Some((inst_czero, None))))
					},

					OpOp::Maxu => {
						let (tag_sltu, _) = tags.allocate();
						let inst_sltu = Self::BinaryOp { op: BinaryOp::Sltu, rd: (XReg::X0, tag_sltu, None), rs1, rs2 };
						let inst_czero = Self::Csel { rd, rcond: RegisterValue::Tag(tag_sltu), rs_eqz: rs1, rs_nez: rs2 };
						Some((inst_sltu, Some((inst_czero, None))))
					},

					OpOp::Min => {
						let (tag_slt, _) = tags.allocate();
						let inst_slt = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag_slt, None), rs1, rs2 };
						let inst_czero = Self::Csel { rd, rcond: RegisterValue::Tag(tag_slt), rs_eqz: rs2, rs_nez: rs1 };
						Some((inst_slt, Some((inst_czero, None))))
					},

					OpOp::Minu => {
						let (tag_sltu, _) = tags.allocate();
						let inst_sltu = Self::BinaryOp { op: BinaryOp::Sltu, rd: (XReg::X0, tag_sltu, None), rs1, rs2 };
						let inst_czero = Self::Csel { rd, rcond: RegisterValue::Tag(tag_sltu), rs_eqz: rs2, rs_nez: rs1 };
						Some((inst_sltu, Some((inst_czero, None))))
					},

					OpOp::Mul => Some((Self::Mul { op: MulOp::Mul, rd, rs1, rs2, state: None }, None)),

					OpOp::Mulh => Some((Self::Mul { op: MulOp::Mulh, rd, rs1, rs2, state: None }, None)),

					OpOp::Mulhsu => Some((Self::Mul { op: MulOp::Mulhsu, rd, rs1, rs2, state: None }, None)),

					OpOp::Mulhu => Some((Self::Mul { op: MulOp::Mulhu, rd, rs1, rs2, state: None }, None)),

					OpOp::Or => Some((Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2 }, None)),

					OpOp::Orn => Some((Self::BinaryOp { op: BinaryOp::Orn, rd, rs1, rs2 }, None)),

					OpOp::Rol => Some((Self::BinaryOp { op: BinaryOp::Rol, rd, rs1, rs2 }, None)),

					OpOp::Ror => Some((Self::BinaryOp { op: BinaryOp::Ror, rd, rs1, rs2 }, None)),

					OpOp::Sh1add => Some((Self::BinaryOp { op: BinaryOp::Sh1add, rd, rs1, rs2 }, None)),

					OpOp::Sh2add => Some((Self::BinaryOp { op: BinaryOp::Sh2add, rd, rs1, rs2 }, None)),

					OpOp::Sh3add => Some((Self::BinaryOp { op: BinaryOp::Sh3add, rd, rs1, rs2 }, None)),

					OpOp::Sll => Some((Self::BinaryOp { op: BinaryOp::Sll, rd, rs1, rs2 }, None)),

					OpOp::Slt => Some((Self::BinaryOp { op: BinaryOp::Slt, rd, rs1, rs2 }, None)),

					OpOp::Sltu => Some((Self::BinaryOp { op: BinaryOp::Sltu, rd, rs1, rs2 }, None)),

					OpOp::Sra => Some((Self::BinaryOp { op: BinaryOp::Sra, rd, rs1, rs2 }, None)),

					OpOp::Srl => Some((Self::BinaryOp { op: BinaryOp::Srl, rd, rs1, rs2 }, None)),

					OpOp::Sub => Some((Self::BinaryOp { op: BinaryOp::Sub, rd, rs1, rs2 }, None)),

					OpOp::Xnor => Some((Self::BinaryOp { op: BinaryOp::Xnor, rd, rs1, rs2 }, None)),

					OpOp::Xor => Some((Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2 }, None)),
				}
			},

			// zext.w
			Instruction::Op32 { op: Op32Op::AddUw, rd, rs1, rs2: XReg::X0 } => {
				let rs1 = x_regs.load(rs1);
				let (tag_li, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_li)?;
				Some((Self::UnaryOp { op: UnaryOp::ZextW, rd, rs: rs1 }, None))
			},

			Instruction::Op32 { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let (tag_op, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_op)?;
				match op {
					Op32Op::AddUw => Some((Self::BinaryOp { op: BinaryOp::AddUw, rd, rs1, rs2 }, None)),

					Op32Op::Addw => Some((Self::BinaryOp { op: BinaryOp::Addw, rd, rs1, rs2 }, None)),

					Op32Op::Mulw => Some((Self::Mul { op: MulOp::Mulw, rd, rs1, rs2, state: None }, None)),

					Op32Op::Rolw => Some((Self::BinaryOp { op: BinaryOp::Rolw, rd, rs1, rs2 }, None)),

					Op32Op::Rorw => Some((Self::BinaryOp { op: BinaryOp::Rorw, rd, rs1, rs2 }, None)),

					Op32Op::Sh1addUw => Some((Self::BinaryOp { op: BinaryOp::Sh1addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sh2addUw => Some((Self::BinaryOp { op: BinaryOp::Sh2addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sh3addUw => Some((Self::BinaryOp { op: BinaryOp::Sh3addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sllw => Some((Self::BinaryOp { op: BinaryOp::Sllw, rd, rs1, rs2 }, None)),

					Op32Op::Sraw => Some((Self::BinaryOp { op: BinaryOp::Sraw, rd, rs1, rs2 }, None)),

					Op32Op::Srlw => Some((Self::BinaryOp { op: BinaryOp::Srlw, rd, rs1, rs2 }, None)),

					Op32Op::Subw => Some((Self::BinaryOp { op: BinaryOp::Subw, rd, rs1, rs2 }, None)),

					Op32Op::ZextH => Some((Self::UnaryOp { op: UnaryOp::ZextH, rd, rs: rs1 }, None)),
				}
			},

			// mv
			Instruction::OpImm { op: OpImmOp::Addi, rd, rs1, imm: 0 } => {
				let rs1 = x_regs.load(rs1);
				let (tag_li, _) = tags.allocate();
				let inst_li = assign_x_reg(rd, rs1, x_regs, tag_li)?;
				Some((inst_li, None))
			},

			// li
			Instruction::OpImm { op: OpImmOp::Addi, rd, rs1: XReg::X0, imm } => {
				let (tag_li, _) = tags.allocate();
				let inst_li = assign_x_reg(rd, RegisterValue::Value(imm), x_regs, tag_li)?;
				Some((inst_li, None))
			}

			// zext.b
			Instruction::OpImm { op: OpImmOp::Andi, rd, rs1, imm: 0xff } => {
				let rs1 = x_regs.load(rs1);
				let (tag_li, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_li)?;
				Some((Self::UnaryOp { op: UnaryOp::ZextB, rd, rs: rs1 }, None))
			},

			Instruction::OpImm { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let (tag_op, tags) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_op)?;
				match op {
					OpImmOp::Addi => Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Andi => Some((Self::BinaryOp { op: BinaryOp::And, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Bclri => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst_op = Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpImmOp::Bexti => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Srl, rd: (XReg::X0, tag_shift, None), rs1, rs2: RegisterValue::Value(imm) };
						let inst_op = Self::BinaryOp { op: BinaryOp::And, rd, rs1: RegisterValue::Tag(tag_shift), rs2: RegisterValue::Value(1) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpImmOp::Binvi => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst_op = Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpImmOp::Bseti => {
						let (tag_shift, _) = tags.allocate();
						let inst_shift = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag_shift, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst_op = Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2: RegisterValue::Tag(tag_shift) };
						Some((inst_shift, Some((inst_op, None))))
					},

					OpImmOp::Clz => {
						let (tag_grev, tags) = tags.allocate();
						let inst_grev = Self::BinaryOp { op: BinaryOp::Grev, rd: (XReg::X0, tag_grev, None), rs1, rs2: RegisterValue::Value(0b111111) };

						let (tag_add, tags) = tags.allocate();
						let inst_add = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_add, None), rs1: RegisterValue::Tag(tag_grev), rs2: RegisterValue::Value(-1) };

						let tag_andn = tags.allocate();
						let inst_andn = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag_andn, None), rs1: RegisterValue::Tag(tag_add), rs2: RegisterValue::Tag(tag_grev) };

						let inst_cpop = Self::UnaryOp { op: UnaryOp::Cpop, rd, rs: RegisterValue::Tag(tag_andn) };

						Some((inst_grev, Some((inst_add, Some((inst_andn, Some(inst_cpop)))))))
					},

					OpImmOp::Ctz => {
						let (tag_add, tags) = tags.allocate();
						let inst_add = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_add, None), rs1, rs2: RegisterValue::Value(-1) };

						let (tag_andn, _) = tags.allocate();
						let inst_andn = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag_andn, None), rs1: RegisterValue::Tag(tag_add), rs2: rs1 };

						let inst_cpop = Self::UnaryOp { op: UnaryOp::Cpop, rd, rs: RegisterValue::Tag(tag_andn) };

						Some((inst_add, Some((inst_andn, Some((inst_cpop, None))))))
					},

					OpImmOp::Cpop => Some((Self::UnaryOp { op: UnaryOp::Cpop, rd, rs: rs1 }, None)),

					OpImmOp::OrcB => Some((Self::UnaryOp { op: UnaryOp::OrcB, rd, rs: rs1 }, None)),

					OpImmOp::Ori => Some((Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Rev8 => Some((Self::BinaryOp { op: BinaryOp::Grev, rd, rs1, rs2: RegisterValue::Value(0b001000) }, None)),

					OpImmOp::Rori => Some((Self::BinaryOp { op: BinaryOp::Ror, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::SextB => Some((Self::UnaryOp { op: UnaryOp::SextB, rd, rs: rs1 }, None)),

					OpImmOp::SextH => Some((Self::UnaryOp { op: UnaryOp::SextH, rd, rs: rs1 }, None)),

					OpImmOp::Slli => Some((Self::BinaryOp { op: BinaryOp::Sll, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Slti => Some((Self::BinaryOp { op: BinaryOp::Slt, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Sltiu => Some((Self::BinaryOp { op: BinaryOp::Sltu, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Srai => Some((Self::BinaryOp { op: BinaryOp::Sra, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Srli => Some((Self::BinaryOp { op: BinaryOp::Srl, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Xori => Some((Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),
				}
			},

			// sext.w
			Instruction::OpImm32 { op: OpImm32Op::Addiw, rd, rs1, imm: 0 } => {
				let rs1 = x_regs.load(rs1);
				let (tag_li, _) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_li)?;
				Some((Self::UnaryOp { op: UnaryOp::SextW, rd, rs: rs1 }, None))
			},

			Instruction::OpImm32 { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let (tag_op, tags) = tags.allocate();
				let rd = try_rename_x_reg(rd, x_regs, tag_op)?;
				match op {
					OpImm32Op::Addiw => Some((Self::BinaryOp { op: BinaryOp::Addw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Clzw => {
						let (tag_grev, tags) = tags.allocate();
						let inst_grev = Self::BinaryOp { op: BinaryOp::Grev, rd: (XReg::X0, tag_grev, None), rs1, rs2: RegisterValue::Value(0b011111) };

						let (tag_add, tags) = tags.allocate();
						let inst_add = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_add, None), rs1: RegisterValue::Tag(tag_grev), rs2: RegisterValue::Value(-1) };

						let tag_andn = tags.allocate();
						let inst_andn = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag_andn, None), rs1: RegisterValue::Tag(tag_add), rs2: RegisterValue::Tag(tag_grev) };

						let inst_cpopw = Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: RegisterValue::Tag(tag_andn) };

						Some((inst_grev, Some((inst_add, Some((inst_andn, Some(inst_cpopw)))))))
					},

					OpImm32Op::Cpopw => Some((Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: rs1 }, None)),

					OpImm32Op::Ctzw => {
						let (tag_add, tags) = tags.allocate();
						let inst_add = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_add, None), rs1, rs2: RegisterValue::Value(-1) };

						let (tag_andn, _) = tags.allocate();
						let inst_andn = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag_andn, None), rs1: RegisterValue::Tag(tag_add), rs2: rs1 };

						let inst_cpopw = Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: RegisterValue::Tag(tag_andn) };

						Some((inst_add, Some((inst_andn, Some((inst_cpopw, None))))))
					},

					OpImm32Op::Roriw => Some((Self::BinaryOp { op: BinaryOp::Rorw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::SlliUw => Some((Self::BinaryOp { op: BinaryOp::SllUw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Slliw => Some((Self::BinaryOp { op: BinaryOp::Sllw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Sraiw => Some((Self::BinaryOp { op: BinaryOp::Sraw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Srliw => Some((Self::BinaryOp { op: BinaryOp::Srlw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),
				}
			},

			Instruction::Store { op, rs1, rs2, imm: 0 } => {
				let base = x_regs.load(rs1);
				let value = x_regs.load(rs2);
				Some((Self::Store { op, addr: base, value }, None))
			},

			Instruction::Store { op, rs1, rs2, imm } => {
				let base = x_regs.load(rs1);
				let value = x_regs.load(rs2);

				let (tag_addr, _) = tags.allocate();
				let inst_addr = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag_addr, None), rs1: base, rs2: RegisterValue::Value(imm) };

				let inst_store = Self::Store { op, addr: RegisterValue::Tag(tag_addr), value };

				Some((inst_addr, Some((inst_store, None))))
			},
		}
	}

	pub(crate) fn update(&mut self, tag: Tag, new_value: i64) {
		#[allow(clippy::match_same_arms)]
		match self {
			Self::BinaryOp { op: _, rd: _, rs1, rs2 } => {
				rs1.update(tag, new_value);
				rs2.update(tag, new_value);
			},
			Self::Csel { rd: _, rcond, rs_eqz, rs_nez } => {
				rcond.update(tag, new_value);
				rs_eqz.update(tag, new_value);
				rs_nez.update(tag, new_value);
			},
			Self::Ebreak => (),
			Self::Fence => (),
			Self::Jump { pc, predicted_next_pc: _ } => pc.update(tag, new_value),
			Self::Mul { op: _, rd: _, rs1, rs2, state: _ } => {
				rs1.update(tag, new_value);
				rs2.update(tag, new_value);
			},
			Self::Mv { rd: _, value } => value.update(tag, new_value),
			Self::MvCsr { csr: _, value } => value.update(tag, new_value),
			Self::Load { op: _, rd: _, addr } => addr.update(tag, new_value),
			Self::Store { op: _, addr, value } => {
				addr.update(tag, new_value);
				value.update(tag, new_value);
			},
			Self::UnaryOp { op: _, rd: _, rs } => rs.update(tag, new_value),
		}
	}

	pub(crate) fn rd(&self) -> Option<(XReg, Tag, Option<i64>)> {
		match *self {
			Ucode::BinaryOp { rd, .. } |
			Ucode::Csel { rd, .. } |
			Ucode::Load { rd, .. } |
			Ucode::Mul { rd, .. } |
			Ucode::UnaryOp { rd, .. }
				=> Some(rd),

			Ucode::Mv { rd: (rd, tag), value: RegisterValue::Value(value), .. }
				=> Some((rd, tag, Some(value))),

			Ucode::Mv { rd: (rd, tag), value: RegisterValue::Tag(_), .. }
				=> Some((rd, tag, None)),

			Ucode::Ebreak |
			Ucode::Fence |
			Ucode::Jump { .. } |
			Ucode::MvCsr { .. } |
			Ucode::Store { .. }
				=> None,
		}
	}

	pub(crate) fn done_rd(&self) -> Option<(XReg, Tag, i64)> {
		let (rd, rd_tag, value) = self.rd()?;
		Some((rd, rd_tag, value?))
	}

	pub(crate) fn csr(&self) -> Option<(Csr, Tag, Option<i64>)> {
		match *self {
			Ucode::MvCsr { csr: (csr, tag), value: RegisterValue::Value(value) }
				=> Some((csr, tag, Some(value))),

			Ucode::MvCsr { csr: (csr, tag), value: RegisterValue::Tag(_) }
				=> Some((csr, tag, None)),

			_ => None,
		}
	}

	pub(crate) fn done_csr(&self) -> Option<(Csr, Tag, i64)> {
		let (csr, csr_tag, value) = self.csr()?;
		Some((csr, csr_tag, value?))
	}

	pub(crate) fn done(&self) -> bool {
		#[allow(clippy::match_same_arms)]
		match *self {
			Ucode::BinaryOp { rd, .. } |
			Ucode::Csel { rd, .. } |
			Ucode::Mul { rd, .. } |
			Ucode::UnaryOp { rd, .. }
				=> matches!(rd, (_, _, Some(_))),

			Ucode::Ebreak => false,

			Ucode::Fence => false,

			Ucode::Mv { value, .. } |
			Ucode::MvCsr { value, .. }
				=> matches!(value, RegisterValue::Value(_)),

			Ucode::Load { .. } => false,

			Ucode::Jump { pc, .. } => matches!(pc, RegisterValue::Value(_)),

			Ucode::Store { .. } => false,
		}
	}
}
