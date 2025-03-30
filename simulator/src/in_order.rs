use crate::{
	csrs::Csrs,
	instruction::{
		Instruction,
		OpOp, OpImmOp, Op32Op, OpImm32Op,
		MemoryBase, MemoryOffset,
	},
	memory::Memory,
	x_regs::{XReg, XRegs},
	LogLevel,
	Statistics,
	load_inst,
};

pub(crate) fn run(
	memory: &mut Memory,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	statistics: &mut Statistics,
	mut pc: i64,
	log_level: LogLevel,
) {
	loop {
		{
			let tick = csrs.cycle();
			if log_level == LogLevel::Debug {
				if tick % 100 == 0 {
					eprintln!();
					eprintln!("===== {tick} =====");
					eprintln!("0x{pc:016x}");
				}
			}
			else if log_level >= LogLevel::Trace {
				eprintln!();
				eprintln!("===== {tick} =====");
				eprintln!("{x_regs}");
				eprintln!("{csrs}");
			}
		}

		let (inst, inst_len, instret) = match load_inst(memory, pc, statistics) {
			Ok(inst) => inst,
			Err(inst) => panic!("SIGILL: 0x{inst:08x}"),
		};

		if log_level >= LogLevel::Trace {
			eprintln!("+ 0x{pc:016x} : {inst:?}");
		}

		if let Instruction::Ebreak = inst {
			break;
		}

		let mut next_pc = pc.wrapping_add(inst_len);

		execute(inst, pc, &mut next_pc, x_regs, csrs, memory);

		pc = next_pc;

		let cycles = match inst {
			Instruction::Op { op: OpOp::Mul | OpOp::Mulh | OpOp::Mulhsu | OpOp::Mulhu, .. }
				=> 34,

			Instruction::Op32 { op: Op32Op::Mulw, .. }
				=> 17,

			Instruction::OpImm { op: OpImmOp::Clz | OpImmOp::Ctz | OpImmOp::Cpop, .. } |
			Instruction::OpImm32 { op: OpImm32Op::Clzw | OpImm32Op::Ctzw | OpImm32Op::Cpopw, .. }
				=> 3,

			_
				=> 1,
		};

		csrs.tick(cycles, instret);

		if log_level >= LogLevel::Trace {
			eprintln!("->");
			eprintln!("{x_regs}");
			eprintln!("{csrs}");
		}
	}
}

fn execute(
	inst: Instruction,
	pc: i64,
	next_pc: &mut i64,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	memory: &mut Memory,
) {
	match inst {
		Instruction::Abs { rd, rs } => {
			let arg = x_regs.load(rs);
			x_regs.store(rd, arg.unsigned_abs().cast_signed());
		},

		Instruction::Auipc { rd, imm } => {
			x_regs.store(rd, pc.wrapping_add(imm));
		},

		Instruction::Branch { op, rs1, rs2, imm } => {
			let arg1 = x_regs.load(rs1);
			let arg2 = x_regs.load(rs2);
			if op.exec(arg1, arg2) {
				*next_pc = pc.wrapping_add(imm);
			}
		},

		Instruction::Csrrw { rd, csr, rs1 } =>
			if rd == XReg::X0 {
				let new = x_regs.load(rs1);
				csrs.store(csr, new);
			}
			else {
				let previous = csrs.load(csr);
				let new = x_regs.load(rs1);
				x_regs.store(rd, previous);
				csrs.store(csr, new);
			},

		Instruction::Csrrwi { rd, csr, imm } =>
			if rd == XReg::X0 {
				csrs.store(csr, imm);
			}
			else {
				let previous = csrs.load(csr);
				x_regs.store(rd, previous);
				csrs.store(csr, imm);
			},

		Instruction::Csrrs { rd, csr, rs1 } =>
			if rs1 == XReg::X0 {
				let previous = csrs.load(csr);
				x_regs.store(rd, previous);
			}
			else {
				let previous = csrs.load(csr);
				let new = previous | x_regs.load(rs1);
				x_regs.store(rd, previous);
				csrs.store(csr, new);
			},

		Instruction::Csrrsi { rd, csr, imm } =>
			if imm == 0 {
				let previous = csrs.load(csr);
				x_regs.store(rd, previous);
			}
			else {
				let previous = csrs.load(csr);
				let new = previous | imm;
				x_regs.store(rd, previous);
				csrs.store(csr, new);
			},

		Instruction::Csrrc { rd, csr, rs1 } =>
			if rs1 == XReg::X0 {
				let previous = csrs.load(csr);
				x_regs.store(rd, previous);
			}
			else {
				let previous = csrs.load(csr);
				let new = previous & !x_regs.load(rs1);
				x_regs.store(rd, previous);
				csrs.store(csr, new);
			},

		Instruction::Csrrci { rd, csr, imm } =>
			if imm == 0 {
				let previous = csrs.load(csr);
				x_regs.store(rd, previous);
			}
			else {
				let previous = csrs.load(csr);
				let new = previous & !imm;
				x_regs.store(rd, previous);
				csrs.store(csr, new);
			},

		Instruction::Ebreak => panic!("EBREAK"),

		Instruction::Fence => (),

		Instruction::Jal { rd, imm } => {
			x_regs.store(rd, *next_pc);
			*next_pc = pc.wrapping_add(imm);
		},

		Instruction::Jalr { rd, rs1, imm } => {
			let arg1 = x_regs.load(rs1);
			x_regs.store(rd, *next_pc);
			*next_pc = arg1.wrapping_add(imm) & 0xffff_ffff_ffff_fffe_u64.cast_signed();
		},

		Instruction::Load { op, rd, base, offset } => {
			let base = match base {
				MemoryBase::XReg(rs1) => x_regs.load(rs1),
				MemoryBase::XRegSh1(rs1) => x_regs.load(rs1) << 1,
				MemoryBase::XRegSh2(rs1) => x_regs.load(rs1) << 2,
				MemoryBase::XRegSh3(rs1) => x_regs.load(rs1) << 3,
				MemoryBase::Pc => pc,
			};
			let offset = match offset {
				MemoryOffset::Imm(imm) => imm,
				MemoryOffset::XReg(rs2) => x_regs.load(rs2),
			};
			let address = base.wrapping_add(offset);
			let value = op.exec(memory, address);
			x_regs.store(rd, value);
		},

		Instruction::Lui { rd, imm } => {
			x_regs.store(rd, imm);
		},

		Instruction::Op { op, rd, rs1, rs2 } => {
			let arg1 = x_regs.load(rs1);
			let arg2 = x_regs.load(rs2);
			let value = match op {
				OpOp::Add => arg1.wrapping_add(arg2),
				OpOp::And => arg1 & arg2,
				OpOp::Andn => arg1 & !arg2,
				OpOp::Bclr => arg1 & !(1 << (arg2 & 0x3f)),
				OpOp::Bext => (arg1 >> (arg2 & 0x3f)) & 0x1,
				OpOp::Binv => arg1 ^ (1 << (arg2 & 0x3f)),
				OpOp::Bset => arg1 | (1 << (arg2 & 0x3f)),
				OpOp::CzeroEqz => if arg2 == 0 { 0 } else { arg1 },
				OpOp::CzeroNez => if arg2 == 0 { arg1 } else { 0 },
				OpOp::Max => arg1.max(arg2),
				OpOp::Maxu => arg1.cast_unsigned().max(arg2.cast_unsigned()).cast_signed(),
				OpOp::Min => arg1.min(arg2),
				OpOp::Minu => arg1.cast_unsigned().min(arg2.cast_unsigned()).cast_signed(),
				OpOp::Mul => arg1.wrapping_mul(arg2),
				OpOp::Mulh => ((i128::from(arg1) * i128::from(arg2)) >> 64).try_into().unwrap(),
				OpOp::Mulhsu => ((i128::from(arg1) * i128::from(arg2.cast_unsigned())) >> 64).try_into().unwrap(),
				OpOp::Mulhu => ((u128::from(arg1.cast_unsigned()) * u128::from(arg2.cast_unsigned())).cast_signed() >> 64).try_into().unwrap(),
				OpOp::Or => arg1 | arg2,
				OpOp::Orn => arg1 | !arg2,
				OpOp::Rol => arg1.rotate_left((arg2 & 0x3f).try_into().unwrap()),
				OpOp::Ror => arg1.rotate_right((arg2 & 0x3f).try_into().unwrap()),
				OpOp::Sh1add => (arg1 << 1).wrapping_add(arg2),
				OpOp::Sh2add => (arg1 << 2).wrapping_add(arg2),
				OpOp::Sh3add => (arg1 << 3).wrapping_add(arg2),
				OpOp::Sll => arg1 << (arg2 & 0x3f),
				OpOp::Slt => (arg1 < arg2).into(),
				OpOp::Sltu => (arg1.cast_unsigned() < arg2.cast_unsigned()).into(),
				OpOp::Sra => arg1 >> (arg2 & 0x3f),
				OpOp::Srl => (arg1.cast_unsigned() >> (arg2 & 0x3f)).cast_signed(),
				OpOp::Sub => arg1.wrapping_sub(arg2),
				OpOp::Xnor => arg1 ^ !arg2,
				OpOp::Xor => arg1 ^ arg2,
			};
			x_regs.store(rd, value);
		},

		Instruction::Op32 { op, rd, rs1, rs2 } => {
			let arg1 = x_regs.load(rs1);
			let arg2 = x_regs.load(rs2);

			#[allow(clippy::cast_possible_truncation)]
			let arg1w = arg1 as i32;
			let arg1uw = arg1w.cast_unsigned();

			#[allow(clippy::cast_possible_truncation)]
			let arg2w = arg2 as i32;

			let value = match op {
				Op32Op::AddUw => i64::from(arg1uw).wrapping_add(arg2),
				Op32Op::Addw => arg1w.wrapping_add(arg2w).into(),
				Op32Op::Mulw => arg1w.wrapping_mul(arg2w).into(),
				Op32Op::Rolw => arg1w.rotate_left((arg2w & 0x1f).try_into().unwrap()).into(),
				Op32Op::Rorw => arg1w.rotate_right((arg2w & 0x1f).try_into().unwrap()).into(),
				Op32Op::Sh1addUw => (i64::from(arg1uw) << 1).wrapping_add(arg2),
				Op32Op::Sh2addUw => (i64::from(arg1uw) << 2).wrapping_add(arg2),
				Op32Op::Sh3addUw => (i64::from(arg1uw) << 3).wrapping_add(arg2),
				Op32Op::Sllw => (arg1w << (arg2w & 0x1f)).into(),
				Op32Op::Sraw => (arg1w >> (arg2w & 0x1f)).into(),
				Op32Op::Srlw => (arg1uw >> (arg2w & 0x1f)).into(),
				Op32Op::Subw => arg1w.wrapping_sub(arg2w).into(),
				#[allow(clippy::cast_possible_truncation)]
				Op32Op::ZextH => i64::from(arg1.cast_unsigned() as u16),
			};
			x_regs.store(rd, value);
		},

		Instruction::OpImm { op, rd, rs1, imm } => {
			let arg1 = x_regs.load(rs1);
			let value = match op {
				OpImmOp::Addi => arg1.wrapping_add(imm),
				OpImmOp::Andi => arg1 & imm,
				OpImmOp::Bclri => arg1 & !(1 << (imm & 0x3f)),
				OpImmOp::Bexti => (arg1 >> (imm & 0x3f)) & 0x1,
				OpImmOp::Binvi => arg1 ^ (1 << (imm & 0x3f)),
				OpImmOp::Bseti => arg1 | (1 << (imm & 0x3f)),
				OpImmOp::Clz => arg1.leading_zeros().into(),
				OpImmOp::Cpop => arg1.count_ones().into(),
				OpImmOp::Ctz => arg1.trailing_zeros().into(),
				OpImmOp::OrcB => i64::from_ne_bytes(arg1.to_ne_bytes().map(|b| if b == 0 { 0x00 } else { 0xff })),
				OpImmOp::Ori => arg1 | imm,
				OpImmOp::Rev8 => i64::from_be_bytes(arg1.to_le_bytes()),
				OpImmOp::Rori => arg1.rotate_right((imm & 0x3f).try_into().unwrap()),
				#[allow(clippy::cast_possible_truncation)]
				OpImmOp::SextB => (arg1 as i8).into(),
				#[allow(clippy::cast_possible_truncation)]
				OpImmOp::SextH => (arg1 as i16).into(),
				OpImmOp::Slli => arg1 << (imm & 0x3f),
				OpImmOp::Slti => (arg1 < imm).into(),
				OpImmOp::Sltiu => (arg1.cast_unsigned() < imm.cast_unsigned()).into(),
				OpImmOp::Srai => arg1 >> (imm & 0x3f),
				OpImmOp::Srli => (arg1.cast_unsigned() >> (imm & 0x3f)).cast_signed(),
				OpImmOp::Xori => arg1 ^ imm,
			};
			x_regs.store(rd, value);
		},

		Instruction::OpImm32 { op, rd, rs1, imm } => {
			#[allow(clippy::cast_possible_truncation)]
			let arg1 = x_regs.load(rs1) as i32;
			#[allow(clippy::cast_possible_truncation)]
			let imm = imm as i32;
			let value = match op {
				OpImm32Op::Addiw => arg1.wrapping_add(imm).into(),
				OpImm32Op::Clzw => arg1.leading_zeros().into(),
				OpImm32Op::Cpopw => arg1.count_ones().into(),
				OpImm32Op::Ctzw => arg1.trailing_zeros().into(),
				OpImm32Op::Roriw => arg1.rotate_right((imm & 0x1f).try_into().unwrap()).into(),
				OpImm32Op::SlliUw => i64::from(arg1.cast_unsigned()) << (imm & 0x3f),
				OpImm32Op::Slliw => (arg1 << (imm & 0x1f)).into(),
				OpImm32Op::Sraiw => (arg1 >> (imm & 0x1f)).into(),
				OpImm32Op::Srliw => (arg1.cast_unsigned() >> (imm & 0x1f)).cast_signed().into(),
			};
			x_regs.store(rd, value);
		},

		Instruction::Store { op, rs1, rs2, imm } => {
			let address = x_regs.load(rs1).wrapping_add(imm);
			let value = x_regs.load(rs2);
			op.exec(memory, address, value);
		},
	}
}
