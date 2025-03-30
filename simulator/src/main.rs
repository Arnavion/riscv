mod csrs;
use csrs::Csrs;

mod in_order;

mod instruction;
use instruction::{
	Instruction,
	OpOp, Op32Op,
	OpImmOp, OpImm32Op,
	MemoryBase, MemoryOffset,
};

mod memory;
use memory::{Memory, LoadOp};

mod x_regs;
use x_regs::{XReg, XRegs};

fn main() {
	let log_level = match std::env::var_os("SIMULATOR_LOG") {
		Some(var) if var.to_str() == Some("debug") => LogLevel::Debug,
		Some(var) if var.to_str() == Some("trace") => LogLevel::Trace,
		_ => LogLevel::Info,
	};

	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let (program_path, in_file_path) = parse_args(args, &argv0);

	let mut memory = Memory::new(program_path, in_file_path);

	let mut x_regs: XRegs = Default::default();

	let mut csrs: Csrs = Default::default();

	let mut statistics: Statistics = Default::default();

	let pc = 0x8000_0000_0000_0000_u64.cast_signed();

	in_order::run(
		&mut memory,
		&mut x_regs,
		&mut csrs,
		&mut statistics,
		pc,
		log_level,
	);

	memory.dump_console();

	println!("{statistics}");

	println!("{x_regs}");

	println!("{csrs}");
}

fn load_inst(memory: &Memory, pc: i64, statistics: &mut Statistics) -> Result<(Instruction, i64, i64), u32> {
	let inst1 = LoadOp::HalfWordUnsigned.exec(memory, pc).cast_unsigned();
	let inst2 = LoadOp::HalfWordUnsigned.exec(memory, pc + 2).cast_unsigned();
	let inst3 = LoadOp::HalfWordUnsigned.exec(memory, pc + 4).cast_unsigned();
	let inst4 = LoadOp::HalfWordUnsigned.exec(memory, pc + 6).cast_unsigned();
	let inst = inst1 | (inst2 << 16) | (inst3 << 32) | (inst4 << 48);

	#[allow(clippy::cast_possible_truncation)]
	let Ok((inst_a, inst_a_len)) = Instruction::decode(inst as u32) else {
		return Err(inst as u32);
	};

	let inst = inst >> (inst_a_len * 8);
	#[allow(clippy::cast_possible_truncation)]
	let result =
		if let Ok((inst_b, inst_b_len)) = Instruction::decode(inst as u32) {
			macro_op_fuse(inst_a, inst_a_len, inst_b, inst_b_len, &mut statistics.fusions)
		}
		else {
			(inst_a, inst_a_len, 1)
		};
	Ok(result)
}

fn macro_op_fuse(
	inst_a: Instruction, inst_a_len: i64,
	inst_b: Instruction, inst_b_len: i64,
	fusions: &mut std::collections::BTreeMap<&'static str, usize>,
) -> (Instruction, i64, i64) {
	let (inst, entry) = match (inst_a, inst_b) {
		(
			Instruction::Auipc { rd: rd_a, imm: imm_a },
			Instruction::OpImm { op: OpImmOp::Addi, rd: rd_b, rs1: rs1_b, imm: imm_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Auipc { rd: rd_a, imm: imm_a.wrapping_add(imm_b) },
			"auipc; addi -> auipc",
		),

		(
			Instruction::Lui { rd: rd_a, imm: imm_a },
			Instruction::Op { op: OpOp::Add, rd: rd_b, rs1: rs1_b, rs2: rs2_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b &&
			rs1_b != rs2_b
		=> (
			Instruction::OpImm { op: OpImmOp::Addi, rd: rd_a, rs1: rs2_b, imm: imm_a },
			"lui; add -> addi",
		),

		(
			Instruction::Lui { rd: rd_a, imm: imm_a },
			Instruction::Op32 { op: Op32Op::Addw, rd: rd_b, rs1: rs1_b, rs2: rs2_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b &&
			rs1_b != rs2_b
		=> (
			Instruction::OpImm32 { op: OpImm32Op::Addiw, rd: rd_a, rs1: rs2_b, imm: imm_a },
			"lui; addw -> addiw",
		),

		(
			Instruction::Lui { rd: rd_a, imm: imm_a },
			Instruction::OpImm { op: OpImmOp::Addi, rd: rd_b, rs1: rs1_b, imm: imm_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Lui { rd: rd_a, imm: imm_a.wrapping_add(imm_b) },
			"lui; addi -> lui",
		),

		(
			Instruction::Lui { rd: rd_a, imm: imm_a },
			Instruction::OpImm32 { op: OpImm32Op::Addiw, rd: rd_b, rs1: rs1_b, imm: imm_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Lui { rd: rd_a, imm: ((imm_a << 31).wrapping_add(imm_b << 31)) >> 31 },
			"lui; addiw -> lui",
		),

		(
			Instruction::Auipc { rd: rd_a, imm: imm_a },
			Instruction::Jalr { rd: rd_b, rs1: rs1_b, imm: imm_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Jal { rd: rd_a, imm: imm_a.wrapping_add(imm_b) },
			"auipc; jalr -> jal",
		),

		(
			Instruction::Auipc { rd: rd_a, imm: imm_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(offset_b) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::Pc, offset: MemoryOffset::Imm(imm_a.wrapping_add(offset_b)) },
			"auipc; load -> load.pc",
		),

		(
			Instruction::Lui { rd: rd_a, imm: imm_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(offset_b) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::XReg(XReg::X0), offset: MemoryOffset::Imm(imm_a.wrapping_add(offset_b)) },
			"lui; load -> load",
		),

		(
			Instruction::Op { op: OpOp::Add, rd: rd_a, rs1: rs1_a, rs2: rs2_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(0) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::XReg(rs1_a), offset: MemoryOffset::XReg(rs2_a) },
			"add; load -> load.add",
		),

		(
			Instruction::Op { op: OpOp::Sh1add, rd: rd_a, rs1: rs1_a, rs2: rs2_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(0) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::XRegSh1(rs1_a), offset: MemoryOffset::XReg(rs2_a) },
			"sh1add; load -> load.sh1add",
		),

		(
			Instruction::Op { op: OpOp::Sh2add, rd: rd_a, rs1: rs1_a, rs2: rs2_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(0) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::XRegSh2(rs1_a), offset: MemoryOffset::XReg(rs2_a) },
			"sh2add; load -> load.sh2add",
		),

		(
			Instruction::Op { op: OpOp::Sh3add, rd: rd_a, rs1: rs1_a, rs2: rs2_a },
			Instruction::Load { op: op_b, rd: rd_b, base: MemoryBase::XReg(rs1_b), offset: MemoryOffset::Imm(0) },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b
		=> (
			Instruction::Load { op: op_b, rd: rd_a, base: MemoryBase::XRegSh3(rs1_a), offset: MemoryOffset::XReg(rs2_a) },
			"sh3add; load -> load.sh3add",
		),

		(
			Instruction::Op { op: OpOp::Sub, rd: rd_a, rs1: XReg::X0, rs2: rs2_a },
			Instruction::Op { op: OpOp::Max, rd: rd_b, rs1: rs1_b, rs2: rs2_b },
		) if
			rd_a == rd_b &&
			rd_a == rs1_b &&
			rs2_a == rs2_b
		=> (
			Instruction::Abs { rd: rd_a, rs: rs2_a },
			"sub; max -> abs",
		),

		(_, _) => return (inst_a, inst_a_len, 1),
	};
	*fusions.entry(entry).or_default() += 1;
	(inst, inst_a_len + inst_b_len, 2)
}

#[derive(Clone, Copy, Eq, Ord, PartialEq, PartialOrd)]
enum LogLevel {
	Info,
	Debug,
	Trace,
}

#[derive(Default)]
struct Statistics {
	fusions: std::collections::BTreeMap<&'static str, usize>,
}

impl std::fmt::Display for Statistics {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		writeln!(f, "fusions: {:#?}", self.fusions)?;
		Ok(())
	}
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> (std::path::PathBuf, std::path::PathBuf) {
	let mut program_path = None;
	let mut in_file_path = None;

	for opt in &mut args {
		match opt.to_str() {
			Some("--help") => {
				write_usage(std::io::stdout(), argv0);
				std::process::exit(0);
			},

			Some("--") => {
				program_path = args.next();
				in_file_path = args.next();
				break;
			},

			_ if program_path.is_none() => program_path = Some(opt),

			_ if in_file_path.is_none() => in_file_path = Some(opt),

			_ => write_usage_and_crash(argv0),
		}
	}

	let None = args.next() else { write_usage_and_crash(argv0); };

	let Some(program_path) = program_path else { write_usage_and_crash(argv0); };
	let Some(in_file_path) = in_file_path else { write_usage_and_crash(argv0); };
	(program_path.into(), in_file_path.into())
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} [ -- ] <program.bin> <in_file.S>", argv0.to_string_lossy());
}
