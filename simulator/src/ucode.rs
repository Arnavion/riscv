#![allow(clippy::unreadable_literal)]

use crate::{
	RegisterValue, Tag,
	csrs::{Csr, Csrs},
	instruction::{
		Instruction,
		BranchOp,
		OpOp, Op32Op,
		OpImmOp, OpImm32Op,
		MemoryBase, MemoryOffset,
	},
	memory::{LoadOp, StoreOp},
	x_regs::{XReg, XRegs},
};

#[derive(Clone, Copy, Debug)]
pub(crate) enum Ucode {
	BinaryOp { op: BinaryOp, rd: (XReg, Tag, Option<i64>), rs1: RegisterValue, rs2: RegisterValue },
	Czero { rd: (XReg, Tag, Option<i64>), rcond: RegisterValue, rs_eqz: RegisterValue, rs_nez: RegisterValue },
	Ebreak,
	Fence,
	Jump { pc: RegisterValue, predicted_next_pc: i64 },
	Li { rd: (XReg, Tag), value: RegisterValue },
	LiCsr { csr: (Csr, Tag), value: RegisterValue },
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
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum BinaryOp {
	Add,
	AddUw,
	Addw,
	And,
	Andn,
	Grev,
	Mul,
	Mulh,
	Mulhsu,
	Mulhu,
	Mulw,
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

impl Ucode {
	pub(crate) fn new(
		inst: Instruction,
		pc: i64,
		next_inst_pc: i64,
		predicted_next_pc: i64,
		x_regs: &mut XRegs,
		csrs: &mut Csrs,
		next_renamed_register_tag: &mut Tag,
	) -> Option<(Self, Option<(Self, Option<(Self, Option<Self>)>)>)> {
		fn try_rename_xreg(
			rd: XReg,
			x_regs: &mut XRegs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<(XReg, Tag, Option<i64>)> {
			let tag = next_renamed_register_tag.allocate_if(|tag| x_regs.rename(rd, tag))?;
			Some((rd, tag, None))
		}

		fn try_rename_csr(
			csr: Csr,
			csrs: &mut Csrs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<(Csr, Tag)> {
			let tag = next_renamed_register_tag.allocate_if(|tag| csrs.rename(csr, tag))?;
			Some((csr, tag))
		}

		fn assign_x_reg(
			rd: XReg,
			rs: RegisterValue,
			x_regs: &mut XRegs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<Ucode> {
			match rs {
				RegisterValue::Value(value) => {
					let (rd, tag, _) = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
					Some(Ucode::Li { rd: (rd, tag), value: RegisterValue::Value(value) })
				},

				RegisterValue::Tag(tag) =>
					if x_regs.rename(rd, tag) {
						Some(Ucode::Li { rd: (rd, tag), value: RegisterValue::Tag(tag) })
					}
					else {
						None
					},
			}
		}

		fn assign_csr(
			csr: Csr,
			rs: Option<RegisterValue>,
			csr_load_value_and_op: Option<(RegisterValue, BinaryOp)>,
			csrs: &mut Csrs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<(Ucode, Option<Ucode>)> {
			let rs = rs?;
			if let Some((csr_load_value, op)) = csr_load_value_and_op {
				let tag = next_renamed_register_tag.allocate();
				let csr = try_rename_csr(csr, csrs, next_renamed_register_tag)?;
				Some((
					Ucode::BinaryOp { op, rd: (XReg::X0, tag, None), rs1: csr_load_value, rs2: rs },
					Some(Ucode::LiCsr { csr, value: RegisterValue::Tag(tag) }),
				))
			}
			else {
				match rs {
					RegisterValue::Value(_) => {
						let csr = try_rename_csr(csr, csrs, next_renamed_register_tag)?;
						Some((
							Ucode::LiCsr { csr, value: rs },
							None,
						))
					},

					RegisterValue::Tag(tag) =>
						if csrs.rename(csr, tag) {
							Some((
								Ucode::LiCsr { csr: (csr, tag), value: rs },
								None
							))
						}
						else {
							None
						},
				}
			}
		}

		match inst {
			Instruction::Abs { rd, rs } => {
				let rs = x_regs.load(rs);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;

				let tag1 = next_renamed_register_tag.allocate();
				let inst1 = Self::BinaryOp { op: BinaryOp::Sub, rd: (XReg::X0, tag1, None), rs1: RegisterValue::Value(0), rs2: rs };

				let tag2 = next_renamed_register_tag.allocate();
				let inst2 = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag2, None), rs1: rs, rs2: RegisterValue::Tag(tag1) };

				let inst3 = Self::Czero { rd, rcond: RegisterValue::Tag(tag2), rs_eqz: rs, rs_nez: RegisterValue::Tag(tag1) };

				Some((inst1, Some((inst2, Some((inst3, None))))))
			},

			Instruction::Auipc { rd, imm } => {
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) }, None))
			},

			Instruction::Branch { op, rs1, rs2, imm } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);

				let tag1 = next_renamed_register_tag.allocate();
				let tag2 = next_renamed_register_tag.allocate();
				let (op, rs_eqz, rs_nez) = match op {
					BranchOp::Equal => (BinaryOp::Xor, RegisterValue::Tag(tag2), RegisterValue::Value(next_inst_pc)),
					BranchOp::NotEqual => (BinaryOp::Xor, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag2)),
					BranchOp::LessThan => (BinaryOp::Slt, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag2)),
					BranchOp::GreaterThanOrEqual => (BinaryOp::Slt, RegisterValue::Tag(tag2), RegisterValue::Value(next_inst_pc)),
					BranchOp::LessThanUnsigned => (BinaryOp::Sltu, RegisterValue::Value(next_inst_pc), RegisterValue::Tag(tag2)),
					BranchOp::GreaterThanOrEqualUnsigned => (BinaryOp::Sltu, RegisterValue::Tag(tag2), RegisterValue::Value(next_inst_pc)),
				};

				let inst1 = Self::BinaryOp { op, rd: (XReg::X0, tag1, None), rs1, rs2 };

				let inst2 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag2, None), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) };

				let tag3 = next_renamed_register_tag.allocate();
				let inst3 = Self::Czero { rd: (XReg::X0, tag3, None), rcond: RegisterValue::Tag(tag1), rs_eqz, rs_nez };

				let inst4 = Self::Jump { pc: RegisterValue::Tag(tag3), predicted_next_pc };

				Some((inst1, Some((inst2, Some((inst3, Some(inst4)))))))
			},

			Instruction::Csrrw { rd, rs1, csr } => {
				let rs1 = x_regs.load(rs1);
				let inst1 =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag)
					};

				let inst23 = assign_csr(
					csr,
					Some(rs1),
					None,
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
			},

			Instruction::Csrrwi { rd, imm, csr } => {
				let inst1 =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag)
					};

				let inst23 = assign_csr(
					csr,
					Some(RegisterValue::Value(imm)),
					None,
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
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

				let inst1 = assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag);

				let inst23 = assign_csr(
					csr,
					rs1,
					Some((csr_load_value, BinaryOp::Or)),
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
			},

			Instruction::Csrrsi { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let inst1 = assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag);

				let inst23 = assign_csr(
					csr,
					(imm != 0).then_some(RegisterValue::Value(imm)),
					Some((csr_load_value, BinaryOp::Or)),
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
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

				let inst1 = assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag);

				let inst23 = assign_csr(
					csr,
					rs1,
					Some((csr_load_value, BinaryOp::Andn)),
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
			},

			Instruction::Csrrci { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let inst1 = assign_x_reg(rd, csr_load_value, x_regs, next_renamed_register_tag);

				let inst23 = assign_csr(
					csr,
					(imm != 0).then_some(RegisterValue::Value(imm)),
					Some((csr_load_value, BinaryOp::Andn)),
					csrs,
					next_renamed_register_tag,
				);

				match (inst1, inst23) {
					(None, None) => None,
					(None, Some((inst2, None))) => Some((inst2, None)),
					(None, Some((inst2, Some(inst3)))) => Some((inst2, Some((inst3, None)))),
					(Some(inst1), None) => Some((inst1, None)),
					(Some(inst1), Some((inst2, None))) => Some((inst1, Some((inst2, None)))),
					(Some(inst1), Some((inst2, Some(inst3)))) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
			},

			Instruction::Ebreak => Some((Self::Ebreak, None)),

			Instruction::Fence => Some((Self::Fence, None)),

			Instruction::Jal { rd, imm } => {
				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) };

				let inst2 = assign_x_reg(rd, RegisterValue::Value(next_inst_pc), x_regs, next_renamed_register_tag);

				let inst3 = Self::Jump { pc: RegisterValue::Tag(tag), predicted_next_pc };

				match inst2 {
					None => Some((inst1, Some((inst3, None)))),
					Some(inst2) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
			},

			Instruction::Jalr { rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag, None), rs1, rs2: RegisterValue::Value(imm) };

				let inst2 = assign_x_reg(rd, RegisterValue::Value(next_inst_pc), x_regs, next_renamed_register_tag);

				let inst3 = Self::Jump { pc: RegisterValue::Tag(tag), predicted_next_pc };

				match inst2 {
					None => Some((inst1, Some((inst3, None)))),
					Some(inst2) => Some((inst1, Some((inst2, Some((inst3, None)))))),
				}
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

				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::BinaryOp { op: addr_op, rd: (XReg::X0, tag, None), rs1: base, rs2: offset };

				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst2 = Self::Load { op, rd, addr: RegisterValue::Tag(tag) };

				Some((inst1, Some((inst2, None))))
			},

			Instruction::Lui { rd, imm } => {
				let inst = assign_x_reg(rd, RegisterValue::Value(imm), x_regs, next_renamed_register_tag)?;
				Some((inst, None))
			},

			// c.mv
			Instruction::Op { op: OpOp::Add, rd, rs1: XReg::X0, rs2 } => {
				let rs2 = x_regs.load(rs2);
				let inst = assign_x_reg(rd, rs2, x_regs, next_renamed_register_tag)?;
				Some((inst, None))
			},

			Instruction::Op { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				match op {
					OpOp::Add => Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1, rs2 }, None)),

					OpOp::And => Some((Self::BinaryOp { op: BinaryOp::And, rd, rs1, rs2 }, None)),

					OpOp::Andn => Some((Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2 }, None)),

					OpOp::Bclr => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2 };
						let inst2 = Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Bext => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Srl, rd: (XReg::X0, tag, None), rs1, rs2 };
						let inst2 = Self::BinaryOp { op: BinaryOp::And, rd, rs1: RegisterValue::Tag(tag), rs2: RegisterValue::Value(1) };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Binv => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2 };
						let inst2 = Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Bset => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2 };
						let inst2 = Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::CzeroEqz => Some((Self::Czero { rd, rcond: rs2, rs_eqz: RegisterValue::Value(0), rs_nez: rs1 }, None)),

					OpOp::CzeroNez => Some((Self::Czero { rd, rcond: rs2, rs_eqz: rs1, rs_nez: RegisterValue::Value(0) }, None)),

					OpOp::Max => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag, None), rs1, rs2 };
						let inst2 = Self::Czero { rd, rcond: RegisterValue::Tag(tag), rs_eqz: rs1, rs_nez: rs2 };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Maxu => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sltu, rd: (XReg::X0, tag, None), rs1, rs2 };
						let inst2 = Self::Czero { rd, rcond: RegisterValue::Tag(tag), rs_eqz: rs1, rs_nez: rs2 };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Min => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Slt, rd: (XReg::X0, tag, None), rs1, rs2 };
						let inst2 = Self::Czero { rd, rcond: RegisterValue::Tag(tag), rs_eqz: rs2, rs_nez: rs1 };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Minu => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sltu, rd: (XReg::X0, tag, None), rs1, rs2 };
						let inst2 = Self::Czero { rd, rcond: RegisterValue::Tag(tag), rs_eqz: rs2, rs_nez: rs1 };
						Some((inst1, Some((inst2, None))))
					},

					OpOp::Mul => Some((Self::BinaryOp { op: BinaryOp::Mul, rd, rs1, rs2 }, None)),

					OpOp::Mulh => Some((Self::BinaryOp { op: BinaryOp::Mulh, rd, rs1, rs2 }, None)),

					OpOp::Mulhsu => Some((Self::BinaryOp { op: BinaryOp::Mulhsu, rd, rs1, rs2 }, None)),

					OpOp::Mulhu => Some((Self::BinaryOp { op: BinaryOp::Mulhu, rd, rs1, rs2 }, None)),

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

			Instruction::Op32 { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				match op {
					Op32Op::AddUw => Some((Self::BinaryOp { op: BinaryOp::AddUw, rd, rs1, rs2 }, None)),

					Op32Op::Addw => Some((Self::BinaryOp { op: BinaryOp::Addw, rd, rs1, rs2 }, None)),

					Op32Op::Mulw => Some((Self::BinaryOp { op: BinaryOp::Mulw, rd, rs1, rs2 }, None)),

					Op32Op::Rolw => Some((Self::BinaryOp { op: BinaryOp::Rolw, rd, rs1, rs2 }, None)),

					Op32Op::Rorw => Some((Self::BinaryOp { op: BinaryOp::Rorw, rd, rs1, rs2 }, None)),

					Op32Op::Sh1addUw => Some((Self::BinaryOp { op: BinaryOp::Sh1addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sh2addUw => Some((Self::BinaryOp { op: BinaryOp::Sh2addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sh3addUw => Some((Self::BinaryOp { op: BinaryOp::Sh3addUw, rd, rs1, rs2 }, None)),

					Op32Op::Sllw => Some((Self::BinaryOp { op: BinaryOp::Sllw, rd, rs1, rs2 }, None)),

					Op32Op::Sraw => Some((Self::BinaryOp { op: BinaryOp::Sraw, rd, rs1, rs2 }, None)),

					Op32Op::Srlw => Some((Self::BinaryOp { op: BinaryOp::Srlw, rd, rs1, rs2 }, None)),

					Op32Op::Subw => Some((Self::BinaryOp { op: BinaryOp::Subw, rd, rs1, rs2 }, None)),

					Op32Op::ZextH => Some((Self::BinaryOp { op: BinaryOp::And, rd, rs1, rs2: RegisterValue::Value(0xffff) }, None)),
				}
			},

			// mv
			Instruction::OpImm { op: OpImmOp::Addi, rd, rs1, imm: 0 } => {
				let rs1 = x_regs.load(rs1);
				let inst = assign_x_reg(rd, rs1, x_regs, next_renamed_register_tag)?;
				Some((inst, None))
			},

			Instruction::OpImm { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				match op {
					OpImmOp::Addi => Some((Self::BinaryOp { op: BinaryOp::Add, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Andi => Some((Self::BinaryOp { op: BinaryOp::And, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImmOp::Bclri => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst2 = Self::BinaryOp { op: BinaryOp::Andn, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpImmOp::Bexti => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Srl, rd: (XReg::X0, tag, None), rs1, rs2: RegisterValue::Value(imm) };
						let inst2 = Self::BinaryOp { op: BinaryOp::And, rd, rs1: RegisterValue::Tag(tag), rs2: RegisterValue::Value(1) };
						Some((inst1, Some((inst2, None))))
					},

					OpImmOp::Binvi => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst2 = Self::BinaryOp { op: BinaryOp::Xor, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpImmOp::Bseti => {
						let tag = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Sll, rd: (XReg::X0, tag, None), rs1: RegisterValue::Value(1), rs2: RegisterValue::Value(imm) };
						let inst2 = Self::BinaryOp { op: BinaryOp::Or, rd, rs1, rs2: RegisterValue::Tag(tag) };
						Some((inst1, Some((inst2, None))))
					},

					OpImmOp::Clz => {
						let tag1 = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Grev, rd: (XReg::X0, tag1, None), rs1, rs2: RegisterValue::Value(0b111111) };

						let tag2 = next_renamed_register_tag.allocate();
						let inst2 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag2, None), rs1: RegisterValue::Tag(tag1), rs2: RegisterValue::Value(-1) };

						let tag3 = next_renamed_register_tag.allocate();
						let inst3 = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag3, None), rs1: RegisterValue::Tag(tag2), rs2: RegisterValue::Tag(tag1) };

						let inst4 = Self::UnaryOp { op: UnaryOp::Cpop, rd, rs: RegisterValue::Tag(tag3) };

						Some((inst1, Some((inst2, Some((inst3, Some(inst4)))))))
					},

					OpImmOp::Ctz => {
						let tag1 = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag1, None), rs1, rs2: RegisterValue::Value(-1) };

						let tag2 = next_renamed_register_tag.allocate();
						let inst2 = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag2, None), rs1: RegisterValue::Tag(tag1), rs2: rs1 };

						let inst3 = Self::UnaryOp { op: UnaryOp::Cpop, rd, rs: RegisterValue::Tag(tag2) };

						Some((inst1, Some((inst2, Some((inst3, None))))))
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

			Instruction::OpImm32 { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				match op {
					OpImm32Op::Addiw => Some((Self::BinaryOp { op: BinaryOp::Addw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Clzw => {
						let tag1 = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Grev, rd: (XReg::X0, tag1, None), rs1, rs2: RegisterValue::Value(0b011111) };

						let tag2 = next_renamed_register_tag.allocate();
						let inst2 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag2, None), rs1: RegisterValue::Tag(tag1), rs2: RegisterValue::Value(-1) };

						let tag3 = next_renamed_register_tag.allocate();
						let inst3 = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag3, None), rs1: RegisterValue::Tag(tag2), rs2: RegisterValue::Tag(tag1) };

						let inst4 = Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: RegisterValue::Tag(tag3) };

						Some((inst1, Some((inst2, Some((inst3, Some(inst4)))))))
					},

					OpImm32Op::Cpopw => Some((Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: rs1 }, None)),

					OpImm32Op::Ctzw => {
						let tag1 = next_renamed_register_tag.allocate();
						let inst1 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag1, None), rs1, rs2: RegisterValue::Value(-1) };

						let tag2 = next_renamed_register_tag.allocate();
						let inst2 = Self::BinaryOp { op: BinaryOp::Andn, rd: (XReg::X0, tag2, None), rs1: RegisterValue::Tag(tag1), rs2: rs1 };

						let inst3 = Self::UnaryOp { op: UnaryOp::Cpopw, rd, rs: RegisterValue::Tag(tag2) };

						Some((inst1, Some((inst2, Some((inst3, None))))))
					},

					OpImm32Op::Roriw => Some((Self::BinaryOp { op: BinaryOp::Rorw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::SlliUw => Some((Self::BinaryOp { op: BinaryOp::SllUw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Slliw => Some((Self::BinaryOp { op: BinaryOp::Sllw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Sraiw => Some((Self::BinaryOp { op: BinaryOp::Sraw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),

					OpImm32Op::Srliw => Some((Self::BinaryOp { op: BinaryOp::Srlw, rd, rs1, rs2: RegisterValue::Value(imm) }, None)),
				}
			},

			Instruction::Store { op, rs1, rs2, imm } => {
				let base = x_regs.load(rs1);
				let value = x_regs.load(rs2);

				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::BinaryOp { op: BinaryOp::Add, rd: (XReg::X0, tag, None), rs1: base, rs2: RegisterValue::Value(imm) };

				let inst2 = Self::Store { op, addr: RegisterValue::Tag(tag), value };

				Some((inst1, Some((inst2, None))))
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
			Self::Czero { rd: _, rcond, rs_eqz, rs_nez } => {
				rcond.update(tag, new_value);
				rs_eqz.update(tag, new_value);
				rs_nez.update(tag, new_value);
			},
			Self::Ebreak => (),
			Self::Fence => (),
			Self::Jump { pc, predicted_next_pc: _ } => pc.update(tag, new_value),
			Self::Li { rd: _, value } => value.update(tag, new_value),
			Self::LiCsr { csr: _, value } => value.update(tag, new_value),
			Self::Load { op: _, rd: _, addr } => addr.update(tag, new_value),
			Self::Store { op: _, addr, value } => {
				addr.update(tag, new_value);
				value.update(tag, new_value);
			},
			Self::UnaryOp { op: _, rd: _, rs } => rs.update(tag, new_value),
		}
	}
}
