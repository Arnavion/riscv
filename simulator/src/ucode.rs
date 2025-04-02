#![allow(clippy::unreadable_literal)]

use crate::{
	RegisterValue, Tag,
	csrs::{Csr, Csrs},
	instruction::{
		BranchOp,
		Instruction,
		OpOp, Op32Op,
		OpImmOp, OpImm32Op,
		MemoryBase, MemoryOffset,
	},
	memory::{LoadOp, StoreOp},
	x_regs::{XReg, XRegs},
};

#[derive(Clone, Copy, Debug)]
pub(crate) enum Ucode {
	Abs { rd: (XReg, Tag), rs: RegisterValue },
	Branch { op: BranchOp, rs1: RegisterValue, rs2: RegisterValue, pc: RegisterValue, next_inst_pc: i64, predicted_next_pc: i64 },
	Ebreak,
	Fence,
	Jal { rd: Option<(XReg, Tag)>, pc: RegisterValue, next_inst_pc: i64, predicted_next_pc: i64 },
	Li { rd: (XReg, Tag), value: RegisterValue },
	LiCsr { csr: (Csr, Tag), value: RegisterValue },
	Load { op: LoadOp, rd: (XReg, Tag), addr: RegisterValue },
	Op { op: Op, rd: (XReg, Tag), rs1: RegisterValue, rs2: RegisterValue },
	Store { op: StoreOp, addr: RegisterValue, value: RegisterValue },
}

#[derive(Clone, Copy, Debug)]
pub(crate) enum Op {
	Add,
	AddUw,
	Addw,
	And,
	Andn,
	Bclr,
	Bext,
	Binv,
	Bset,
	Clz,
	Clzw,
	Cpop,
	Cpopw,
	Ctz,
	Ctzw,
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
	Mulw,
	Or,
	OrcB,
	Orn,
	Rev8,
	Rol,
	Rolw,
	Ror,
	Rorw,
	SextB,
	SextH,
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
	ZextH,
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
	) -> Option<(Self, Option<(Self, Option<Self>)>)> {
		fn try_rename_xreg(
			rd: XReg,
			x_regs: &mut XRegs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<(XReg, Tag)> {
			let tag = next_renamed_register_tag.allocate_if(|tag| x_regs.rename(rd, tag))?;
			Some((rd, tag))
		}

		fn try_rename_csr(
			csr: Csr,
			csrs: &mut Csrs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<(Csr, Tag)> {
			let tag = next_renamed_register_tag.allocate_if(|tag| csrs.rename(csr, tag))?;
			Some((csr, tag))
		}

		fn assign_x_reg_to_csr(
			rs: RegisterValue,
			csr: Csr,
			csrs: &mut Csrs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<Ucode> {
			match rs {
				RegisterValue::Value(imm) => {
					let csr = try_rename_csr(csr, csrs, next_renamed_register_tag)?;
					Some(Ucode::LiCsr { csr, value: RegisterValue::Value(imm) })
				},

				RegisterValue::Tag(tag) =>
					if csrs.rename(csr, tag) {
						Some(Ucode::LiCsr { csr: (csr, tag), value: RegisterValue::Tag(tag) })
					}
					else {
						None
					},
			}
		}

		fn assign_csr_to_x_reg(
			csr_load_value: RegisterValue,
			rd: XReg,
			x_regs: &mut XRegs,
			next_renamed_register_tag: &mut Tag,
		) -> Option<Ucode> {
			match csr_load_value {
				RegisterValue::Value(imm) => {
					let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
					Some(Ucode::Li { rd, value: RegisterValue::Value(imm) })
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

		match inst {
			Instruction::Abs { rd, rs } => {
				let rs = x_regs.load(rs);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				Some((Self::Abs { rd, rs }, None))
			},

			Instruction::Auipc { rd, imm } => {
				let (rd, rd_tag) = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				Some((Self::Op { op: Op::Add, rd: (rd, rd_tag), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) }, None))
			},

			Instruction::Branch { op, rs1, rs2, imm } => {
				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::Op { op: Op::Add, rd: (XReg::X0, tag), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) };

				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let inst2 = Self::Branch { op, rs1, rs2, pc: RegisterValue::Tag(tag), next_inst_pc, predicted_next_pc };

				Some((inst1, Some((inst2, None))))
			},

			Instruction::Csrrw { rd, rs1, csr } => {
				let rs1 = x_regs.load(rs1);
				let rd_inst =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag)
					};

				let csr_inst = assign_x_reg_to_csr(rs1, csr, csrs, next_renamed_register_tag);

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some(inst)) |
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some(inst2)) => Some((inst1, Some((inst2, None)))),
				}
			},

			Instruction::Csrrwi { rd, imm, csr } => {
				let rd_inst =
					if rd == XReg::X0 {
						None
					}
					else {
						let csr_load_value = csrs.load(csr);
						assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag)
					};

				let csr_inst = assign_x_reg_to_csr(RegisterValue::Value(imm), csr, csrs, next_renamed_register_tag);

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some(inst)) |
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some(inst2)) => Some((inst1, Some((inst2, None)))),
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

				let rd_inst = assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag);

				let csr_inst =
					if let Some(rs1) = rs1 {
						try_rename_csr(csr, csrs, next_renamed_register_tag)
							.map(|csr| (
								Self::Op { op: Op::Or, rd: (XReg::X0, csr.1), rs1: csr_load_value, rs2: rs1 },
								Self::LiCsr { csr, value: RegisterValue::Tag(csr.1) },
							))
					}
					else {
						None
					};

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some((inst1, inst2))) => Some((inst1, Some((inst2, None)))),
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some((inst2, inst3))) => Some((inst1, Some((inst2, Some(inst3))))),
				}
			},

			Instruction::Csrrsi { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let rd_inst = assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag);

				let csr_inst =
					if imm == 0 {
						None
					}
					else {
						try_rename_csr(csr, csrs, next_renamed_register_tag)
							.map(|csr| (
								Self::Op { op: Op::Or, rd: (XReg::X0, csr.1), rs1: csr_load_value, rs2: RegisterValue::Value(imm) },
								Self::LiCsr { csr, value: RegisterValue::Tag(csr.1) },
							))
					};

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some((inst1, inst2))) => Some((inst1, Some((inst2, None)))),
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some((inst2, inst3))) => Some((inst1, Some((inst2, Some(inst3))))),
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

				let rd_inst = assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag);

				let csr_inst =
					if let Some(rs1) = rs1 {
						try_rename_csr(csr, csrs, next_renamed_register_tag)
							.map(|csr| (
								Self::Op { op: Op::Andn, rd: (XReg::X0, csr.1), rs1: csr_load_value, rs2: rs1 },
								Self::LiCsr { csr, value: RegisterValue::Tag(csr.1) },
							))
					}
					else {
						None
					};

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some((inst1, inst2))) => Some((inst1, Some((inst2, None)))),
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some((inst2, inst3))) => Some((inst1, Some((inst2, Some(inst3))))),
				}
			},

			Instruction::Csrrci { rd, imm, csr } => {
				let csr_load_value = csrs.load(csr);

				let rd_inst = assign_csr_to_x_reg(csr_load_value, rd, x_regs, next_renamed_register_tag);

				let csr_inst =
					if imm == 0 {
						None
					}
					else {
						try_rename_csr(csr, csrs, next_renamed_register_tag)
							.map(|csr| (
								Self::Op { op: Op::Andn, rd: (XReg::X0, csr.1), rs1: csr_load_value, rs2: RegisterValue::Value(imm) },
								Self::LiCsr { csr, value: RegisterValue::Tag(csr.1) },
							))
					};

				match (rd_inst, csr_inst) {
					(None, None) => None,
					(None, Some((inst1, inst2))) => Some((inst1, Some((inst2, None)))),
					(Some(inst), None) => Some((inst, None)),
					(Some(inst1), Some((inst2, inst3))) => Some((inst1, Some((inst2, Some(inst3))))),
				}
			},

			Instruction::Ebreak => Some((Self::Ebreak, None)),

			Instruction::Fence => Some((Self::Fence, None)),

			Instruction::Jal { rd, imm } => {
				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::Op { op: Op::Add, rd: (XReg::X0, tag), rs1: RegisterValue::Value(pc), rs2: RegisterValue::Value(imm) };

				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag);
				let inst2 = Self::Jal { rd, pc: RegisterValue::Tag(tag), next_inst_pc, predicted_next_pc };

				Some((inst1, Some((inst2, None))))
			},

			Instruction::Jalr { rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::Op { op: Op::Add, rd: (XReg::X0, tag), rs1, rs2: RegisterValue::Value(imm) };

				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag);
				let inst2 = Self::Jal { rd, pc: RegisterValue::Tag(tag), next_inst_pc, predicted_next_pc };

				Some((inst1, Some((inst2, None))))
			},

			Instruction::Load { op, rd, base, offset } => {
				let offset = match offset {
					MemoryOffset::Imm(offset) => RegisterValue::Value(offset),
					MemoryOffset::XReg(offset) => x_regs.load(offset),
				};

				let (addr_op, base) = match base {
					MemoryBase::XReg(base) => (Op::Add, x_regs.load(base)),
					MemoryBase::XRegSh1(base) => (Op::Sh1add, x_regs.load(base)),
					MemoryBase::XRegSh2(base) => (Op::Sh2add, x_regs.load(base)),
					MemoryBase::XRegSh3(base) => (Op::Sh3add, x_regs.load(base)),
					MemoryBase::Pc => (Op::Add, RegisterValue::Value(pc)),
				};

				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::Op { op: addr_op, rd: (XReg::X0, tag), rs1: base, rs2: offset };

				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst2 = Self::Load { op, rd, addr: RegisterValue::Tag(tag) };

				Some((inst1, Some((inst2, None))))
			},

			Instruction::Lui { rd, imm } => {
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				Some((Self::Li { rd, value: RegisterValue::Value(imm) }, None))
			},

			Instruction::Op { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst = Self::Op { op: op.into(), rd: (rd.0, rd.1), rs1, rs2 };
				Some((inst, None))
			},

			Instruction::Op32 { op, rd, rs1, rs2 } => {
				let rs1 = x_regs.load(rs1);
				let rs2 = x_regs.load(rs2);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst = Self::Op { op: op.into(), rd, rs1, rs2 };
				Some((inst, None))
			},

			Instruction::OpImm { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst = Self::Op { op: op.into(), rd: (rd.0, rd.1), rs1, rs2: RegisterValue::Value(imm) };
				Some((inst, None))
			},

			Instruction::OpImm32 { op, rd, rs1, imm } => {
				let rs1 = x_regs.load(rs1);
				let rd = try_rename_xreg(rd, x_regs, next_renamed_register_tag)?;
				let inst = Self::Op { op: op.into(), rd, rs1, rs2: RegisterValue::Value(imm) };
				Some((inst, None))
			},

			Instruction::Store { op, rs1, rs2, imm } => {
				let base = x_regs.load(rs1);
				let value = x_regs.load(rs2);

				let tag = next_renamed_register_tag.allocate();
				let inst1 = Self::Op { op: Op::Add, rd: (XReg::X0, tag), rs1: base, rs2: RegisterValue::Value(imm) };

				let inst2 = Self::Store { op, addr: RegisterValue::Tag(tag), value };

				Some((inst1, Some((inst2, None))))
			},
		}
	}

	pub(crate) fn update(&mut self, tag: Tag, new_value: i64) {
		#[allow(clippy::match_same_arms)]
		match self {
			Self::Abs { rd: _, rs } => rs.update(tag, new_value),
			Self::Branch { op: _, rs1, rs2, pc, next_inst_pc: _, predicted_next_pc: _ } => {
				rs1.update(tag, new_value);
				rs2.update(tag, new_value);
				pc.update(tag, new_value);
			},
			Self::Ebreak => (),
			Self::Fence => (),
			Self::Jal { rd: _, pc, next_inst_pc: _, predicted_next_pc: _ } => pc.update(tag, new_value),
			Self::Li { rd: _, value } => value.update(tag, new_value),
			Self::LiCsr { csr: _, value } => value.update(tag, new_value),
			Self::Load { op: _, rd: _, addr } => addr.update(tag, new_value),
			Self::Op { op: _, rd: _, rs1, rs2 } => {
				rs1.update(tag, new_value);
				rs2.update(tag, new_value);
			},
			Self::Store { op: _, addr, value } => {
				addr.update(tag, new_value);
				value.update(tag, new_value);
			},
		}
	}
}

impl From<OpOp> for Op {
	fn from(op: OpOp) -> Self {
		match op {
			OpOp::Add => Self::Add,
			OpOp::And => Self::And,
			OpOp::Andn => Self::Andn,
			OpOp::Bclr => Self::Bclr,
			OpOp::Bext => Self::Bext,
			OpOp::Binv => Self::Binv,
			OpOp::Bset => Self::Bset,
			OpOp::CzeroEqz => Self::CzeroEqz,
			OpOp::CzeroNez => Self::CzeroNez,
			OpOp::Max => Self::Max,
			OpOp::Maxu => Self::Maxu,
			OpOp::Min => Self::Min,
			OpOp::Minu => Self::Minu,
			OpOp::Mul => Self::Mul,
			OpOp::Mulh => Self::Mulh,
			OpOp::Mulhsu => Self::Mulhsu,
			OpOp::Mulhu => Self::Mulhu,
			OpOp::Or => Self::Or,
			OpOp::Orn => Self::Orn,
			OpOp::Rol => Self::Rol,
			OpOp::Ror => Self::Ror,
			OpOp::Sh1add => Self::Sh1add,
			OpOp::Sh2add => Self::Sh2add,
			OpOp::Sh3add => Self::Sh3add,
			OpOp::Sll => Self::Sll,
			OpOp::Slt => Self::Slt,
			OpOp::Sltu => Self::Sltu,
			OpOp::Sra => Self::Sra,
			OpOp::Srl => Self::Srl,
			OpOp::Sub => Self::Sub,
			OpOp::Xnor => Self::Xnor,
			OpOp::Xor => Self::Xor,
		}
	}
}

impl From<OpImmOp> for Op {
	fn from(op: OpImmOp) -> Self {
		match op {
			OpImmOp::Addi => Self::Add,
			OpImmOp::Andi => Self::And,
			OpImmOp::Bclri => Self::Bclr,
			OpImmOp::Bexti => Self::Bext,
			OpImmOp::Binvi => Self::Binv,
			OpImmOp::Bseti => Self::Bset,
			OpImmOp::Clz => Self::Clz,
			OpImmOp::Cpop => Self::Cpop,
			OpImmOp::Ctz => Self::Ctz,
			OpImmOp::OrcB => Self::OrcB,
			OpImmOp::Ori => Self::Or,
			OpImmOp::Rev8 => Self::Rev8,
			OpImmOp::Rori => Self::Ror,
			OpImmOp::SextB => Self::SextB,
			OpImmOp::SextH => Self::SextH,
			OpImmOp::Slli => Self::Sll,
			OpImmOp::Slti => Self::Slt,
			OpImmOp::Sltiu => Self::Sltu,
			OpImmOp::Srai => Self::Sra,
			OpImmOp::Srli => Self::Srl,
			OpImmOp::Xori => Self::Xor,
		}
	}
}

impl From<Op32Op> for Op {
	fn from(op: Op32Op) -> Self {
		match op {
			Op32Op::AddUw => Self::AddUw,
			Op32Op::Addw => Self::Addw,
			Op32Op::Mulw => Self::Mulw,
			Op32Op::Rolw => Self::Rolw,
			Op32Op::Rorw => Self::Rorw,
			Op32Op::Sh1addUw => Self::Sh1addUw,
			Op32Op::Sh2addUw => Self::Sh2addUw,
			Op32Op::Sh3addUw => Self::Sh3addUw,
			Op32Op::Sllw => Self::Sllw,
			Op32Op::Sraw => Self::Sraw,
			Op32Op::Srlw => Self::Srlw,
			Op32Op::Subw => Self::Subw,
			Op32Op::ZextH => Self::ZextH,
		}
	}
}

impl From<OpImm32Op> for Op {
	fn from(op: OpImm32Op) -> Self {
		match op {
			OpImm32Op::Addiw => Self::Addw,
			OpImm32Op::Clzw => Self::Clzw,
			OpImm32Op::Cpopw => Self::Cpopw,
			OpImm32Op::Ctzw => Self::Ctzw,
			OpImm32Op::Roriw => Self::Rorw,
			OpImm32Op::SlliUw => Self::SllUw,
			OpImm32Op::Slliw => Self::Sllw,
			OpImm32Op::Sraiw => Self::Sraw,
			OpImm32Op::Srliw => Self::Srlw,
		}
	}
}
