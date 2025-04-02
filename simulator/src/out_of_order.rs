use crate::{
	csrs::Csrs,
	instruction::Instruction,
	memory::Memory,
	multiplier::{self, State},
	tag::{Tag, TagAllocator},
	ucode::{Ucode, BinaryOp, MulOp, UnaryOp},
	x_regs::XRegs,
	LogLevel,
	RegisterValue,
	Statistics,
	load_inst,
};

const ROB_MAX_LEN: usize = 32;

pub(crate) fn run(
	memory: &mut Memory,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	statistics: &mut Statistics,
	mut pc: i64,
	max_retire_per_cycle: std::num::NonZero<usize>,
	log_level: LogLevel,
) {
	let mut rob = std::collections::VecDeque::<RobEntry>::with_capacity(ROB_MAX_LEN);

	let mut tag_allocator: TagAllocator = Default::default();

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
				for rob_entry in &rob {
					eprintln!("- {rob_entry:?}");
				}
			}
		}

		let Some(retired) = execute(
			&mut rob,
			max_retire_per_cycle,
			&mut pc,
			x_regs,
			csrs,
			memory,
			statistics,
			log_level,
		) else { return; };

		fetch(
			&mut rob,
			&mut pc,
			x_regs,
			csrs,
			memory,
			statistics,
			&mut tag_allocator,
			log_level,
		);

		csrs.tick(1, retired);

		if log_level >= LogLevel::Trace {
			eprintln!("->");
			eprintln!("{x_regs}");
			eprintln!("{csrs}");
			for rob_entry in &rob {
				eprintln!("- {rob_entry:?}");
			}
		}
	}
}

fn fetch(
	rob: &mut std::collections::VecDeque<RobEntry>,
	pc: &mut i64,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	memory: &mut Memory,
	statistics: &mut Statistics,
	tag_allocator: &mut TagAllocator,
	log_level: LogLevel,
) {
	if rob.len() < ROB_MAX_LEN - 3 && let Ok((inst, inst_len, instret)) = load_inst(memory, *pc, statistics) {
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

			// TODO: Instruction::Jalr
			//
			// # Return address stack
			//
			// Ref: 2.5.1 Unconditional jumps
			//
			// ## `jal rd, offset`
			//
			// +----+------------+
			// | rd | RAS action |
			// +====+============+
			// | x1 | Push       |
			// | x5 | Push       |
			// | _  | None       |
			// +----+------------+
			//
			// ## `jalr rd, offset(rs1)`
			//
			// +----+-----+----------------+
			// | rd | rs1 |   RAS action   |
			// +====+=====+================+
			// | x1 | x5  | Pop, then push |
			// | x5 | x1  | Pop, then push |
			// | x1 | _   | Push           |
			// | x5 | _   | Push           |
			// | _  | x1  | Pop            |
			// | _  | x5  | Pop            |
			// | _  | _   | None           |
			// +----+-----+----------------+
			//
			//
			// # Other cases
			//
			// If rs1 is available, no prediction needed.
			//
			// `if let RegisterValue::Value(arg1) = x_regs.load(rs1) { arg1.wrapping_add(imm) & -2 }`

			_ => pc.wrapping_add(inst_len),
		};

		let tags = tag_allocator.allocate();
		let ucode_1234 = Ucode::new(
			inst,
			*pc,
			next_inst_pc,
			predicted_next_pc,
			x_regs,
			csrs,
			tags,
		);
		if let Some((ucode_1, ucode_234)) = ucode_1234 {
			if let Ucode::Jump { .. } = ucode_1 {
				statistics.jump_predictions += 1;
			}
			rob.push_back(RobEntry {
				state: RobEntryState::initial_state(&ucode_1),
				inst: ucode_1,
				instret: ucode_234.map_or(instret, |_| 0),
			});

			if let Some((ucode_2, ucode_34)) = ucode_234 {
				if let Ucode::Jump { .. } = ucode_2 {
					statistics.jump_predictions += 1;
				}
				rob.push_back(RobEntry {
					state: RobEntryState::initial_state(&ucode_2),
					inst: ucode_2,
					instret: ucode_34.map_or(instret, |_| 0),
				});

				if let Some((ucode_3, ucode_4)) = ucode_34 {
					if let Ucode::Jump { .. } = ucode_3 {
						statistics.jump_predictions += 1;
					}
					rob.push_back(RobEntry {
						state: RobEntryState::initial_state(&ucode_3),
						inst: ucode_3,
						instret: ucode_4.map_or(instret, |_| 0),
					});

					if let Some(ucode_4) = ucode_4 {
						if let Ucode::Jump { .. } = ucode_4 {
							statistics.jump_predictions += 1;
						}
						rob.push_back(RobEntry {
							state: RobEntryState::initial_state(&ucode_4),
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

		*pc = predicted_next_pc;
	}
}

fn execute(
	rob: &mut std::collections::VecDeque<RobEntry>,
	max_retire_per_cycle: std::num::NonZero<usize>,
	pc: &mut i64,
	x_regs: &mut XRegs,
	csrs: &mut Csrs,
	memory: &mut Memory,
	statistics: &mut Statistics,
	log_level: LogLevel,
) -> Option<i64> {
	let mut remaining_retire = max_retire_per_cycle.get();

	let mut next_rob = std::collections::VecDeque::with_capacity(rob.len());

	if let Some(mut rob_entry) = rob.pop_front() {
		if let Ucode::Ebreak = rob_entry.inst {
			return None;
		}

		if matches!(rob_entry.state, RobEntryState::Pending) {
			remaining_retire = 0;
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

	let functional_units: [&mut dyn FunctionalUnit; 14] = [
		&mut AddFunctionalUnit("add1"),
		&mut AddFunctionalUnit("add2"),
		&mut CpopFunctionalUnit("cpop1"),
		&mut CpopFunctionalUnit("cpop2"),
		&mut CzeroFunctionalUnit("czero1"),
		&mut CzeroFunctionalUnit("czero2"),
		&mut ExtFunctionalUnit("ext1"),
		&mut ExtFunctionalUnit("ext2"),
		&mut MulFunctionalUnit("mul1"),
		&mut MulFunctionalUnit("mul2"),
		&mut OrFunctionalUnit("or1"),
		&mut OrFunctionalUnit("or2"),
		&mut ShiftFunctionalUnit("shift1"),
		&mut ShiftFunctionalUnit("shift2"),
	];
	let mut functional_units: Vec<_> = functional_units.into();

	let mut retired = 0;
	let mut misprediction = false;
	let mut done_tags = vec![];

	while let Some(mut rob_entry) = rob.pop_front() {
		if matches!(rob_entry.state, RobEntryState::Done) {
			if !misprediction {
				if let Some((rd, tag, value)) = rob_entry.inst.done_rd() {
					done_tags.push((tag, value));

					if remaining_retire > 0 {
						x_regs.store(rd, tag, value);
					}
				}

				if let Some((csr, tag, value)) = rob_entry.inst.done_csr() {
					done_tags.push((tag, value));

					if remaining_retire > 0 {
						csrs.store(csr, tag, value);
					}
				}

				if let Ucode::Jump { pc: RegisterValue::Value(next_pc), predicted_next_pc } = rob_entry.inst && next_pc != predicted_next_pc {
					misprediction = true;
					statistics.jump_mispredictions += 1;
					remaining_retire = 0;
					if log_level >= LogLevel::Trace {
						eprintln!("jump misprediction!");
					}

					*pc = next_pc;
					x_regs.reset_all_tags(next_rob.iter().filter_map(|rob_entry| rob_entry.inst.rd()));
					csrs.reset_all_tags(next_rob.iter().filter_map(|rob_entry| rob_entry.inst.csr()));

					rob_entry = RobEntry {
						state: RobEntryState::Done,
						inst: Ucode::Jump { pc: RegisterValue::Value(next_pc), predicted_next_pc: next_pc },
						instret: rob_entry.instret,
					};
				}

				if let Some(r) = remaining_retire.checked_sub(1) {
					remaining_retire = r;
					retired += rob_entry.instret;
				}
				else {
					next_rob.push_back(rob_entry);
				}
			}
		}
		else {
			remaining_retire = 0;

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

			if !misprediction {
				next_rob.push_back(rob_entry);
			}
		}
	}

	*rob = next_rob;

	for (tag, value) in done_tags {
		for rob_entry in &mut *rob {
			if !(matches!(rob_entry.state, RobEntryState::Done)) {
				rob_entry.update(tag, value);
			}
		}
	}

	for functional_unit in functional_units {
		_ = *statistics.fu_utilization.entry(functional_unit.statistics_key()).or_default();
	}

	if retired == 0 {
		statistics.num_ticks_where_instructions_not_retired += 1;
	}
	else {
		statistics.num_ticks_where_instructions_retired += 1;
	}

	Some(retired)
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
	Done,
}

impl RobEntry {
	fn update(&mut self, tag: Tag, new_value: i64) {
		if !(matches!(self.state, RobEntryState::Done)) {
			self.inst.update(tag, new_value);
			if matches!(self.state, RobEntryState::Pending) {
				self.state = RobEntryState::initial_state(&self.inst);
			}
		}
	}
}

impl RobEntryState {
	fn initial_state(inst: &Ucode) -> Self {
		if inst.done() {
			Self::Done
		}
		else {
			Self::Pending
		}
	}
}

trait FunctionalUnit {
	fn statistics_key(&self) -> &'static str;

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool;
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
					BinaryOp::AddUw => i64::from(arg1uw).wrapping_add(arg2),
					BinaryOp::Addw => arg1w.wrapping_add(arg2w).into(),
					BinaryOp::And => arg1 & arg2,
					BinaryOp::Andn => arg1 & !arg2,
					BinaryOp::Sh1add => (arg1 << 1).wrapping_add(arg2),
					BinaryOp::Sh1addUw => (i64::from(arg1uw) << 1).wrapping_add(arg2),
					BinaryOp::Sh2add => (arg1 << 2).wrapping_add(arg2),
					BinaryOp::Sh2addUw => (i64::from(arg1uw) << 2).wrapping_add(arg2),
					BinaryOp::Sh3add => (arg1 << 3).wrapping_add(arg2),
					BinaryOp::Sh3addUw => (i64::from(arg1uw) << 3).wrapping_add(arg2),
					BinaryOp::Slt => (arg1 < arg2).into(),
					BinaryOp::Sltu => (arg1.cast_unsigned() < arg2.cast_unsigned()).into(),
					BinaryOp::Sub => arg1.wrapping_sub(arg2),
					BinaryOp::Subw => arg1w.wrapping_sub(arg2w).into(),
					BinaryOp::Xnor => arg1 ^ !arg2,
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

				#[allow(clippy::match_wildcard_for_single_variants)]
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

struct CzeroFunctionalUnit(&'static str);

impl FunctionalUnit for CzeroFunctionalUnit {
	fn statistics_key(&self) -> &'static str { self.0 }

	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Csel {
				rd,
				rcond: RegisterValue::Value(0),
				rs_eqz: RegisterValue::Value(value),
				rs_nez: RegisterValue::Value(_),
			}, RobEntryState::Pending) => {
				rd.2 = Some(*value);
				rob_entry.state = RobEntryState::Done;
				true
			},

			(Ucode::Csel {
				rd,
				rcond: RegisterValue::Value(rcond),
				rs_eqz: RegisterValue::Value(_),
				rs_nez: RegisterValue::Value(value),
			}, RobEntryState::Pending) if *rcond != 0 => {
				rd.2 = Some(*value);
				rob_entry.state = RobEntryState::Done;
				true
			},

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
				let value = match *op {
					UnaryOp::SextB => (arg as i8).into(),
					UnaryOp::SextH => (arg as i16).into(),
					UnaryOp::SextW => (arg as i32).into(),
					UnaryOp::ZextB => (arg.cast_unsigned() as u8).into(),
					UnaryOp::ZextH => (arg.cast_unsigned() as u16).into(),
					UnaryOp::ZextW => (arg.cast_unsigned() as u32).into(),
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

	#[allow(clippy::many_single_char_names)]
	fn try_execute(&mut self, rob_entry: &mut RobEntry) -> bool {
		match (&mut rob_entry.inst, rob_entry.state) {
			(Ucode::Mul {
				op,
				rd,
				rs1: RegisterValue::Value(arg1),
				rs2: RegisterValue::Value(arg2),
				state,
			}, RobEntryState::Pending) => {
				let (arg1_is_signed, arg1) = match *op {
					MulOp::Mul |
					MulOp::Mulh |
					MulOp::Mulhsu => (true, *arg1),

					MulOp::Mulhu => (false, *arg1),

					#[allow(clippy::cast_possible_truncation)]
					MulOp::Mulw => (true, (*arg1 as i32).into()),
				};

				let (i, p) = state.get_or_insert_with(|| match *op {
					MulOp::Mul |
					MulOp::Mulh => State::initial(true, *arg2),

					MulOp::Mulhsu |
					MulOp::Mulhu => State::initial(false, *arg2),

					#[allow(clippy::cast_possible_truncation)]
					MulOp::Mulw => State::initial(true, (*arg2 as i32).into()),
				});

				match multiplier::round(arg1_is_signed, arg1, *i, *p) {
					State::Pending { i: i_, p: p_ } => {
						*i = i_;
						*p = p_;
					},

					State::Mulw { i: i_, p: p_, mulw } =>
						if matches!(*op, MulOp::Mulw) {
							rd.2 = Some(mulw.into());
							rob_entry.state = RobEntryState::Done;
						}
						else {
							*i = i_;
							*p = p_;
						},

					State::Mul { mul, mulh } =>
						if matches!(*op, MulOp::Mul) {
							rd.2 = Some(mul);
							rob_entry.state = RobEntryState::Done;
						}
						else {
							rd.2 = Some(mulh);
							rob_entry.state = RobEntryState::Done;
						},
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
					BinaryOp::Rol => arg1.rotate_left((arg2 & 0x3f).try_into().unwrap()),
					BinaryOp::Rolw => arg1w.rotate_left((arg2w & 0x1f).try_into().unwrap()).into(),
					BinaryOp::Ror => arg1.rotate_right((arg2 & 0x3f).try_into().unwrap()),
					BinaryOp::Rorw => arg1w.rotate_right((arg2w & 0x1f).try_into().unwrap()).into(),
					BinaryOp::Sll => arg1 << (arg2 & 0x3f),
					BinaryOp::SllUw => i64::from(arg1uw) << (arg2 & 0x3f),
					BinaryOp::Sllw => (arg1w << (arg2w & 0x1f)).into(),
					BinaryOp::Sra => arg1 >> (arg2 & 0x3f),
					BinaryOp::Sraw => (arg1w >> (arg2w & 0x1f)).into(),
					BinaryOp::Srl => (arg1.cast_unsigned() >> (arg2 & 0x3f)).cast_signed(),
					BinaryOp::Srlw => (arg1uw >> (arg2w & 0x1f)).cast_signed().into(),
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
