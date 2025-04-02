use crate::{
	csrs::Csrs,
	instruction::Instruction,
	memory::Memory,
	multiplier::{self, State},
	tag::TagAllocator,
	ucode::{Ucode, BinaryOp, MulOp, UnaryOp},
	x_regs::XRegs,
	LogLevel,
	RegisterValue,
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

		let next_inst_pc = pc.wrapping_add(inst_len);
		let predicted_next_pc = match inst {
			// Constant
			Instruction::Jal { rd: _, imm } => pc.wrapping_add(imm),

			_ => pc.wrapping_add(inst_len),
		};

		let mut cycles = 0;
		let ucode_1234 = Ucode::new(
			inst,
			pc,
			next_inst_pc,
			predicted_next_pc,
			x_regs,
			csrs,
			TagAllocator::default().allocate(),
		);
		let mut ucodes = std::collections::VecDeque::with_capacity(4);
		if let Some((ucode_1, ucode_234)) = ucode_1234 {
			ucodes.push_back(ucode_1);
			if let Some((ucode_2, ucode_34)) = ucode_234 {
				ucodes.push_back(ucode_2);
				if let Some((ucode_3, ucode_4)) = ucode_34 {
					ucodes.push_back(ucode_3);
					if let Some(ucode_4) = ucode_4 {
						ucodes.push_back(ucode_4);
					}
				}
			}
		}

		pc = next_inst_pc;

		while let Some(mut ucode) = ucodes.pop_front() {
			if let Ucode::Ebreak = ucode {
				return;
			}

			cycles += execute(&mut ucode, memory);

			if let Some((rd, tag, value)) = ucode.done_rd() {
				x_regs.store(rd, tag, value);
				for ucode in &mut ucodes {
					ucode.update(tag, value);
				}
			}
			if let Some((csr, tag, value)) = ucode.done_csr() {
				csrs.store(csr, tag, value);
				for ucode in &mut ucodes {
					ucode.update(tag, value);
				}
			}

			if let Ucode::Jump { pc: RegisterValue::Value(next_pc), predicted_next_pc: _ } = ucode {
				pc = next_pc;
			}
		}

		statistics.num_ticks_where_instructions_retired += 1;
		statistics.num_ticks_where_instructions_not_retired += usize::from(cycles) - 1;

		csrs.tick(cycles.into(), instret);

		if log_level >= LogLevel::Trace {
			eprintln!("->");
			eprintln!("{x_regs}");
			eprintln!("{csrs}");
		}
	}
}

fn execute(inst: &mut Ucode, memory: &mut Memory) -> u8 {
	#[allow(clippy::match_same_arms)]
	match inst {
		Ucode::BinaryOp {
			op,
			rd,
			rs1: RegisterValue::Value(arg1),
			rs2: RegisterValue::Value(arg2),
		} => {
			let arg1 = *arg1;
			let arg2 = *arg2;

			#[allow(clippy::cast_possible_truncation)]
			let arg1w = arg1 as i32;
			let arg1uw = arg1w.cast_unsigned();

			#[allow(clippy::cast_possible_truncation)]
			let arg2w = arg2 as i32;

			let (value, cycles) = match *op {
				BinaryOp::Add => (arg1.wrapping_add(arg2), 1),
				BinaryOp::AddUw => (i64::from(arg1uw).wrapping_add(arg2), 1),
				BinaryOp::Addw => (arg1w.wrapping_add(arg2w).into(), 1),
				BinaryOp::And => (arg1 & arg2, 1),
				BinaryOp::Andn => (arg1 & !arg2, 1),
				#[allow(clippy::unreadable_literal)]
				BinaryOp::Grev => {
					let value = arg1.cast_unsigned();
					let value = (value << (arg2 & 0b100000)) | (value >> (arg2 & 0b100000));
					let value = ((value & 0x0000ffff_0000ffff) << (arg2 & 0b010000)) | ((value & 0xffff0000_ffff0000) >> (arg2 & 0b010000));
					let value = ((value & 0x00ff00ff_00ff00ff) << (arg2 & 0b001000)) | ((value & 0xff00ff00_ff00ff00) >> (arg2 & 0b001000));
					let value = ((value & 0x0f0f0f0f_0f0f0f0f) << (arg2 & 0b000100)) | ((value & 0xf0f0f0f0_f0f0f0f0) >> (arg2 & 0b000100));
					let value = ((value & 0x33333333_33333333) << (arg2 & 0b000010)) | ((value & 0xcccccccc_cccccccc) >> (arg2 & 0b000010));
					let value = ((value & 0x55555555_55555555) << (arg2 & 0b000001)) | ((value & 0xaaaaaaaa_aaaaaaaa) >> (arg2 & 0b000001));
					(value.cast_signed(), 1)
				},
				BinaryOp::Or => (arg1 | arg2, 1),
				BinaryOp::Orn => (arg1 | !arg2, 1),
				BinaryOp::Rol => (arg1.rotate_left((arg2 & 0x3f).try_into().unwrap()), 1),
				BinaryOp::Rolw => (arg1w.rotate_left((arg2w & 0x1f).try_into().unwrap()).into(), 1),
				BinaryOp::Ror => (arg1.rotate_right((arg2 & 0x3f).try_into().unwrap()), 1),
				BinaryOp::Rorw => (arg1w.rotate_right((arg2w & 0x1f).try_into().unwrap()).into(), 1),
				BinaryOp::Sh1add => ((arg1 << 1).wrapping_add(arg2), 1),
				BinaryOp::Sh1addUw => ((i64::from(arg1uw) << 1).wrapping_add(arg2), 1),
				BinaryOp::Sh2add => ((arg1 << 2).wrapping_add(arg2), 1),
				BinaryOp::Sh2addUw => ((i64::from(arg1uw) << 2).wrapping_add(arg2), 1),
				BinaryOp::Sh3add => ((arg1 << 3).wrapping_add(arg2), 1),
				BinaryOp::Sh3addUw => ((i64::from(arg1uw) << 3).wrapping_add(arg2), 1),
				BinaryOp::Sll => (arg1 << (arg2 & 0x3f), 1),
				BinaryOp::SllUw => (i64::from(arg1uw) << (arg2 & 0x3f), 1),
				BinaryOp::Sllw => ((arg1w << (arg2w & 0x1f)).into(), 1),
				BinaryOp::Slt => ((arg1 < arg2).into(), 1),
				BinaryOp::Sltu => ((arg1.cast_unsigned() < arg2.cast_unsigned()).into(), 1),
				BinaryOp::Sra => (arg1 >> (arg2 & 0x3f), 1),
				BinaryOp::Sraw => ((arg1w >> (arg2w & 0x1f)).into(), 1),
				BinaryOp::Srl => ((arg1.cast_unsigned() >> (arg2 & 0x3f)).cast_signed(), 1),
				BinaryOp::Srlw => ((arg1uw >> (arg2w & 0x1f)).cast_signed().into(), 1),
				BinaryOp::Sub => (arg1.wrapping_sub(arg2), 1),
				BinaryOp::Subw => (arg1w.wrapping_sub(arg2w).into(), 1),
				BinaryOp::Xnor => (arg1 ^ !arg2, 1),
				BinaryOp::Xor => (arg1 ^ arg2, 1),
			};
			rd.2 = Some(value);
			cycles
		},

		Ucode::Csel {
			rd,
			rcond: RegisterValue::Value(0),
			rs_eqz: RegisterValue::Value(value),
			rs_nez: RegisterValue::Value(_),
		} => {
			rd.2 = Some(*value);
			1
		},

		Ucode::Csel {
			rd,
			rcond: RegisterValue::Value(rcond),
			rs_eqz: RegisterValue::Value(_),
			rs_nez: RegisterValue::Value(value),
		} if *rcond != 0 => {
			rd.2 = Some(*value);
			1
		},

		Ucode::Ebreak => panic!("EBREAK"),

		Ucode::Fence => 1,

		Ucode::Jump { pc: RegisterValue::Value(_), predicted_next_pc: _ } => 1,

		Ucode::Mul {
			op,
			rd,
			rs1: RegisterValue::Value(arg1),
			rs2: RegisterValue::Value(arg2),
			state,
		} => {
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

			let mut cycles = 0;
			let value = loop {
				match multiplier::round(arg1_is_signed, arg1, *i, *p) {
					State::Pending { i: i_, p: p_ } => {
						cycles += 1;
						*i = i_;
						*p = p_;
					},

					State::Mulw { i: i_, p: p_, mulw } => {
						cycles += 1;
						if matches!(*op, MulOp::Mulw) {
							break mulw.into();
						}

						*i = i_;
						*p = p_;
					},

					State::Mul { mul, mulh } => {
						cycles += 1;
						break if matches!(*op, MulOp::Mul) {
							mul
						}
						else {
							mulh
						};
					},
				}
			};
			rd.2 = Some(value);
			cycles
		},

		Ucode::Mv { rd: _, value: RegisterValue::Value(_) } => 1,

		Ucode::MvCsr { csr: _, value: RegisterValue::Value(_) } => 1,

		Ucode::Load { op, rd, addr: RegisterValue::Value(addr) } => {
			let result = op.exec(memory, *addr);
			rd.2 = Some(result);
			1
		},

		Ucode::Store {
			op,
			addr: RegisterValue::Value(addr),
			value: RegisterValue::Value(value),
		} => {
			op.exec(memory, *addr, *value);
			1
		},

		Ucode::UnaryOp {
			op,
			rd,
			rs: RegisterValue::Value(arg),
		} => {
			let arg = *arg;

			#[allow(clippy::cast_possible_truncation)]
			let argw = arg as i32;

			let (value, cycles) = match *op {
				UnaryOp::Cpop => (arg.count_ones().into(), 2),
				UnaryOp::Cpopw => (argw.count_ones().into(), 2),
				UnaryOp::OrcB => (i64::from_ne_bytes(arg.to_ne_bytes().map(|b| if b == 0 { 0x00 } else { 0xff })), 1),
				#[allow(clippy::cast_possible_truncation)]
				UnaryOp::SextB => ((arg as i8).into(), 1),
				#[allow(clippy::cast_possible_truncation)]
				UnaryOp::SextH => ((arg as i16).into(), 1),
				UnaryOp::SextW => (argw.into(), 1),
				#[allow(clippy::cast_possible_truncation)]
				UnaryOp::ZextB => ((arg.cast_unsigned() as u8).into(), 1),
				#[allow(clippy::cast_possible_truncation)]
				UnaryOp::ZextH => ((arg.cast_unsigned() as u16).into(), 1),
				#[allow(clippy::cast_possible_truncation)]
				UnaryOp::ZextW => ((arg.cast_unsigned() as u32).into(), 1),
			};
			rd.2 = Some(value);
			cycles
		},

		_ => unreachable!("{inst:?}")
	}
}
