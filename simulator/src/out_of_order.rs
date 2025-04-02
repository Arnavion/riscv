use crate::{
	csrs::{Csr, Csrs},
	instruction::Instruction,
	memory::{Memory, LoadOp},
	ucode::{Ucode, Op},
	x_regs::{XReg, XRegs},
	RegisterValue, Tag,
	Statistics,
	macro_op_fuse,
};

pub(crate) fn run(
	memory: &mut Memory,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	statistics: &mut Statistics,
	mut pc: i64,
) {
	const ROB_MAX_LEN: usize = 32;

	let mut rob = std::collections::VecDeque::<_>::with_capacity(ROB_MAX_LEN);

	let mut next_renamed_register_tag: Tag = Default::default();

	loop {
		if rob.len() < ROB_MAX_LEN - 2 {
			let inst = LoadOp::DoubleWord.exec(memory, pc).cast_unsigned();
			#[allow(clippy::cast_possible_truncation)]
			if let Ok((inst_a, inst_a_len)) = Instruction::decode(inst as u32) {
				let inst = inst >> (inst_a_len * 8);
				#[allow(clippy::cast_possible_truncation)]
				let (inst, inst_len, instret) =
					if let Ok((inst_b, inst_b_len)) = Instruction::decode(inst as u32) {
						macro_op_fuse(inst_a, inst_a_len, inst_b, inst_b_len, &mut statistics.fusions)
					}
					else {
						(inst_a, inst_a_len, 1)
					};

				let next_inst_pc = pc.wrapping_add(inst_len);
				let predicted_next_pc = match inst {
					// BTFNT
					Instruction::Branch { op: _, rs1: _, rs2: _, imm } =>
						if imm < 0 {
							pc.wrapping_add(imm)
						}
						else {
							pc.wrapping_add(inst_len)
						},

					// Constant
					Instruction::Jal { rd: _, imm } => pc.wrapping_add(imm),

					// Maybe constant
					Instruction::Jalr { rd: _, rs1, imm } =>
						if let RegisterValue::Value(arg1) = x_regs.load(rs1) {
							arg1.wrapping_add(imm) & 0xffff_ffff_ffff_fffe_u64.cast_signed()
						}
						else {
							pc.wrapping_add(inst_len)
						},

					_ => pc.wrapping_add(inst_len),
				};

				let ucode_123 = Ucode::new(inst, pc, next_inst_pc, predicted_next_pc, x_regs, csrs, &mut next_renamed_register_tag);
				if let Some((ucode_1, ucode_23)) = ucode_123 {
					rob.push_back(RobEntry {
						state: RobEntryState::Pending,
						inst: ucode_1,
						instret: ucode_23.map_or(instret, |_| 0),
						rd: None,
						next_pc: None,
						csr: None,
					});

					if let Some((ucode_2, ucode_3)) = ucode_23 {
						rob.push_back(RobEntry {
							state: RobEntryState::Pending,
							inst: ucode_2,
							instret: ucode_3.map_or(instret, |_| 0),
							rd: None,
							next_pc: None,
							csr: None,
						});

						if let Some(ucode_3) = ucode_3 {
							rob.push_back(RobEntry {
								state: RobEntryState::Pending,
								inst: ucode_3,
								instret,
								rd: None,
								next_pc: None,
								csr: None,
							});
						}
					}
				}

				pc = predicted_next_pc;
			}
		}

		let mut integer_functional_units = vec![IntegerFunctionalUnit];

		let mut retired = 0;

		let mut next_rob = Vec::with_capacity(ROB_MAX_LEN);

		{
			let mut rob_entry = rob.pop_front().expect("ROB is empty! Something went wrong in the past.");

			if let Ucode::Ebreak = rob_entry.inst {
				break;
			}

			if matches!(rob_entry.state, RobEntryState::Done) {
				statistics.num_ticks_where_instructions_retired += 1;

				if let Some((next_pc, predicted_next_pc)) = rob_entry.next_pc {
					match rob_entry.inst {
						Ucode::Branch { .. } => statistics.branch_predictions += 1,
						Ucode::Jal { .. } => statistics.jal_predictions += 1,
						_ => (),
					}

					if next_pc != predicted_next_pc {
						match rob_entry.inst {
							Ucode::Branch { .. } => statistics.branch_mispredictions += 1,
							Ucode::Jal { .. } => statistics.jal_mispredictions += 1,
							_ => (),
						}

						rob.clear();
						pc = next_pc;
						x_regs.reset_all_tags();
						csrs.reset_all_tags();
					}
				}

				if let Some((rd, tag, value)) = rob_entry.rd {
					x_regs.store(rd, tag, value);

					for rob_entry in &mut rob {
						rob_entry.inst.update(tag, value);
					}
				}

				if let Some((csr, tag, value)) = rob_entry.csr {
					csrs.store(csr, tag, value);

					for rob_entry in &mut rob {
						rob_entry.inst.update(tag, value);
					}
				}

				retired = rob_entry.instret;
			}
			else {
				statistics.num_ticks_where_instructions_not_retired += 1;

				// Only the first entry gets to execute on memory functional unit

				if MemoryFunctionalUnit.try_execute(&mut rob_entry, memory) {
					next_rob.push(rob_entry);
				}
				else {
					rob.push_front(rob_entry);
				}
			}
		}

		while let Some(mut rob_entry) = rob.pop_front() {
			if let RobEntryState::Done = rob_entry.state {}
			else if let Some(integer_functional_unit) = integer_functional_units.pop() {
				if !integer_functional_unit.try_execute(&mut rob_entry) {
					integer_functional_units.push(integer_functional_unit);
				}
			}

			next_rob.push(rob_entry);
		}

		rob = next_rob.into();

		csrs.tick(1, retired);
	}
}

#[derive(Debug)]
struct RobEntry {
	state: RobEntryState,
	inst: Ucode,
	instret: i64,
	rd: Option<(XReg, Tag, i64)>,
	next_pc: Option<(i64, i64)>,
	csr: Option<(Csr, Tag, i64)>,
}

#[derive(Clone, Copy, Debug)]
enum RobEntryState {
	Pending,
	Wait(usize),
	Done,
}

struct IntegerFunctionalUnit;

impl IntegerFunctionalUnit {
	#[allow(clippy::unused_self)]
	fn try_execute(&self, rob_entry: &mut RobEntry) -> bool {
		match (rob_entry.inst, &mut rob_entry.state) {
			(Ucode::Abs { rd, rs: RegisterValue::Value(arg) }, RobEntryState::Pending) => {
				let result = arg.unsigned_abs().cast_signed();
				rob_entry.rd = Some((rd.0, rd.1, result));
			},

			(Ucode::Branch {
				op,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
				pc: RegisterValue::Value(pc),
				next_inst_pc,
				predicted_next_pc,
			}, RobEntryState::Pending) => {
				let next_pc =
					if op.exec(arg1, arg2) {
						pc
					}
					else {
						next_inst_pc
					};
				rob_entry.next_pc = Some((next_pc, predicted_next_pc));
			},

			(Ucode::Jal { rd, pc: RegisterValue::Value(pc), next_inst_pc, predicted_next_pc }, RobEntryState::Pending) => {
				rob_entry.rd = rd.map(|rd| (rd.0, rd.1, next_inst_pc));
				rob_entry.next_pc = Some((pc, predicted_next_pc));
			},

			(Ucode::Li { rd, value: RegisterValue::Value(value) }, RobEntryState::Pending) =>
				rob_entry.rd = Some((rd.0, rd.1, value)),

			(Ucode::LiCsr { csr, value: RegisterValue::Value(value) }, RobEntryState::Pending) =>
				rob_entry.csr = Some((csr.0, csr.1, value)),

			(Ucode::Op {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				#[allow(clippy::cast_possible_truncation)]
				let arg1b = arg1 as i8;
				#[allow(clippy::cast_possible_truncation)]
				let arg1h = arg1 as i32;
				let arg1uh = arg1h.cast_unsigned();
				#[allow(clippy::cast_possible_truncation)]
				let arg1w = arg1 as i32;
				let arg1uw = arg1w.cast_unsigned();

				#[allow(clippy::cast_possible_truncation)]
				let arg2w = arg2 as i32;

				let (value, wait) = match op {
					Op::Add => (arg1.wrapping_add(arg2), 0),
					Op::AddUw => (i64::from(arg1w.cast_unsigned()).wrapping_add(arg2), 0),
					Op::Addw => (arg1w.wrapping_add(arg2w).into(), 0),
					Op::And => (arg1 & arg2, 0),
					Op::Andn => (arg1 & !arg2, 0),
					Op::Bclr => (arg1 & !(1 << (arg2 & 0x3f)), 0),
					Op::Bext => ((arg1 >> (arg2 & 0x3f)) & 0x1, 0),
					Op::Binv => (arg1 ^ (1 << (arg2 & 0x3f)), 0),
					Op::Bset => (arg1 | (1 << (arg2 & 0x3f)), 0),
					Op::Clz => (arg1.leading_zeros().into(), 0),
					Op::Clzw => (arg1w.leading_zeros().into(), 0),
					Op::Cpop => (arg1.count_ones().into(), 2),
					Op::Cpopw => (arg1w.count_ones().into(), 2),
					Op::Ctz => (arg1.trailing_zeros().into(), 2),
					Op::Ctzw => (arg1w.trailing_zeros().into(), 2),
					Op::CzeroEqz => (if arg2 == 0 { 0 } else { arg1 }, 0),
					Op::CzeroNez => (if arg2 == 0 { arg1 } else { 0 }, 0),
					Op::Max => (arg1.max(arg2), 0),
					Op::Maxu => (arg1.cast_unsigned().max(arg2.cast_unsigned()).cast_signed(), 0),
					Op::Min => (arg1.min(arg2), 0),
					Op::Minu => (arg1.cast_unsigned().min(arg2.cast_unsigned()).cast_signed(), 0),
					Op::Mul => (arg1.wrapping_mul(arg2), 33),
					Op::Mulh => (((i128::from(arg1) * i128::from(arg2)) >> 64).try_into().unwrap(), 33),
					Op::Mulhsu => (((i128::from(arg1) * u128::from(arg2.cast_unsigned()).cast_signed()) >> 64).try_into().unwrap(), 33),
					Op::Mulhu => (((u128::from(arg1.cast_unsigned()) * u128::from(arg2.cast_unsigned())).cast_signed() >> 64).try_into().unwrap(), 33),
					Op::Mulw => (arg1w.wrapping_mul(arg2w).into(), 33),
					Op::Or => (arg1 | arg2, 0),
					Op::OrcB => (i64::from_le_bytes(arg1.to_le_bytes().map(|b| if b == 0 { 0x00 } else { 0xff })), 0),
					Op::Orn => (arg1 | !arg2, 0),
					Op::Rev8 => (i64::from_be_bytes(arg1.to_le_bytes()), 0),
					Op::Rol => (arg1.rotate_left((arg2 & 0x3f).try_into().unwrap()), 0),
					Op::Rolw => (arg1w.rotate_left((arg2w & 0x1f).try_into().unwrap()).into(), 0),
					Op::Ror => (arg1.rotate_right((arg2 & 0x3f).try_into().unwrap()), 0),
					Op::Rorw => (arg1w.rotate_right((arg2w & 0x1f).try_into().unwrap()).into(), 0),
					Op::SextB => (arg1b.into(), 0),
					Op::SextH => (arg1h.into(), 0),
					Op::Sh1add => ((arg1 << 1).wrapping_add(arg2), 0),
					Op::Sh1addUw => ((i64::from(arg1uw) << 1).wrapping_add(arg2), 0),
					Op::Sh2add => ((arg1 << 2).wrapping_add(arg2), 0),
					Op::Sh2addUw => ((i64::from(arg1uw) << 2).wrapping_add(arg2), 0),
					Op::Sh3add => ((arg1 << 3).wrapping_add(arg2), 0),
					Op::Sh3addUw => ((i64::from(arg1uw) << 3).wrapping_add(arg2), 0),
					Op::Sll => (arg1 << (arg2 & 0x3f), 0),
					Op::SllUw => ((u64::from(arg1uw) << (arg2 & 0x1f)).cast_signed(), 0),
					Op::Sllw => ((arg1w << (arg2w & 0x1f)).into(), 0),
					Op::Slt => ((arg1 < arg2).into(), 0),
					Op::Sltu => ((arg1.cast_unsigned() < arg2.cast_unsigned()).into(), 0),
					Op::Sra => (arg1 >> (arg2 & 0x3f), 0),
					Op::Sraw => ((arg1w >> (arg2w & 0x1f)).into(), 0),
					Op::Srl => ((arg1.cast_unsigned() >> (arg2 & 0x3f)).cast_signed(), 0),
					Op::Srlw => ((arg1w.cast_unsigned() >> (arg2w & 0x1f)).cast_signed().into(), 0),
					Op::Sub => (arg1.wrapping_sub(arg2), 0),
					Op::Subw => (arg1w.wrapping_sub(arg2w).into(), 0),
					Op::Xnor => (!(arg1 ^ arg2), 0),
					Op::Xor => (arg1 ^ arg2, 0),
					Op::ZextH => (i64::from(arg1uh), 0),
				};
				rob_entry.rd = Some((rd.0, rd.1, value));
				if wait > 0 {
					rob_entry.state = RobEntryState::Wait(wait);
					return true;
				}
			},

			(_, RobEntryState::Wait(0)) => (),

			(_, RobEntryState::Wait(w)) => {
				*w -= 1;
				return true;
			},

			_ => return false,
		}

		rob_entry.state = RobEntryState::Done;
		true
	}
}

struct MemoryFunctionalUnit;

impl MemoryFunctionalUnit {
	#[allow(clippy::unused_self)]
	fn try_execute(&self, rob_entry: &mut RobEntry, memory: &mut Memory) -> bool {
		match (rob_entry.inst, rob_entry.state) {
			(Ucode::Fence, RobEntryState::Pending) => (),

			(Ucode::Load { op, rd, addr: RegisterValue::Value(addr) }, RobEntryState::Pending) => {
				let result = op.exec(memory, addr);
				rob_entry.rd = Some((rd.0, rd.1, result));
			},

			(Ucode::Store {
				op,
				addr: RegisterValue::Value(addr),
				value: RegisterValue::Value(value),
			}, RobEntryState::Pending) =>
				op.exec(memory, addr, value),

			_ => return false,
		}

		rob_entry.state = RobEntryState::Done;
		true
	}
}
