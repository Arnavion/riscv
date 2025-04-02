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
use memory::Memory;

mod out_of_order;

mod x_regs;
use x_regs::{XReg, XRegs};

mod ucode;

fn main() {
	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let (out_of_order, program_path, in_file_path) = parse_args(args, &argv0);

	let mut memory = Memory::new(program_path, in_file_path);

	let mut x_regs: XRegs = Default::default();

	let mut csrs: Csrs = Default::default();

	let mut statistics: Statistics = Default::default();

	let pc = 0x8000_0000_0000_0000_u64.cast_signed();

	if out_of_order {
		out_of_order::run(
			&mut memory,
			&mut x_regs,
			&mut csrs,
			&mut statistics,
			pc,
		);
	}
	else {
		in_order::run(
			&mut memory,
			&mut x_regs,
			&mut csrs,
			&mut statistics,
			pc,
		);
	}

	memory.dump_console();

	println!("{statistics}");
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

#[derive(Default)]
struct Statistics {
	fusions: std::collections::BTreeMap<&'static str, usize>,
	num_ticks_where_instructions_retired: usize,
	num_ticks_where_instructions_not_retired: usize,
	branch_predictions: usize,
	branch_mispredictions: usize,
	jal_predictions: usize,
	jal_mispredictions: usize,
}

impl std::fmt::Display for Statistics {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		writeln!(f, "fusions: {:#?}", self.fusions)?;
		writeln!(f, "num ticks where instructions retired: {}", self.num_ticks_where_instructions_retired)?;
		writeln!(f, "num ticks where instructions not retired: {}", self.num_ticks_where_instructions_not_retired)?;
		writeln!(f, "B* predictions: {}", self.branch_predictions)?;
		writeln!(f, "B* mispredictions: {}", self.branch_mispredictions)?;
		writeln!(f, "JAL* predictions: {}", self.jal_predictions)?;
		writeln!(f, "JAL* mispredictions: {}", self.jal_mispredictions)?;
		Ok(())
	}
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct Tag(usize);

impl Tag {
	fn allocate(&mut self) -> Self {
		let result = *self;
		self.0 += 1;
		result
	}

	fn allocate_if(&mut self, f: impl FnOnce(Self) -> bool) -> Option<Self> {
		let result = *self;
		if f(result) {
			self.0 += 1;
			Some(result)
		}
		else {
			None
		}
	}
}

impl std::fmt::Display for Tag {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		self.0.fmt(f)
	}
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum RegisterValue {
	Value(i64),
	Tag(Tag),
}

impl RegisterValue {
	fn update(&mut self, tag: Tag, value: i64) {
		if matches!(self, Self::Tag(tag_) if *tag_ == tag) {
			*self = Self::Value(value);
		}
	}

	fn in_order(self) -> i64 {
		match self {
			Self::Value(value) => value,
			Self::Tag(_) => unreachable!(),
		}
	}
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> (bool, std::path::PathBuf, std::path::PathBuf) {
	let mut out_of_order = false;
	let mut program_path = None;
	let mut in_file_path = None;

	for opt in &mut args {
		match opt.to_str() {
			Some("--help") => {
				write_usage(std::io::stdout(), argv0);
				std::process::exit(0);
			},

			Some("--ooo") => out_of_order = true,

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
	(out_of_order, program_path.into(), in_file_path.into())
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} [--ooo] [ -- ] <program.bin> <in_file.S>", argv0.to_string_lossy());
}
