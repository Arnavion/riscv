#![no_std]

mod instruction;
pub use instruction::{FenceSet, Instruction};

mod pseudo_instruction;

mod register;
pub use register::Register;

pub fn parse_program(program: &str) -> impl Iterator<Item = Result<Instruction, ParseError<'_>>> + '_ {
	program
		.lines()
		.flat_map(|line| match Instruction::parse(line) {
			Ok(Some(instruction)) => SmallIterator::One(Ok(instruction)),
			Ok(None) => SmallIterator::Empty,
			Err(_) => match pseudo_instruction::parse(line) {
				Ok(instructions) => instructions.map(Ok),
				Err(err) => SmallIterator::One(Err(err)),
			},
		})
}

enum SmallIterator<T> {
	Empty,
	One(T),
	Two(T, T),
}

impl<T> SmallIterator<T> {
	fn map<U>(self, mut f: impl FnMut(T) -> U) -> SmallIterator<U> {
		match self {
			Self::Empty => SmallIterator::Empty,
			Self::One(i) => SmallIterator::One(f(i)),
			Self::Two(i, j) => SmallIterator::Two(f(i), f(j)),
		}
	}
}

impl<T> Iterator for SmallIterator<T> {
	type Item = T;

	fn next(&mut self) -> Option<Self::Item> {
		match core::mem::replace(self, Self::Empty) {
			Self::Empty => None,
			Self::One(i) => Some(i),
			Self::Two(i, j) => {
				*self = Self::One(j);
				Some(i)
			},
		}
	}
}

#[derive(Debug)]
pub enum ParseError<'a> {
	InvalidUtf8 { token: &'a [u8] },
	MalformedFenceSet { token: &'a [u8] },
	MalformedImmediate { token: &'a [u8] },
	MalformedInstruction { line: &'a str },
	MalformedRegister { token: &'a str },
	TrailingGarbage { line: &'a str },
	TruncatedInstruction { line: &'a str },
	UnknownInstruction { line: &'a str },
}

impl core::error::Error for ParseError<'_> {}

impl core::fmt::Display for ParseError<'_> {
	fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
		match self {
			Self::InvalidUtf8 { token } => write!(f, "invalid UTF-8 {token:?}"),
			Self::MalformedFenceSet { token } => write!(f, "malformed fence set {token:?}"),
			Self::MalformedImmediate { token } => write!(f, "malformed immediate {token:?}"),
			Self::MalformedInstruction { line } => write!(f, "malformed instruction {line:?}"),
			Self::MalformedRegister { token } => write!(f, "malformed register {token:?}"),
			Self::TrailingGarbage { line } => write!(f, "trailing garbage {line:?}"),
			Self::TruncatedInstruction { line } => write!(f, "truncated instruction {line:?}"),
			Self::UnknownInstruction { line } => write!(f, "unknown instruction {line:?}"),
		}
	}
}

#[derive(Debug)]
pub enum EncodeError {
	ImmediateOverflow,
}

impl core::error::Error for EncodeError {}

impl core::fmt::Display for EncodeError {
	fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
		match self {
			Self::ImmediateOverflow => f.write_str("imm overflow"),
		}
	}
}

#[cfg(test)]
mod tests {
	extern crate std;
	use std::prelude::v1::*;

	#[allow(clippy::unreadable_literal)]
	#[test]
	fn full() {
		static TESTS: &[(&str, &[u32])] = &[
			// Registers and aliases
			("add x0, x1, x2", &[0x00208033]),
			("add x3, x4, x5", &[0x005201b3]),
			("add x6, x7, x8", &[0x00838333]),
			("add x9, x10, x11", &[0x00b504b3]),
			("add x12, x13, x14", &[0x00e68633]),
			("add x15, x16, x17", &[0x011807b3]),
			("add x18, x19, x20", &[0x01498933]),
			("add x21, x22, x23", &[0x017b0ab3]),
			("add x24, x25, x26", &[0x01ac8c33]),
			("add x27, x28, x29", &[0x01de0db3]),
			("add x30, x31, x8", &[0x008f8f33]),

			("add zero, ra, sp", &[0x00208033]),
			("add gp, tp, t0", &[0x005201b3]),
			("add t1, t2, s0", &[0x00838333]),
			("add s1, a0, a1", &[0x00b504b3]),
			("add a2, a3, a4", &[0x00e68633]),
			("add a5, a6, a7", &[0x011807b3]),
			("add s2, s3, s4", &[0x01498933]),
			("add s5, s6, s7", &[0x017b0ab3]),
			("add s8, s9, s10", &[0x01ac8c33]),
			("add s11, t3, t4", &[0x01de0db3]),
			("add t5, t6, fp", &[0x008f8f33]),


			// Instructions

			("add a0, a1, a2", &[0x00c58533]),

			("addi a0, a1, -11", &[0xff558513]),
			("addi a0, a1, 11", &[0x00b58513]),

			("and a0, a1, a2", &[0x00c5f533]),

			("andi a0, a1, -11", &[0xff55f513]),
			("andi a0, a1, 11", &[0x00b5f513]),

			("auipc a0, -11", &[0xffff5517]),
			("auipc a0, 11", &[0x0000b517]),

			("beq a0, a1, -4", &[0xfeb50ee3]),
			("beq a0, a1, 44", &[0x02b50663]),

			("beqz a0, -4", &[0xfe050ee3]),
			("beqz a0, 28", &[0x00050e63]),

			("bge a0, a1, -12", &[0xfeb55ae3]),
			("bge a0, a1, 36", &[0x02b55263]),

			("bgeu a0, a1, -20", &[0xfeb576e3]),
			("bgeu a0, a1, 28", &[0x00b57e63]),

			("bgez a0, -12", &[0xfe055ae3]),
			("bgez a0, 20", &[0x00055a63]),

			("bgt a0, a1, -4", &[0xfea5cee3]),
			("bgt a0, a1, 28", &[0x00a5ce63]),

			("bgtu a0, a1, -12", &[0xfea5eae3]),
			("bgtu a0, a1, 20", &[0x00a5ea63]),

			("bgtz a0, -4", &[0xfea04ee3]),
			("bgtz a0, 12", &[0x00a04663]),

			("ble a0, a1, -20", &[0xfea5d6e3]),
			("ble a0, a1, 12", &[0x00a5d663]),

			("bleu a0, a1, -28", &[0xfea5f2e3]),
			("bleu a0, a1, 4", &[0x00a5f263]),

			("blez a0, -12", &[0xfea05ae3]),
			("blez a0, 4", &[0x00a05263]),

			("blt a0, a1, -28", &[0xfeb542e3]),
			("blt a0, a1, 20", &[0x00b54a63]),

			("bltu a0, a1, -36", &[0xfcb56ee3]),
			("bltu a0, a1, 12", &[0x00b56663]),

			("bltz a0, -20", &[0xfe0546e3]),
			("bltz a0, 12", &[0x00054663]),

			("bne a0, a1, -44", &[0xfcb51ae3]),
			("bne a0, a1, 4", &[0x00b51263]),

			("bnez a0, -28", &[0xfe0512e3]),
			("bnez a0, 4", &[0x00051263]),

			("call -4", &[0x00000097, 0xffc080e7]),
			("call 24", &[0x00000097, 0x018080e7]),
			("call a0, -20", &[0x00000517, 0xfec50567]),
			("call a0, 8", &[0x00000517, 0x00850567]),

			("ebreak", &[0x00100073]),

			("ecall", &[0x00000073]),

			("fence", &[0x0330000f]),
			("fence 0, 0", &[0x0000000f]),
			("fence iorw, iorw", &[0x0ff0000f]),

			("fence.tso", &[0x8330000f]),

			("j -4", &[0xffdff06f]),
			("j 4", &[0x0040006f]),

			("jal -4", &[0xffdff0ef]),
			("jal 12", &[0x00c000ef]),
			("jal a0, -12", &[0xff5ff56f]),
			("jal a0, 4", &[0x0040056f]),

			("jalr (a0)", &[0x000500e7]),
			("jalr -11(a0)", &[0xff5500e7]),
			("jalr 11(a0)", &[0x00b500e7]),
			("jalr a0, a1", &[0x00058567]),
			("jalr a0, (a1)", &[0x00058567]),
			("jalr a0, -11(a1)", &[0xff558567]),
			("jalr a0, 11(a1)", &[0x00b58567]),
			("jalr a0", &[0x000500e7]),

			("jump -4, a0", &[0x00000517, 0xffc50067]),
			("jump 8, a0", &[0x00000517, 0x00850067]),

			// Positive immediate with [11:0] significant bits -> addi
			("li a0, 0x7ff", &[0x7ff00513]),
			// Negative immediate with [11:0] significant bits -> addi
			("li a0, -1", &[0xfff00513]),
			// Positive immediate with [31:12] significant bits -> lui
			("li a0, 0x7ffff000", &[0x7ffff537]),
			// Negative immediate with [31:12] significant bits -> lui
			("li a0, -4096", &[0xfffff537]),
			// Positive immediate with [31:0] significant bits -> lui; addi
			("li a0, 0x7fffffff", &[0x80000537, 0xfff50513]),
			// Negative immediate with [31:0] significant bits -> lui; addi
			("li a0, -2147479553", &[0x80001537, 0xfff50513]),

			("lla a0, -4", &[0x00000517, 0xffc50513]),
			("lla a0, 8", &[0x00000517, 0x00850513]),

			("lui a0, -11", &[0xffff5537]),
			("lui a0, 11", &[0x0000b537]),

			("lb a0, -4", &[0x00000517, 0xffc50503]),
			("lb a0, 104", &[0x00000517, 0x06850503]),
			("lb a0, -11(a1)", &[0xff558503]),
			("lb a0, 11(a1)", &[0x00b58503]),

			("lbu a0, -20", &[0x00000517, 0xfec54503]),
			("lbu a0, 88", &[0x00000517, 0x05854503]),
			("lbu a0, -11(a1)", &[0xff55c503]),
			("lbu a0, 11(a1)", &[0x00b5c503]),

			("lh a0, -52", &[0x00000517, 0xfcc51503]),
			("lh a0, 56", &[0x00000517, 0x03851503]),
			("lh a0, -11(a1)", &[0xff559503]),
			("lh a0, 11(a1)", &[0x00b59503]),

			("lhu a0, -68", &[0x00000517, 0xfbc55503]),
			("lhu a0, 40", &[0x00000517, 0x02855503]),
			("lhu a0, -11(a1)", &[0xff55d503]),
			("lhu a0, 11(a1)", &[0x00b5d503]),

			("lw a0, -84", &[0x00000517, 0xfac52503]),
			("lw a0, 24", &[0x00000517, 0x01852503]),
			("lw a0, -11(a1)", &[0xff55a503]),
			("lw a0, 11(a1)", &[0x00b5a503]),

			("mv a0, a1", &[0x00058513]),

			("neg a0, a1", &[0x40b00533]),

			("nop", &[0x00000013]),

			("not a0, a1", &[0xfff5c513]),

			("ntl.all", &[0x00500033]),
			("ntl.pall", &[0x00300033]),
			("ntl.p1", &[0x00200033]),
			("ntl.s1", &[0x00400033]),

			("or a0, a1, a2", &[0x00c5e533]),

			("ori a0, a1, -11", &[0xff55e513]),
			("ori a0, a1, 11", &[0x00b5e513]),

			("pause", &[0x0100000f]),

			("ret", &[0x00008067]),

			("sb a0, -11(a1)", &[0xfea58aa3]),
			("sb a0, 11(a1)", &[0x00a585a3]),

			("seqz a0, a1", &[0x0015b513]),

			("sext.b a0, a1", &[0x01859513, 0x41855513]),

			("sext.h a0, a1", &[0x01059513, 0x41055513]),

			("sgtz a0, a1", &[0x00b02533]),

			("sh a0, -11(a1)", &[0xfea59aa3]),
			("sh a0, 11(a1)", &[0x00a595a3]),

			("sll a0, a1, a2", &[0x00c59533]),

			("slli a0, a1, 11", &[0x00b59513]),
			("slli a0, a1, 31", &[0x01f59513]),

			("slt a0, a1, a2", &[0x00c5a533]),

			("slti a0, a1, -11", &[0xff55a513]),
			("slti a0, a1, 11", &[0x00b5a513]),

			("sltiu a0, a1, -11", &[0xff55b513]),
			("sltiu a0, a1, 11", &[0x00b5b513]),

			("sltu a0, a1, a2", &[0x00c5b533]),

			("sltz a0, a1", &[0x0005a533]),

			("snez a0, a1", &[0x00b03533]),

			("sra a0, a1, a2", &[0x40c5d533]),

			("srai a0, a1, 11", &[0x40b5d513]),
			("srai a0, a1, 31", &[0x41f5d513]),

			("srl a0, a1, a2", &[0x00c5d533]),

			("srli a0, a1, 11", &[0x00b5d513]),
			("srli a0, a1, 31", &[0x01f5d513]),

			("sub a0, a1, a2", &[0x40c58533]),

			("sw a0, -11(a1)", &[0xfea5aaa3]),
			("sw a0, 11(a1)", &[0x00a5a5a3]),

			("tail -4", &[0x00000317, 0xffc30067]),
			("tail 8", &[0x00000317, 0x00830067]),

			("xor a0, a1, a2", &[0x00c5c533]),

			("xori a0, a1, -11", &[0xff55c513]),
			("xori a0, a1, 11", &[0x00b5c513]),

			("zext.b a0, a1", &[0x0ff5f513]),

			("zext.h a0, a1", &[0x01059513, 0x01055513]),
		];
		for &(input, expected) in TESTS {
			std::eprintln!("{input}");

			let actual =
				super::parse_program(input)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	// Source: https://sourceware.org/git/?p=binutils-gdb.git
	//
	// /gas/testsuite/gas/riscv/
	#[allow(clippy::unreadable_literal)]
	#[test]
	fn gas() {
		static TESTS: &[(&str, &[u32])] = &[
			// auipc-x0.s
			("
				auipc x0, 0
				lw x0, 0(x0)
			", &[
				0x00000017,
				0x00002003,
			]),

			// bge.s
			("
				bge a1, a2, 0
				ble a1, a2, -4
				bgeu a1, a2, -8
				bleu a1, a2, -12
			", &[
				0x00c5d063,
				0xfeb65ee3,
				0xfec5fce3,
				0xfeb67ae3,
			]),

			// dis-addr-overflow.s
			("
				## Use hi_addr
				# Load
				lui t0, 0xfffff
				lw s2, -4(t0)
				# Store
				lui t1, 0xffffe
				sw s3, -8(t1)
				# JALR (implicit destination, no offset)
				lui t2, 0xffffd
				jalr t2
				# JALR (implicit destination, with offset)
				lui t3, 0xffffc
				jalr -12(t3)
				# JALR (explicit destination, no offset)
				lui t4, 0xffffb
				jalr s4, t4
				# ADDI (not compressed)
				lui t5, 0xffffa
				addi s5, t5, -16

				# Use addresses relative to gp
				lw t0, 0x400(gp)
				lw t1, -0x400(gp)
				# Use addresses relative to zero
				lw t2, 0x100(zero)
				lw t3, -0x800(zero)
				jalr t4, 0x104(zero)
				jalr t5, -0x7fc(zero)
			", &[
				0xfffff2b7,
				0xffc2a903,
				0xffffe337,
				0xff332c23,
				0xffffd3b7,
				0x000380e7,
				0xffffce37,
				0xff4e00e7,
				0xffffbeb7,
				0x000e8a67,
				0xffffaf37,
				0xff0f0a93,
				0x4001a283,
				0xc001a303,
				0x10002383,
				0x80002e03,
				0x10400ee7,
				0x80400f67,
			]),

			// dis-addr-topaddr.s
			("
				lb t0, -1(zero)
			", &[
				0xfff00283,
			]),

			// dis-addr-topaddr-gp.s
			("
				# Use addresses relative to gp
				# (gp is the highest address)
				lw t0, +5(gp)
				lw t1, -3(gp)
			", &[
				0x0051a283,
				0xffd1a303,
			]),

			// fence-tso.s
			("
				fence.tso
			", &[
				0x8330000f,
			]),

			// fixup-local.s
			("
				lla a0, 24
				lh a0, 16
				auipc a0, 0
				sh a0, 8, a0
				lla a0, 0
				lh a0, 0
				auipc a0, 0
				sh a0, 0, a0
				lla a0, 0
				lh a0, 0
				auipc a0, 0
				sh a0, 0, a0
				auipc a0, 0
				lw a0, 16(a0)
				auipc a0, 0
				sw a0, 16(a0)
				ret
			", &[
				0x00000517,
				0x01850513,
				0x00000517,
				0x01051503,
				0x00000517,
				0x00a51423,
				0x00000517,
				0x00050513,
				0x00000517,
				0x00051503,
				0x00000517,
				0x00a51023,
				0x00000517,
				0x00050513,
				0x00000517,
				0x00051503,
				0x00000517,
				0x00a51023,
				0x00000517,
				0x01052503,
				0x00000517,
				0x00a52823,
				0x00008067,
			]),

			// t_insns.s
			("
				nop
			", &[
				0x00000013,
			]),

			// tlsdesc.s
			("
				auipc a0, 0
				lw t0, 0(a0)
				addi a0, a0, 0
				jalr t0, t0, 0

				auipc a0, 0
				lw t0, 0(a0)
				addi a0, a0, 0
				jalr t0, t0, 0

				ret
			", &[
				0x00000517,
				0x00052283,
				0x00050513,
				0x000282e7,
				0x00000517,
				0x00052283,
				0x00050513,
				0x000282e7,
				0x00008067,
			]),

			// zihintntl.s
			("
				ntl.p1
				sb s11, 0(t0)
				ntl.pall
				sb s11, 2(t0)
				ntl.s1
				sb s11, 4(t0)
				ntl.all
				sb s11, 6(t0)
			", &[
				0x00200033,
				0x01b28023,
				0x00300033,
				0x01b28123,
				0x00400033,
				0x01b28223,
				0x00500033,
				0x01b28323,
			]),

			// zihintntl-base.s
			("
				add x0, x0, x2
				sb s11, 0(t0)
				add x0, x0, x3
				sb s11, 2(t0)
				add x0, x0, x4
				sb s11, 4(t0)
				add x0, x0, x5
				sb s11, 6(t0)
			", &[
				0x00200033,
				0x01b28023,
				0x00300033,
				0x01b28123,
				0x00400033,
				0x01b28223,
				0x00500033,
				0x01b28323,
			]),
		];
		for &(input, expected) in TESTS {
			std::eprintln!("{input}");

			let actual =
				super::parse_program(input)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}
}
