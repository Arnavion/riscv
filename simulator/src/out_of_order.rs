use crate::{
	csrs::{Csr, Csrs},
	instruction::Instruction,
	memory::Memory,
	ucode::{Ucode, BinaryOp, UnaryOp},
	x_regs::{XReg, XRegs},
	LogLevel,
	RegisterValue, Tag,
	Statistics,
	load_inst,
	macro_op_fuse,
};

pub(crate) fn run(
	memory: &mut Memory,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	statistics: &mut Statistics,
	mut pc: i64,
	max_retire_per_cycle: std::num::NonZero<usize>,
	log_level: LogLevel,
) {
	const ROB_MAX_LEN: usize = 32;

	let mut tick = 0_u64;

	let mut rob = std::collections::VecDeque::<RobEntry>::with_capacity(ROB_MAX_LEN);

	let mut next_renamed_register_tag: Tag = Default::default();

	loop {
		assert!(pc != 0);
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
			for rob_entry in &rob {
				eprintln!("- {rob_entry:?}");
			}
		}

		let mut retired = 0;
		let mut remaining_retire = max_retire_per_cycle.get();

		let mut next_rob = std::collections::VecDeque::with_capacity(ROB_MAX_LEN);

		while let Some(rob_entry) = rob.pop_front() {
			if matches!(rob_entry.state, RobEntryState::Done) {
				if let Some((rd, tag, value)) = rob_entry.done_rd() {
					if remaining_retire > 0 {
						x_regs.store(rd, tag, value);
					}

					for rob_entry in &mut rob {
						rob_entry.inst.update(tag, value);
					}
				}

				if let Some((csr, tag, value)) = rob_entry.done_csr() {
					if remaining_retire > 0 {
						csrs.store(csr, tag, value);
					}

					for rob_entry in &mut rob {
						rob_entry.inst.update(tag, value);
					}
				}

				if let Ucode::Jump { pc: RegisterValue::Value(next_pc), predicted_next_pc } = rob_entry.inst {
					statistics.jump_predictions += 1;

					if next_pc != predicted_next_pc {
						statistics.jump_mispredictions += 1;

						if log_level >= LogLevel::Trace {
							eprintln!("jump misprediction!");
						}

						rob.clear();
						pc = next_pc;
						x_regs.reset_all_tags(next_rob.iter().filter_map(RobEntry::rd));
						csrs.reset_all_tags(next_rob.iter().filter_map(RobEntry::csr));

						if remaining_retire > 0 {
							retired += rob_entry.instret;
						}

						break;
					}
				}

				if remaining_retire > 0 {
					remaining_retire -= 1;
					retired += rob_entry.instret;
				}
				else {
					next_rob.push_back(rob_entry);
				}
			}
			else {
				remaining_retire = 0;

				next_rob.push_back(rob_entry);
			}
		}

		rob = next_rob;

		let mut next_rob = std::collections::VecDeque::with_capacity(ROB_MAX_LEN);

		if let Some(mut rob_entry) = rob.pop_front() {
			if let Ucode::Ebreak = rob_entry.inst {
				break;
			}

			// Only the first entry gets to execute on memory functional unit
			if MemoryFunctionalUnit.try_execute(&mut rob_entry, memory) {
				*statistics.fu_utilization.entry("memory").or_default() += 1;
				next_rob.push_back(rob_entry);
			}
			else {
				rob.push_front(rob_entry);
			}
		}

		let functional_units: [&mut dyn FunctionalUnit; 30] = [
			&mut CzeroFunctionalUnit("czero1"),
			&mut CzeroFunctionalUnit("czero2"),
			&mut JumpFunctionalUnit("jump1"),
			&mut JumpFunctionalUnit("jump2"),
			&mut LiFunctionalUnit("li1"),
			&mut LiFunctionalUnit("li2"),
			&mut LiCsrFunctionalUnit("licsr1"),
			&mut LiCsrFunctionalUnit("licsr2"),
			&mut AddFunctionalUnit("add1"),
			&mut AddFunctionalUnit("add2"),
			&mut AndFunctionalUnit("and1"),
			&mut AndFunctionalUnit("and2"),
			&mut CpopFunctionalUnit("cpop1"),
			&mut CpopFunctionalUnit("cpop2"),
			&mut ExtFunctionalUnit("ext1"),
			&mut ExtFunctionalUnit("ext2"),
			&mut GrevFunctionalUnit("grev1"),
			&mut GrevFunctionalUnit("grev2"),
			&mut MulFunctionalUnit("mul1"),
			&mut MulFunctionalUnit("mul2"),
			&mut OrFunctionalUnit("or1"),
			&mut OrFunctionalUnit("or2"),
			&mut OrcBFunctionalUnit("orc.b1"),
			&mut OrcBFunctionalUnit("orc.b2"),
			&mut ShiftFunctionalUnit("shift1"),
			&mut ShiftFunctionalUnit("shift2"),
			&mut SltFunctionalUnit("slt1"),
			&mut SltFunctionalUnit("slt2"),
			&mut XorFunctionalUnit("xor1"),
			&mut XorFunctionalUnit("xor2"),
		];
		let mut functional_units: Vec<_> = functional_units.into();

		while let Some(mut rob_entry) = rob.pop_front() {
			let mut executed = false;
			functional_units.retain_mut(|functional_unit| {
				if executed {
					return true;
				}

				if functional_unit.try_execute(&mut rob_entry) {
					*statistics.fu_utilization.entry(functional_unit.statistics_key()).or_default() += 1;
					executed = true;
					false
				}
				else {
					true
				}
			});

			next_rob.push_back(rob_entry);
		}

		rob = next_rob;

		if retired == 0 {
			statistics.num_ticks_where_instructions_not_retired += 1;
		}
		else {
			statistics.num_ticks_where_instructions_retired += 1;
		}

		csrs.tick(1, retired);

		if rob.len() < ROB_MAX_LEN - 3 {
			let inst = load_inst(memory, pc);
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

				let ucode_1234 = Ucode::new(
					inst,
					pc,
					next_inst_pc,
					predicted_next_pc,
					x_regs,
					csrs,
					&mut next_renamed_register_tag,
				);
				if let Some((ucode_1, ucode_234)) = ucode_1234 {
					rob.push_back(RobEntry {
						state: RobEntryState::Pending,
						inst: ucode_1,
						instret: ucode_234.map_or(instret, |_| 0),
					});

					if let Some((ucode_2, ucode_34)) = ucode_234 {
						rob.push_back(RobEntry {
							state: RobEntryState::Pending,
							inst: ucode_2,
							instret: ucode_34.map_or(instret, |_| 0),
						});

						if let Some((ucode_3, ucode_4)) = ucode_34 {
							rob.push_back(RobEntry {
								state: RobEntryState::Pending,
								inst: ucode_3,
								instret: ucode_4.map_or(instret, |_| 0),
							});

							if let Some(ucode_4) = ucode_4 {
								rob.push_back(RobEntry {
									state: RobEntryState::Pending,
									inst: ucode_4,
									instret,
								});
							}
						}
					}
				}

				if log_level >= LogLevel::Trace {
					eprintln!("+ 0x{pc:016x} : {inst:?}");
				}

				pc = predicted_next_pc;
			}
		}

		if log_level >= LogLevel::Trace {
			eprintln!("->");
			eprintln!("{x_regs}");
			for rob_entry in &rob {
				eprintln!("- {rob_entry:?}");
			}
		}

		tick += 1;
	}
}

#[derive(Debug)]
struct RobEntry {
	state: RobEntryState,
	inst: Ucode,
	instret: i64,
}

#[derive(Clone, Copy, Debug)]
enum RobEntryState {
	Pending,
	CpopWait(usize),
	MulWait(usize),
	Done,
}

impl RobEntry {
	fn rd(&self) -> Option<(XReg, Tag, Option<i64>)> {
		match self.inst {
			Ucode::BinaryOp { rd, .. } |
			Ucode::Czero { rd, .. } |
			Ucode::Load { rd, .. } |
			Ucode::UnaryOp { rd, .. }
				=> Some(rd),

			Ucode::Li { rd: (rd, tag), value: RegisterValue::Value(value) }
				=> Some((rd, tag, Some(value))),

			Ucode::Li { rd: (rd, tag), value: RegisterValue::Tag(_) }
				=> Some((rd, tag, None)),

			Ucode::Ebreak |
			Ucode::Fence |
			Ucode::Jump { .. } |
			Ucode::LiCsr { .. } |
			Ucode::Store { .. }
				=> None,
		}
	}

	fn done_rd(&self) -> Option<(XReg, Tag, i64)> {
		let (rd, rd_tag, value) = self.rd()?;
		Some((rd, rd_tag, value?))
	}

	fn csr(&self) -> Option<(Csr, Tag, Option<i64>)> {
		match self.inst {
			Ucode::LiCsr { csr: (csr, tag), value: RegisterValue::Value(value) }
				=> Some((csr, tag, Some(value))),

			Ucode::LiCsr { csr: (csr, tag), value: RegisterValue::Tag(_) }
				=> Some((csr, tag, None)),

			_ => None,
		}
	}

	fn done_csr(&self) -> Option<(Csr, Tag, i64)> {
		let (csr, csr_tag, value) = self.csr()?;
		Some((csr, csr_tag, value?))
	}
}

trait FunctionalUnit {
	fn statistics_key(&self) -> &'static str;

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool;
}

struct CzeroFunctionalUnit(&'static str);

impl FunctionalUnit for CzeroFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Czero {
				rd,
				rcond: RegisterValue::Value(0),
				rs_eqz: RegisterValue::Value(value),
				rs_nez: _,
			}, RobEntryState::Pending) => {
				rd.2 = Some(*value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			(Ucode::Czero {
				rd,
				rcond: RegisterValue::Value(rcond),
				rs_eqz: _,
				rs_nez: RegisterValue::Value(value),
			}, RobEntryState::Pending) if *rcond != 0 => {
				rd.2 = Some(*value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct JumpFunctionalUnit(&'static str);

impl FunctionalUnit for JumpFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Jump { pc: RegisterValue::Value(_), predicted_next_pc: _ }, RobEntryState::Pending) => {
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct LiFunctionalUnit(&'static str);

impl FunctionalUnit for LiFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Li { rd: _, value: RegisterValue::Value(_) }, RobEntryState::Pending) => {
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct LiCsrFunctionalUnit(&'static str);

impl FunctionalUnit for LiCsrFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::LiCsr { csr: _, value: RegisterValue::Value(_) }, RobEntryState::Pending) => {
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct AddFunctionalUnit(&'static str);

impl FunctionalUnit for AddFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				#[allow(clippy::cast_possible_truncation)]
				let arg1w = arg1 as i32;
				let arg1uw = arg1w.cast_unsigned();

				#[allow(clippy::cast_possible_truncation)]
				let arg2w = arg2 as i32;

				let value = match *op {
					BinaryOp::Add => arg1.wrapping_add(arg2),
					BinaryOp::AddUw => i64::from(arg1w.cast_unsigned()).wrapping_add(arg2),
					BinaryOp::Addw => arg1w.wrapping_add(arg2w).into(),
					BinaryOp::Sh1add => (arg1 << 1).wrapping_add(arg2),
					BinaryOp::Sh1addUw => (i64::from(arg1uw) << 1).wrapping_add(arg2),
					BinaryOp::Sh2add => (arg1 << 2).wrapping_add(arg2),
					BinaryOp::Sh2addUw => (i64::from(arg1uw) << 2).wrapping_add(arg2),
					BinaryOp::Sh3add => (arg1 << 3).wrapping_add(arg2),
					BinaryOp::Sh3addUw => (i64::from(arg1uw) << 3).wrapping_add(arg2),
					BinaryOp::Sub => arg1.wrapping_sub(arg2),
					BinaryOp::Subw => arg1w.wrapping_sub(arg2w).into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct AndFunctionalUnit(&'static str);

impl FunctionalUnit for AndFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				let value = match *op {
					BinaryOp::And => arg1 & arg2,
					BinaryOp::Andn => arg1 & !arg2,
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct CpopFunctionalUnit(&'static str);

impl FunctionalUnit for CpopFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::UnaryOp {
				op,
				rd,
				rs: RegisterValue::Value(arg),
			}, RobEntryState::Pending) => {
				let arg = *arg;

				#[allow(clippy::cast_possible_truncation)]
				let argw = arg as i32;

				let value = match *op {
					UnaryOp::Cpop => arg.count_ones().into(),
					UnaryOp::Cpopw => argw.count_ones().into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::CpopWait(0);
				true
			},

			(_, RobEntryState::CpopWait(w)) => {
				if let Some(next_w) = w.checked_sub(1) {
					rob_entry.state = RobEntryState::CpopWait(next_w);
				}
				else {
					rob_entry.state = RobEntryState::Done;
				}
				true
			},

			_ => false,
		}
	}
}

struct ExtFunctionalUnit(&'static str);

impl FunctionalUnit for ExtFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::UnaryOp {
				op,
				rd,
				rs: RegisterValue::Value(arg),
			}, RobEntryState::Pending) => {
				let arg = *arg;

				#[allow(clippy::cast_possible_truncation)]
				let argb = arg as i8;
				#[allow(clippy::cast_possible_truncation)]
				let argh = arg as i32;

				let value = match *op {
					UnaryOp::SextB => argb.into(),
					UnaryOp::SextH => argh.into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct GrevFunctionalUnit(&'static str);

impl FunctionalUnit for GrevFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				let value = match *op {
					#[allow(clippy::unreadable_literal)]
					BinaryOp::Grev => {
						let value = arg1.cast_unsigned();
						let value = (value << (arg2 & 0b100000)) | (value >> (arg2 & 0b100000));
						let value = ((value & 0x0000ffff_0000ffff) << (arg2 & 0b010000)) | ((value & 0xffff0000_ffff0000) >> (arg2 & 0b010000));
						let value = ((value & 0x00ff00ff_00ff00ff) << (arg2 & 0b001000)) | ((value & 0xff00ff00_ff00ff00) >> (arg2 & 0b001000));
						let value = ((value & 0x0f0f0f0f_0f0f0f0f) << (arg2 & 0b000100)) | ((value & 0xf0f0f0f0_f0f0f0f0) >> (arg2 & 0b000100));
						let value = ((value & 0x33333333_33333333) << (arg2 & 0b000010)) | ((value & 0xcccccccc_cccccccc) >> (arg2 & 0b000010));
						let value = ((value & 0x55555555_55555555) << (arg2 & 0b000001)) | ((value & 0xaaaaaaaa_aaaaaaaa) >> (arg2 & 0b000001));
						value.cast_signed()
					},
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct MulFunctionalUnit(&'static str);

impl FunctionalUnit for MulFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				#[allow(clippy::cast_possible_truncation)]
				let arg1w = arg1 as i32;

				#[allow(clippy::cast_possible_truncation)]
				let arg2w = arg2 as i32;

				let value = match *op {
					BinaryOp::Mul => arg1.wrapping_mul(arg2),
					BinaryOp::Mulh => ((i128::from(arg1) * i128::from(arg2)) >> 64).try_into().unwrap(),
					BinaryOp::Mulhsu => ((i128::from(arg1) * u128::from(arg2.cast_unsigned()).cast_signed()) >> 64).try_into().unwrap(),
					BinaryOp::Mulhu => ((u128::from(arg1.cast_unsigned()) * u128::from(arg2.cast_unsigned())).cast_signed() >> 64).try_into().unwrap(),
					BinaryOp::Mulw => arg1w.wrapping_mul(arg2w).into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::MulWait(32);
				true
			},

			(_, RobEntryState::MulWait(w)) => {
				if let Some(next_w) = w.checked_sub(1) {
					rob_entry.state = RobEntryState::MulWait(next_w);
				}
				else {
					rob_entry.state = RobEntryState::Done;
				}
				true
			},

			_ => false,
		}
	}
}

struct OrFunctionalUnit(&'static str);

impl FunctionalUnit for OrFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				let value = match *op {
					BinaryOp::Or => arg1 | arg2,
					BinaryOp::Orn => arg1 | !arg2,
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct OrcBFunctionalUnit(&'static str);

impl FunctionalUnit for OrcBFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::UnaryOp {
				op,
				rd,
				rs: RegisterValue::Value(arg),
			}, RobEntryState::Pending) => {
				let value = match *op {
					UnaryOp::OrcB => i64::from_ne_bytes(arg.to_ne_bytes().map(|b| if b == 0 { 0x00 } else { 0xff })),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct ShiftFunctionalUnit(&'static str);

impl FunctionalUnit for ShiftFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				#[allow(clippy::cast_possible_truncation)]
				let arg1w = arg1 as i32;
				let arg1uw = arg1w.cast_unsigned();

				#[allow(clippy::cast_possible_truncation)]
				let arg2w = arg2 as i32;

				let value = match *op {
					BinaryOp::Rol => arg1.rotate_left((arg2 & 0x3f).try_into().unwrap()),
					BinaryOp::Rolw => arg1w.rotate_left((arg2w & 0x1f).try_into().unwrap()).into(),
					BinaryOp::Ror => arg1.rotate_right((arg2 & 0x3f).try_into().unwrap()),
					BinaryOp::Rorw => arg1w.rotate_right((arg2w & 0x1f).try_into().unwrap()).into(),
					BinaryOp::Sll => arg1 << (arg2 & 0x3f),
					BinaryOp::SllUw => i64::from(arg1uw) << (arg2 & 0x1f),
					BinaryOp::Sllw => (arg1w << (arg2w & 0x1f)).into(),
					BinaryOp::Sra => arg1 >> (arg2 & 0x3f),
					BinaryOp::Sraw => (arg1w >> (arg2w & 0x1f)).into(),
					BinaryOp::Srl => (arg1.cast_unsigned() >> (arg2 & 0x3f)).cast_signed(),
					BinaryOp::Srlw => (arg1w.cast_unsigned() >> (arg2w & 0x1f)).cast_signed().into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct SltFunctionalUnit(&'static str);

impl FunctionalUnit for SltFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				let value = match *op {
					BinaryOp::Slt => (arg1 < arg2).into(),
					BinaryOp::Sltu => (arg1.cast_unsigned() < arg2.cast_unsigned()).into(),
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct XorFunctionalUnit(&'static str);

impl FunctionalUnit for XorFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::BinaryOp {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
			}, RobEntryState::Pending) => {
				let arg1 = *arg1;
				let arg2 = *arg2;

				let value = match *op {
					BinaryOp::Xnor => !(arg1 ^ arg2),
					BinaryOp::Xor => arg1 ^ arg2,
					_ => return false,
				};
				rd.2 = Some(value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}

struct MemoryFunctionalUnit;

impl MemoryFunctionalUnit {
	#[allow(clippy::unused_self)]
	fn try_execute(&mut self, rob_entry: &mut RobEntry, memory: &mut Memory) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Fence, RobEntryState::Pending) => {
				rob_entry.state = RobEntryState::Done;
				true
			},

			(Ucode::Load { op, rd, addr: RegisterValue::Value(addr) }, RobEntryState::Pending) => {
				let result = op.exec(memory, *addr);
				rd.2 = Some(result);
				rob_entry.state = RobEntryState::Done;
				true
			},

			(Ucode::Store {
				op,
				addr: RegisterValue::Value(addr),
				value: RegisterValue::Value(value),
			}, RobEntryState::Pending) => {
				op.exec(memory, *addr, *value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			_ => false,
		}
	}
}
