#![no_std]

mod instruction;
pub use instruction::{FenceSet, Instruction};

mod pseudo_instruction;

mod register;
pub use register::{Csr, Register};

mod supported_extensions;
pub use supported_extensions::SupportedExtensions;

pub fn parse_program<'a>(
	program: impl IntoIterator<Item = &'a [u8]>,
	supported_extensions: SupportedExtensions,
) -> impl Iterator<Item = Result<Instruction, ParseError<'a>>> {
	program
		.into_iter()
		.flat_map(move |line| match Instruction::parse(line) {
			Ok(Some(instruction)) => SmallIterator::One(Ok(instruction)),
			Ok(None) => SmallIterator::Empty,
			Err(_) => match pseudo_instruction::parse(line, supported_extensions) {
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
	ImmediateOverflow { line: &'a [u8] },
	InvalidUtf8 { token: &'a [u8] },
	MalformedFenceSet { token: &'a [u8] },
	MalformedImmediate { token: &'a [u8] },
	MalformedInstruction { line: &'a [u8] },
	MalformedIntegerCsr { token: &'a [u8] },
	MalformedRegister { token: &'a str },
	SpInstructionRegIsNotX2 { pos: &'static str, line: &'a [u8] },
	TrailingGarbage { line: &'a [u8] },
	TruncatedInstruction { line: &'a [u8] },
	UnknownInstruction { line: &'a [u8] },
}

impl core::error::Error for ParseError<'_> {}

impl core::fmt::Display for ParseError<'_> {
	fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
		match self {
			Self::ImmediateOverflow { line } => write!(f, r#"immediate overflow "{}""#, line.escape_ascii()),
			Self::InvalidUtf8 { token } => write!(f, r#"invalid UTF-8 "{}""#, token.escape_ascii()),
			Self::MalformedFenceSet { token } => write!(f, r#"malformed fence set "{}""#, token.escape_ascii()),
			Self::MalformedImmediate { token } => write!(f, r#"malformed immediate "{}""#, token.escape_ascii()),
			Self::MalformedInstruction { line } => write!(f, r#"malformed instruction "{}""#, line.escape_ascii()),
			Self::MalformedIntegerCsr { token } => write!(f, r#"malformed integer CSR "{}""#, token.escape_ascii()),
			Self::MalformedRegister { token } => write!(f, "malformed register {token:?}"),
			Self::SpInstructionRegIsNotX2 { pos, line } => write!(f, "{pos} register must be x2 {line:?}"),
			Self::TrailingGarbage { line } => write!(f, r#"trailing garbage "{}""#, line.escape_ascii()),
			Self::TruncatedInstruction { line } => write!(f, r#"truncated instruction "{}""#, line.escape_ascii()),
			Self::UnknownInstruction { line } => write!(f, r#"unknown instruction "{}""#, line.escape_ascii()),
		}
	}
}

#[derive(Debug)]
pub enum EncodeError {
	ImmediateOverflow,
	IncompressibleRegister,
}

impl core::error::Error for EncodeError {}

impl core::fmt::Display for EncodeError {
	fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
		match self {
			Self::ImmediateOverflow => f.write_str("imm overflow"),
			Self::IncompressibleRegister => f.write_str("incompressible register"),
		}
	}
}

#[cfg(test)]
mod tests {
	extern crate std;
	use std::prelude::v1::*;

	#[test]
	fn full_uncompressed32() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// Registers and aliases
			("add x0, x1, x2", &[(0x8033, Some(0x0020))]),
			("add x3, x4, x5", &[(0x01b3, Some(0x0052))]),
			("add x6, x7, x8", &[(0x8333, Some(0x0083))]),
			("add x9, x10, x11", &[(0x04b3, Some(0x00b5))]),
			("add x12, x13, x14", &[(0x8633, Some(0x00e6))]),
			("add x15, x16, x17", &[(0x07b3, Some(0x0118))]),
			("add x18, x19, x20", &[(0x8933, Some(0x0149))]),
			("add x21, x22, x23", &[(0x0ab3, Some(0x017b))]),
			("add x24, x25, x26", &[(0x8c33, Some(0x01ac))]),
			("add x27, x28, x29", &[(0x0db3, Some(0x01de))]),
			("add x30, x31, x8", &[(0x8f33, Some(0x008f))]),

			("add zero, ra, sp", &[(0x8033, Some(0x0020))]),
			("add gp, tp, t0", &[(0x01b3, Some(0x0052))]),
			("add t1, t2, s0", &[(0x8333, Some(0x0083))]),
			("add s1, a0, a1", &[(0x04b3, Some(0x00b5))]),
			("add a2, a3, a4", &[(0x8633, Some(0x00e6))]),
			("add a5, a6, a7", &[(0x07b3, Some(0x0118))]),
			("add s2, s3, s4", &[(0x8933, Some(0x0149))]),
			("add s5, s6, s7", &[(0x0ab3, Some(0x017b))]),
			("add s8, s9, s10", &[(0x8c33, Some(0x01ac))]),
			("add s11, t3, t4", &[(0x0db3, Some(0x01de))]),
			("add t5, t6, fp", &[(0x8f33, Some(0x008f))]),


			// Instructions

			("add a0, a1, a2", &[(0x8533, Some(0x00c5))]),

			("addi a0, a1, -11", &[(0x8513, Some(0xff55))]),
			("addi a0, a1, 11", &[(0x8513, Some(0x00b5))]),

			("and a0, a1, a2", &[(0xf533, Some(0x00c5))]),

			("andi a0, a1, -11", &[(0xf513, Some(0xff55))]),
			("andi a0, a1, 11", &[(0xf513, Some(0x00b5))]),

			("auipc a0, -11", &[(0x5517, Some(0xffff))]),
			("auipc a0, 11", &[(0xb517, Some(0x0000))]),

			("beq a0, a1, -4", &[(0x0ee3, Some(0xfeb5))]),
			("beq a0, a1, 44", &[(0x0663, Some(0x02b5))]),

			("beqz a0, -4", &[(0x0ee3, Some(0xfe05))]),
			("beqz a0, 28", &[(0x0e63, Some(0x0005))]),

			("bge a0, a1, -12", &[(0x5ae3, Some(0xfeb5))]),
			("bge a0, a1, 36", &[(0x5263, Some(0x02b5))]),

			("bgeu a0, a1, -20", &[(0x76e3, Some(0xfeb5))]),
			("bgeu a0, a1, 28", &[(0x7e63, Some(0x00b5))]),

			("bgez a0, -12", &[(0x5ae3, Some(0xfe05))]),
			("bgez a0, 20", &[(0x5a63, Some(0x0005))]),

			("bgt a0, a1, -4", &[(0xcee3, Some(0xfea5))]),
			("bgt a0, a1, 28", &[(0xce63, Some(0x00a5))]),

			("bgtu a0, a1, -12", &[(0xeae3, Some(0xfea5))]),
			("bgtu a0, a1, 20", &[(0xea63, Some(0x00a5))]),

			("bgtz a0, -4", &[(0x4ee3, Some(0xfea0))]),
			("bgtz a0, 12", &[(0x4663, Some(0x00a0))]),

			("ble a0, a1, -20", &[(0xd6e3, Some(0xfea5))]),
			("ble a0, a1, 12", &[(0xd663, Some(0x00a5))]),

			("bleu a0, a1, -28", &[(0xf2e3, Some(0xfea5))]),
			("bleu a0, a1, 4", &[(0xf263, Some(0x00a5))]),

			("blez a0, -12", &[(0x5ae3, Some(0xfea0))]),
			("blez a0, 4", &[(0x5263, Some(0x00a0))]),

			("blt a0, a1, -28", &[(0x42e3, Some(0xfeb5))]),
			("blt a0, a1, 20", &[(0x4a63, Some(0x00b5))]),

			("bltu a0, a1, -36", &[(0x6ee3, Some(0xfcb5))]),
			("bltu a0, a1, 12", &[(0x6663, Some(0x00b5))]),

			("bltz a0, -20", &[(0x46e3, Some(0xfe05))]),
			("bltz a0, 12", &[(0x4663, Some(0x0005))]),

			("bne a0, a1, -44", &[(0x1ae3, Some(0xfcb5))]),
			("bne a0, a1, 4", &[(0x1263, Some(0x00b5))]),

			("bnez a0, -28", &[(0x12e3, Some(0xfe05))]),
			("bnez a0, 4", &[(0x1263, Some(0x0005))]),

			("call -4", &[(0x0097, Some(0x0000)), (0x80e7, Some(0xffc0))]),
			("call 24", &[(0x0097, Some(0x0000)), (0x80e7, Some(0x0180))]),
			("call a0, -20", &[(0x0517, Some(0x0000)), (0x0567, Some(0xfec5))]),
			("call a0, 8", &[(0x0517, Some(0x0000)), (0x0567, Some(0x0085))]),

			("ebreak", &[(0x0073, Some(0x0010))]),

			("ecall", &[(0x0073, Some(0x0000))]),

			("fence", &[(0x000f, Some(0x0330))]),
			("fence 0, 0", &[(0x000f, Some(0x0000))]),
			("fence iorw, iorw", &[(0x000f, Some(0x0ff0))]),

			("fence.tso", &[(0x000f, Some(0x8330))]),

			("j -4", &[(0xf06f, Some(0xffdf))]),
			("j 4", &[(0x006f, Some(0x0040))]),

			("jal -4", &[(0xf0ef, Some(0xffdf))]),
			("jal 12", &[(0x00ef, Some(0x00c0))]),
			("jal a0, -12", &[(0xf56f, Some(0xff5f))]),
			("jal a0, 4", &[(0x056f, Some(0x0040))]),

			("jalr (a0)", &[(0x00e7, Some(0x0005))]),
			("jalr -11(a0)", &[(0x00e7, Some(0xff55))]),
			("jalr 11(a0)", &[(0x00e7, Some(0x00b5))]),
			("jalr a0, a1", &[(0x8567, Some(0x0005))]),
			("jalr a0, (a1)", &[(0x8567, Some(0x0005))]),
			("jalr a0, -11(a1)", &[(0x8567, Some(0xff55))]),
			("jalr a0, 11(a1)", &[(0x8567, Some(0x00b5))]),
			("jalr a0", &[(0x00e7, Some(0x0005))]),

			("jump -4, a0", &[(0x0517, Some(0x0000)), (0x0067, Some(0xffc5))]),
			("jump 8, a0", &[(0x0517, Some(0x0000)), (0x0067, Some(0x0085))]),

			// Positive immediate with [11:0] significant bits -> addi
			("li a0, 0x7ff", &[(0x0513, Some(0x7ff0))]),
			// Negative immediate with [11:0] significant bits -> addi
			("li a0, -1", &[(0x0513, Some(0xfff0))]),
			// Positive immediate with [31:12] significant bits -> lui
			("li a0, 0x7ffff000", &[(0xf537, Some(0x7fff))]),
			// Negative immediate with [31:12] significant bits -> lui
			("li a0, -4096", &[(0xf537, Some(0xffff))]),
			// Positive immediate with [31:0] significant bits -> lui; addi
			("li a0, 0x7fffffff", &[(0x0537, Some(0x8000)), (0x0513, Some(0xfff5))]),
			// Negative immediate with [31:0] significant bits -> lui; addi
			("li a0, -2147479553", &[(0x1537, Some(0x8000)), (0x0513, Some(0xfff5))]),

			("lla a0, -4", &[(0x0517, Some(0x0000)), (0x0513, Some(0xffc5))]),
			("lla a0, 8", &[(0x0517, Some(0x0000)), (0x0513, Some(0x0085))]),

			("lui a0, -11", &[(0x5537, Some(0xffff))]),
			("lui a0, 11", &[(0xb537, Some(0x0000))]),

			("lb a0, -4", &[(0x0517, Some(0x0000)), (0x0503, Some(0xffc5))]),
			("lb a0, 104", &[(0x0517, Some(0x0000)), (0x0503, Some(0x0685))]),
			("lb a0, -11(a1)", &[(0x8503, Some(0xff55))]),
			("lb a0, 11(a1)", &[(0x8503, Some(0x00b5))]),

			("lbu a0, -20", &[(0x0517, Some(0x0000)), (0x4503, Some(0xfec5))]),
			("lbu a0, 88", &[(0x0517, Some(0x0000)), (0x4503, Some(0x0585))]),
			("lbu a0, -11(a1)", &[(0xc503, Some(0xff55))]),
			("lbu a0, 11(a1)", &[(0xc503, Some(0x00b5))]),

			("lh a0, -52", &[(0x0517, Some(0x0000)), (0x1503, Some(0xfcc5))]),
			("lh a0, 56", &[(0x0517, Some(0x0000)), (0x1503, Some(0x0385))]),
			("lh a0, -11(a1)", &[(0x9503, Some(0xff55))]),
			("lh a0, 11(a1)", &[(0x9503, Some(0x00b5))]),

			("lhu a0, -68", &[(0x0517, Some(0x0000)), (0x5503, Some(0xfbc5))]),
			("lhu a0, 40", &[(0x0517, Some(0x0000)), (0x5503, Some(0x0285))]),
			("lhu a0, -11(a1)", &[(0xd503, Some(0xff55))]),
			("lhu a0, 11(a1)", &[(0xd503, Some(0x00b5))]),

			("lw a0, -84", &[(0x0517, Some(0x0000)), (0x2503, Some(0xfac5))]),
			("lw a0, 24", &[(0x0517, Some(0x0000)), (0x2503, Some(0x0185))]),
			("lw a0, -11(a1)", &[(0xa503, Some(0xff55))]),
			("lw a0, 11(a1)", &[(0xa503, Some(0x00b5))]),

			("mv a0, a1", &[(0x8513, Some(0x0005))]),

			("neg a0, a1", &[(0x0533, Some(0x40b0))]),

			("nop", &[(0x0013, Some(0x0000))]),

			("not a0, a1", &[(0xc513, Some(0xfff5))]),

			("ntl.all", &[(0x0033, Some(0x0050))]),
			("ntl.pall", &[(0x0033, Some(0x0030))]),
			("ntl.p1", &[(0x0033, Some(0x0020))]),
			("ntl.s1", &[(0x0033, Some(0x0040))]),

			("or a0, a1, a2", &[(0xe533, Some(0x00c5))]),

			("ori a0, a1, -11", &[(0xe513, Some(0xff55))]),
			("ori a0, a1, 11", &[(0xe513, Some(0x00b5))]),

			("pause", &[(0x000f, Some(0x0100))]),

			("ret", &[(0x8067, Some(0x0000))]),

			("sb a0, -11(a1)", &[(0x8aa3, Some(0xfea5))]),
			("sb a0, 11(a1)", &[(0x85a3, Some(0x00a5))]),

			("seqz a0, a1", &[(0xb513, Some(0x0015))]),

			("sext.b a0, a1", &[(0x9513, Some(0x0185)), (0x5513, Some(0x4185))]),

			("sext.h a0, a1", &[(0x9513, Some(0x0105)), (0x5513, Some(0x4105))]),

			("sgtz a0, a1", &[(0x2533, Some(0x00b0))]),

			("sh a0, -11(a1)", &[(0x9aa3, Some(0xfea5))]),
			("sh a0, 11(a1)", &[(0x95a3, Some(0x00a5))]),

			("sh1add a0, a1, a2", &[(0xa533, Some(0x20c5))]),

			("sh2add a0, a1, a2", &[(0xc533, Some(0x20c5))]),

			("sh3add a0, a1, a2", &[(0xe533, Some(0x20c5))]),

			("sll a0, a1, a2", &[(0x9533, Some(0x00c5))]),

			("slli a0, a1, 11", &[(0x9513, Some(0x00b5))]),
			("slli a0, a1, 31", &[(0x9513, Some(0x01f5))]),

			("slt a0, a1, a2", &[(0xa533, Some(0x00c5))]),

			("slti a0, a1, -11", &[(0xa513, Some(0xff55))]),
			("slti a0, a1, 11", &[(0xa513, Some(0x00b5))]),

			("sltiu a0, a1, -11", &[(0xb513, Some(0xff55))]),
			("sltiu a0, a1, 11", &[(0xb513, Some(0x00b5))]),

			("sltu a0, a1, a2", &[(0xb533, Some(0x00c5))]),

			("sltz a0, a1", &[(0xa533, Some(0x0005))]),

			("snez a0, a1", &[(0x3533, Some(0x00b0))]),

			("sra a0, a1, a2", &[(0xd533, Some(0x40c5))]),

			("srai a0, a1, 11", &[(0xd513, Some(0x40b5))]),
			("srai a0, a1, 31", &[(0xd513, Some(0x41f5))]),

			("srl a0, a1, a2", &[(0xd533, Some(0x00c5))]),

			("srli a0, a1, 11", &[(0xd513, Some(0x00b5))]),
			("srli a0, a1, 31", &[(0xd513, Some(0x01f5))]),

			("sub a0, a1, a2", &[(0x8533, Some(0x40c5))]),

			("sw a0, -11(a1)", &[(0xaaa3, Some(0xfea5))]),
			("sw a0, 11(a1)", &[(0xa5a3, Some(0x00a5))]),

			("tail -4", &[(0x0317, Some(0x0000)), (0x0067, Some(0xffc3))]),
			("tail 8", &[(0x0317, Some(0x0000)), (0x0067, Some(0x0083))]),

			("xor a0, a1, a2", &[(0xc533, Some(0x00c5))]),

			("xori a0, a1, -11", &[(0xc513, Some(0xff55))]),
			("xori a0, a1, 11", &[(0xc513, Some(0x00b5))]),

			("zext.b a0, a1", &[(0xf513, Some(0x0ff5))]),

			("zext.h a0, a1", &[(0x9513, Some(0x0105)), (0x5513, Some(0x0105))]),
		];
		for &(input, expected) in TESTS {
			const SUPPORTED_EXTENSIONS: crate::SupportedExtensions = crate::SupportedExtensions::RV32I;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), SUPPORTED_EXTENSIONS)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, SUPPORTED_EXTENSIONS).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn full_compressed32() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// All registers and aliases
			("add x8, x8, x9", &[(0x9426, None)]),
			("add x10, x10, x11", &[(0x952e, None)]),
			("add x12, x12, x13", &[(0x9636, None)]),
			("add x14, x14, x15", &[(0x973e, None)]),

			("add s0, fp, s1", &[(0x9426, None)]),
			("add a0, a0, a1", &[(0x952e, None)]),
			("add a2, a2, a3", &[(0x9636, None)]),
			("add a4, a4, a5", &[(0x973e, None)]),


			// Instructions

			("add x3, x3, x4", &[(0x9192, None)]),
			("add x3, x3, x0", &[(0x818e, None)]), // Collides with c.jalr and c.ebreak, but gets encoded as `mv x3, x3` instead
			("add x0, x0, x4", &[(0x9012, None)]), // HINT, but gets encoded as `ntl.s1` instead

			("addi x3, x3, -11", &[(0x11d5, None)]),
			("addi x3, x3, 11", &[(0x01ad, None)]),
			("addi x0, x0, -11", &[(0x0013, Some(0xff50))]), // Collides with c.nop
			("addi x0, x0, 11", &[(0x0013, Some(0x00b0))]), // Collides with c.nop
			("addi x3, x3, 0", &[(0x818e, None)]), // HINT, but gets encoded as `mv x3, x3` instead

			("addi4spn x8, x2, 44", &[(0x1060, None)]),
			("addi4spn x3, x2, 44", &[(0x0193, Some(0x02c1))]), // Incompressible register
			("addi4spn x8, x2, 0", &[(0x840a, None)]), // Reserved, but gets encoded as `mv x8, x2` instead
			("addi x8, x2, 44", &[(0x1060, None)]),
			("addi x3, x2, 44", &[(0x0193, Some(0x02c1))]), // Incompressible register
			("addi x8, x2, 0", &[(0x840a, None)]), // Reserved, but gets encoded as `mv x8, x2` instead

			("addi16sp x2, 176", &[(0x614d, None)]),
			("addi16sp x2, 0", &[(0x810a, None)]), // Reserved, but gets encoded as `mv x2, x2` instead
			("addi x2, x2, -176", &[(0x7171, None)]),
			("addi x2, x2, 176", &[(0x614d, None)]),
			("addi x2, x2, 0", &[(0x810a, None)]), // Reserved, but gets encoded as `mv x2, x2` instead

			("and x8, x8, x9", &[(0x8c65, None)]),
			("and x3, x3, x9", &[(0xf1b3, Some(0x0091))]), // Incompressible register
			("and x8, x8, x4", &[(0x7433, Some(0x0044))]), // Incompressible register

			("andi x8, x8, 11", &[(0x882d, None)]),
			("andi x8, x8, -11", &[(0x9855, None)]),
			("andi x3, x3, -11", &[(0xf193, Some(0xff51))]), // Incompressible register
			("andi x3, x3, 11", &[(0xf193, Some(0x00b1))]), // Incompressible register

			("beqz x8, -22", &[(0xd46d, None)]),
			("beqz x8, 22", &[(0xc819, None)]),
			("beqz x3, -22", &[(0x85e3, Some(0xfe01))]), // Incompressible register
			("beqz x3, 22", &[(0x8b63, Some(0x0001))]), // Incompressible register

			("bnez x8, -22", &[(0xf46d, None)]),
			("bnez x8, 22", &[(0xe819, None)]),
			("bnez x3, -22", &[(0x95e3, Some(0xfe01))]), // Incompressible register
			("bnez x3, 22", &[(0x9b63, Some(0x0001))]), // Incompressible register

			("ebreak", &[(0x9002, None)]),

			("j -22", &[(0xb7ed, None)]),
			("j 22", &[(0xa819, None)]),

			("jal -22", &[(0x37ed, None)]),
			("jal 22", &[(0x2819, None)]),

			("jalr x3", &[(0x9182, None)]),

			("jr x3", &[(0x8182, None)]),

			("lbu x8, 0(x9)", &[(0x8080, None)]),
			("lbu x8, 1(x9)", &[(0x80c0, None)]),
			("lbu x8, 2(x9)", &[(0x80a0, None)]),
			("lbu x8, 3(x9)", &[(0x80e0, None)]),
			("lbu x3, 3(x9)", &[(0xc183, Some(0x0034))]), // Incompressible register
			("lbu x8, 3(x4)", &[(0x4403, Some(0x0032))]), // Incompressible register
			("lbu x8, 4(x4)", &[(0x4403, Some(0x0042))]), // Offset out of range

			("lh x8, 0(x9)", &[(0x84c0, None)]),
			("lh x8, 2(x9)", &[(0x84e0, None)]),
			("lh x3, 2(x9)", &[(0x9183, Some(0x0024))]), // Incompressible register
			("lh x8, 2(x4)", &[(0x1403, Some(0x0022))]), // Incompressible register
			("lh x8, 1(x4)", &[(0x1403, Some(0x0012))]), // Offset out of range
			("lh x8, 3(x4)", &[(0x1403, Some(0x0032))]), // Offset out of range
			("lh x8, 4(x4)", &[(0x1403, Some(0x0042))]), // Offset out of range

			("lhu x8, 0(x9)", &[(0x8480, None)]),
			("lhu x8, 2(x9)", &[(0x84a0, None)]),
			("lhu x3, 2(x9)", &[(0xd183, Some(0x0024))]), // Incompressible register
			("lhu x8, 2(x4)", &[(0x5403, Some(0x0022))]), // Incompressible register
			("lhu x8, 1(x4)", &[(0x5403, Some(0x0012))]), // Offset out of range
			("lhu x8, 3(x4)", &[(0x5403, Some(0x0032))]), // Offset out of range
			("lhu x8, 4(x4)", &[(0x5403, Some(0x0042))]), // Offset out of range

			("li x3, -11", &[(0x51d5, None)]),
			("li x3, 11", &[(0x41ad, None)]),
			("li x0, -11", &[(0x0013, Some(0xff50))]), // HINT
			("li x0, 11", &[(0x0013, Some(0x00b0))]), // HINT

			("lui x3, -11", &[(0x71d5, None)]),
			("lui x3, 11", &[(0x61ad, None)]),
			("lui x3, 0", &[(0x4181, None)]), // Reserved, but gets encoded as `li x3, 0`
			("lui x0, -11", &[(0x5037, Some(0xffff))]), // HINT
			("lui x0, 11", &[(0xb037, Some(0x0000))]), // HINT
			("lui x2, -11", &[(0x5137, Some(0xffff))]), // Collides with c.addi16sp
			("lui x2, 11", &[(0xb137, Some(0x0000))]), // Collides with c.addi16sp

			("lw x8, 44(x9)", &[(0x54c0, None)]),
			("lw x3, 44(x9)", &[(0xa183, Some(0x02c4))]), // Incompressible register
			("lw x8, 44(x4)", &[(0x2403, Some(0x02c2))]), // Incompressible register

			("lwsp x3, 44(x2)", &[(0x51b2, None)]),
			("lwsp x0, 44(x2)", &[(0x2003, Some(0x02c1))]), // Reserved
			("lw x3, 44(x2)", &[(0x51b2, None)]),
			("lw x0, 44(x2)", &[(0x2003, Some(0x02c1))]), // Reserved

			("mv x3, x4", &[(0x8192, None)]),
			("mv x3, x0", &[(0x4181, None)]), // Collides with c.jr, but gets encoded as `li x3, 0` instead
			("mv x0, x0", &[(0x0001, None)]), // HINT, but gets encoded as `nop` instead

			("nop", &[(0x0001, None)]),

			("not x8, x8", &[(0x9c75, None)]),
			("not x3, x3", &[(0xc193, Some(0xfff1))]), // Incompressible register

			("ntl.all", &[(0x9016, None)]),
			("ntl.pall", &[(0x900e, None)]),
			("ntl.p1", &[(0x900a, None)]),
			("ntl.s1", &[(0x9012, None)]),

			("or x8, x8, x9", &[(0x8c45, None)]),
			("or x3, x3, x9", &[(0xe1b3, Some(0x0091))]), // Incompressible register
			("or x8, x8, x4", &[(0x6433, Some(0x0044))]), // Incompressible register

			("sb x8, 0(x9)", &[(0x8880, None)]),
			("sb x8, 1(x9)", &[(0x88c0, None)]),
			("sb x8, 2(x9)", &[(0x88a0, None)]),
			("sb x8, 3(x9)", &[(0x88e0, None)]),
			("sb x3, 3(x9)", &[(0x81a3, Some(0x0034))]), // Incompressible register
			("sb x8, 3(x4)", &[(0x01a3, Some(0x0082))]), // Incompressible register
			("sb x8, 4(x4)", &[(0x0223, Some(0x0082))]), // Offset out of range

			("sh x8, 0(x9)", &[(0x8c80, None)]),
			("sh x8, 2(x9)", &[(0x8ca0, None)]),
			("sh x3, 2(x9)", &[(0x9123, Some(0x0034))]), // Incompressible register
			("sh x8, 2(x4)", &[(0x1123, Some(0x0082))]), // Incompressible register
			("sh x8, 1(x4)", &[(0x10a3, Some(0x0082))]), // Offset out of range
			("sh x8, 3(x4)", &[(0x11a3, Some(0x0082))]), // Offset out of range
			("sh x8, 4(x4)", &[(0x1223, Some(0x0082))]), // Offset out of range

			("slli x3, x3, 11", &[(0x01ae, None)]),
			("slli x3, x3, 31", &[(0x01fe, None)]),
			("slli x3, x3, 0", &[(0x9193, Some(0x0001))]), // HINT
			("slli x0, x0, 31", &[(0x1013, Some(0x01f0))]), // HINT

			("srai x8, x8, 11", &[(0x842d, None)]),
			("srai x8, x8, 31", &[(0x847d, None)]),
			("srai x3, x3, 11", &[(0xd193, Some(0x40b1))]), // Incompressible register
			("srai x8, x8, 0", &[(0x5413, Some(0x4004))]), // HINT

			("srli x8, x8, 11", &[(0x802d, None)]),
			("srli x8, x8, 31", &[(0x807d, None)]),
			("srli x3, x3, 11", &[(0xd193, Some(0x00b1))]), // Incompressible register
			("srli x8, x8, 0", &[(0x5413, Some(0x0004))]), // HINT

			("sub x8, x8, x9", &[(0x8c05, None)]),
			("sub x3, x3, x9", &[(0x81b3, Some(0x4091))]), // Incompressible register
			("sub x8, x8, x4", &[(0x0433, Some(0x4044))]), // Incompressible register

			("sw x8, 44(x9)", &[(0xd4c0, None)]),
			("sw x3, 44(x9)", &[(0xa623, Some(0x0234))]), // Incompressible register
			("sw x8, 44(x4)", &[(0x2623, Some(0x0282))]), // Incompressible register

			("swsp x3, 44(x2)", &[(0xd60e, None)]),
			("swsp x0, 44(x2)", &[(0xd602, None)]),
			("sw x3, 44(x2)", &[(0xd60e, None)]),
			("sw x0, 44(x2)", &[(0xd602, None)]),

			("xor x8, x8, x9", &[(0x8c25, None)]),
			("xor x3, x3, x9", &[(0xc1b3, Some(0x0091))]), // Incompressible register
			("xor x8, x8, x4", &[(0x4433, Some(0x0044))]), // Incompressible register

			("zext.b x8, x8", &[(0x9c61, None)]),
			("zext.b x3, x3", &[(0xf193, Some(0x0ff1))]), // Incompressible register
		];
		for &(input, expected) in TESTS {
			const SUPPORTED_EXTENSIONS: crate::SupportedExtensions = crate::SupportedExtensions::RV32C_ZCB;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), SUPPORTED_EXTENSIONS)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, SUPPORTED_EXTENSIONS).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn full_uncompressed64() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// Instructions

			("addiw a0, a1, -11", &[(0x851b, Some(0xff55))]),
			("addiw a0, a1, 11", &[(0x851b, Some(0x00b5))]),

			("add.uw a0, a1, a2", &[(0x853b, Some(0x08c5))]),

			("addw a0, a1, a2", &[(0x853b, Some(0x00c5))]),

			("ld a0, -36", &[(0x0517, Some(0x0000)), (0x3503, Some(0xfdc5))]),
			("ld a0, 72", &[(0x0517, Some(0x0000)), (0x3503, Some(0x0485))]),
			("ld a0, -11(a1)", &[(0xb503, Some(0xff55))]),
			("ld a0, 11(a1)", &[(0xb503, Some(0x00b5))]),

			("lwu a0, -100", &[(0x0517, Some(0x0000)), (0x6503, Some(0xf9c5))]),
			("lwu a0, 8", &[(0x0517, Some(0x0000)), (0x6503, Some(0x0085))]),
			("lwu a0, -11(a1)", &[(0xe503, Some(0xff55))]),
			("lwu a0, 11(a1)", &[(0xe503, Some(0x00b5))]),

			("negw a0, a1", &[(0x053b, Some(0x40b0))]),

			("sd a0, -11(a1)", &[(0xbaa3, Some(0xfea5))]),
			("sd a0, 11(a1)", &[(0xb5a3, Some(0x00a5))]),

			("sext.b a0, a1", &[(0x9513, Some(0x0385)), (0x5513, Some(0x4385))]),

			("sext.h a0, a1", &[(0x9513, Some(0x0305)), (0x5513, Some(0x4305))]),

			("sext.w a0, a1", &[(0x851b, Some(0x0005))]),

			("sh1add.uw a0, a1, a2", &[(0xa53b, Some(0x20c5))]),

			("sh2add.uw a0, a1, a2", &[(0xc53b, Some(0x20c5))]),

			("sh3add.uw a0, a1, a2", &[(0xe53b, Some(0x20c5))]),

			("slli a0, a1, 63", &[(0x9513, Some(0x03f5))]),

			("slli.uw a0, a1, 63", &[(0x951b, Some(0x0bf5))]),

			("slliw a0, a1, 11", &[(0x951b, Some(0x00b5))]),
			("slliw a0, a1, 31", &[(0x951b, Some(0x01f5))]),

			("sllw a0, a1, a2", &[(0x953b, Some(0x00c5))]),

			("srai a0, a1, 63", &[(0xd513, Some(0x43f5))]),

			("sraiw a0, a1, 11", &[(0xd51b, Some(0x40b5))]),
			("sraiw a0, a1, 31", &[(0xd51b, Some(0x41f5))]),

			("sraw a0, a1, a2", &[(0xd53b, Some(0x40c5))]),

			("srli a0, a1, 63", &[(0xd513, Some(0x03f5))]),

			("srliw a0, a1, 11", &[(0xd51b, Some(0x00b5))]),
			("srliw a0, a1, 31", &[(0xd51b, Some(0x01f5))]),

			("srlw a0, a1, a2", &[(0xd53b, Some(0x00c5))]),

			("subw a0, a1, a2", &[(0x853b, Some(0x40c5))]),

			("zext.h a0, a1", &[(0x9513, Some(0x0305)), (0x5513, Some(0x0305))]),

			("zext.w a0, a1", &[(0x9513, Some(0x0205)), (0x5513, Some(0x0205))]),
		];
		for &(input, expected) in TESTS {
			const SUPPORTED_EXTENSIONS: crate::SupportedExtensions = crate::SupportedExtensions::RV64I;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), SUPPORTED_EXTENSIONS)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, SUPPORTED_EXTENSIONS).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn full_compressed64() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// Instructions

			("addw x8, x8, x9", &[(0x9c25, None)]),
			("addw x3, x3, x9", &[(0x81bb, Some(0x0091))]), // Incompressible register
			("addw x8, x8, x4", &[(0x043b, Some(0x0044))]), // Incompressible register

			("jal -22", &[(0xf0ef, Some(0xfebf))]), // Collides with c.addiw
			("jal 22", &[(0x00ef, Some(0x0160))]), // Collides with c.addiw

			("ld x8, 88(x9)", &[(0x6ca0, None)]),
			("ld x3, 88(x9)", &[(0xb183, Some(0x0584))]), // Incompressible register
			("ld x8, 88(x4)", &[(0x3403, Some(0x0582))]), // Incompressible register

			("ldsp x3, 88(x2)", &[(0x61e6, None)]),
			("ldsp x0, 88(x2)", &[(0x3003, Some(0x0581))]), // Reserved
			("ld x3, 88(x2)", &[(0x61e6, None)]),
			("ld x0, 88(x2)", &[(0x3003, Some(0x0581))]), // Reserved

			("sd x8, 88(x9)", &[(0xeca0, None)]),
			("sd x3, 88(x9)", &[(0xbc23, Some(0x0434))]), // Incompressible register
			("sd x8, 88(x4)", &[(0x3c23, Some(0x0482))]), // Incompressible register

			("sdsp x3, 88(x2)", &[(0xec8e, None)]),
			("sdsp x0, 88(x2)", &[(0xec82, None)]),
			("sd x3, 88(x2)", &[(0xec8e, None)]),
			("sd x0, 88(x2)", &[(0xec82, None)]),

			("slli x3, x3, 63", &[(0x11fe, None)]),
			("slli x0, x0, 63", &[(0x1013, Some(0x03f0))]), // HINT

			("srai x8, x8, 63", &[(0x947d, None)]),

			("srli x8, x8, 63", &[(0x907d, None)]),

			("subw x8, x8, x9", &[(0x9c05, None)]),
			("subw x3, x3, x9", &[(0x81bb, Some(0x4091))]), // Incompressible register
			("subw x8, x8, x4", &[(0x043b, Some(0x4044))]), // Incompressible register

			("zext.w x8, x8", &[(0x9c71, None)]),
			("zext.w x3, x3", &[(0x81bb, Some(0x0801))]), // Incompressible register
		];
		for &(input, expected) in TESTS {
			let supported_extensions: crate::SupportedExtensions = crate::SupportedExtensions::RV64C_ZCB | crate::SupportedExtensions::ZBA;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), supported_extensions)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, supported_extensions).map_err(|err| err.to_string())?;
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

	#[test]
	fn gas_uncompressed32() {
		static TESTS: &[(&str, &[(u16, u16)])] = &[
			// auipc-x0.s
			("
				auipc x0, 0
				lw x0, 0(x0)
			", &[
				(0x0017, 0x0000),
				(0x2003, 0x0000),
			]),

			// b-ext.s
			("
				sh1add a0, a1, a2
				sh2add a0, a1, a2
				sh3add a0, a1, a2
			", &[
				(0xa533, 0x20c5),
				(0xc533, 0x20c5),
				(0xe533, 0x20c5),
			]),

			// bge.s
			("
				bge a1, a2, 0
				ble a1, a2, -4
				bgeu a1, a2, -8
				bleu a1, a2, -12
			", &[
				(0xd063, 0x00c5),
				(0x5ee3, 0xfeb6),
				(0xfce3, 0xfec5),
				(0x7ae3, 0xfeb6),
			]),

			// csr.s
			("
				# User Counter/Timers
				csrr a0, cycle
				csrw cycle, a1
				csrr a0, time
				csrw time, a1
				csrr a0, instret
				csrw instret, a1
				csrr a0, cycleh
				csrw cycleh, a1
				csrr a0, timeh
				csrw timeh, a1
				csrr a0, instreth
				csrw instreth, a1
				csrr a0, misa
				csrw misa, a1
			", &[
				(0x2573, 0xc000),
				(0x9073, 0xc005),
				(0x2573, 0xc010),
				(0x9073, 0xc015),
				(0x2573, 0xc020),
				(0x9073, 0xc025),
				(0x2573, 0xc800),
				(0x9073, 0xc805),
				(0x2573, 0xc810),
				(0x9073, 0xc815),
				(0x2573, 0xc820),
				(0x9073, 0xc825),
				(0x2573, 0x3010),
				(0x9073, 0x3015),
			]),

			// csr-insns-pseudo.s
			("
				# i-ext
				csrr t0, 0x0
				csrw 0x0, t0
				csrs 0x0, t0
				csrc 0x0, t0
				csrwi 0x0, 31
				csrsi 0x0, 31
				csrci 0x0, 31

				rdcycle t0
				rdtime t0
				rdinstret t0

				# rv32i-ext
				rdcycleh t0
				rdtimeh t0
				rdinstreth t0
			", &[
				(0x22f3, 0x0000),
				(0x9073, 0x0002),
				(0xa073, 0x0002),
				(0xb073, 0x0002),
				(0xd073, 0x000f),
				(0xe073, 0x000f),
				(0xf073, 0x000f),
				(0x22f3, 0xc000),
				(0x22f3, 0xc010),
				(0x22f3, 0xc020),
				(0x22f3, 0xc800),
				(0x22f3, 0xc810),
				(0x22f3, 0xc820),
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
				(0xf2b7, 0xffff),
				(0xa903, 0xffc2),
				(0xe337, 0xffff),
				(0x2c23, 0xff33),
				(0xd3b7, 0xffff),
				(0x80e7, 0x0003),
				(0xce37, 0xffff),
				(0x00e7, 0xff4e),
				(0xbeb7, 0xffff),
				(0x8a67, 0x000e),
				(0xaf37, 0xffff),
				(0x0a93, 0xff0f),
				(0xa283, 0x4001),
				(0xa303, 0xc001),
				(0x2383, 0x1000),
				(0x2e03, 0x8000),
				(0x0ee7, 0x1040),
				(0x0f67, 0x8040),
			]),

			// dis-addr-topaddr.s
			("
				lb t0, -1(zero)
			", &[
				(0x0283, 0xfff0),
			]),

			// dis-addr-topaddr-gp.s
			("
				# Use addresses relative to gp
				# (gp is the highest address)
				lw t0, +5(gp)
				lw t1, -3(gp)
			", &[
				(0xa283, 0x0051),
				(0xa303, 0xffd1),
			]),

			// fence-tso.s
			("
				fence.tso
			", &[
				(0x000f, 0x8330),
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
				(0x0517, 0x0000),
				(0x0513, 0x0185),
				(0x0517, 0x0000),
				(0x1503, 0x0105),
				(0x0517, 0x0000),
				(0x1423, 0x00a5),
				(0x0517, 0x0000),
				(0x0513, 0x0005),
				(0x0517, 0x0000),
				(0x1503, 0x0005),
				(0x0517, 0x0000),
				(0x1023, 0x00a5),
				(0x0517, 0x0000),
				(0x0513, 0x0005),
				(0x0517, 0x0000),
				(0x1503, 0x0005),
				(0x0517, 0x0000),
				(0x1023, 0x00a5),
				(0x0517, 0x0000),
				(0x2503, 0x0105),
				(0x0517, 0x0000),
				(0x2823, 0x00a5),
				(0x8067, 0x0000),
			]),

			// t_insns.s
			("
				nop
			", &[
				(0x0013, 0x0000),
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
				(0x0517, 0x0000),
				(0x2283, 0x0005),
				(0x0513, 0x0005),
				(0x82e7, 0x0002),
				(0x0517, 0x0000),
				(0x2283, 0x0005),
				(0x0513, 0x0005),
				(0x82e7, 0x0002),
				(0x8067, 0x0000),
			]),

			// zicond.s
			("
				czero.eqz a0, a1, a2
				czero.nez a0, a3, a4
			", &[
				(0xd533, 0x0ec5),
				(0xf533, 0x0ee6),
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
				(0x0033, 0x0020),
				(0x8023, 0x01b2),
				(0x0033, 0x0030),
				(0x8123, 0x01b2),
				(0x0033, 0x0040),
				(0x8223, 0x01b2),
				(0x0033, 0x0050),
				(0x8323, 0x01b2),
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
				(0x0033, 0x0020),
				(0x8023, 0x01b2),
				(0x0033, 0x0030),
				(0x8123, 0x01b2),
				(0x0033, 0x0040),
				(0x8223, 0x01b2),
				(0x0033, 0x0050),
				(0x8323, 0x01b2),
			]),
		];
		for &(input, expected) in TESTS {
			const SUPPORTED_EXTENSIONS: crate::SupportedExtensions = crate::SupportedExtensions::RV32I;

			std::eprintln!("{input}");

			let expected = expected.iter().map(|&(lo, hi)| (lo, Some(hi))).collect::<Vec<_>>();
			let actual =
				super::parse_program(input.lines().map(str::as_bytes), SUPPORTED_EXTENSIONS)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, SUPPORTED_EXTENSIONS).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn gas_compressed32() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// c-add-addi.s
			("
				addi a2, zero, 1
				add a0, zero, a1
			", &[
				(0x4605, None),
				(0x852e, None),
			]),

			// c-branch.s
			("
				beq x8, x0, 0
				beqz x9, -2
				bne x8, x0, -4
				bnez x9, -6
				j -8
				jal -10
				jalr x6
				jr x7
				ret
			", &[
				(0xc001, None),
				(0xdcfd, None),
				(0xfc75, None),
				(0xfced, None),
				(0xbfe5, None),
				(0x3fdd, None),
				(0x9302, None),
				(0x8382, None),
				(0x8082, None),
			]),

			// c-lw.s
			("
				lw a0, (a0)  # 'Ck'
				lw a0, 0(a0) # 'Ck'
				sw a0, (a0)  # 'Ck'
				sw a0, 0(a0) # 'Ck'
				lw a0, (sp)  # 'Cm'
				lw a0, 0(sp) # 'Cm'
				sw a0, (sp)  # 'CM'
				sw a0, 0(sp) # 'CM'
			", &[
				(0x4108, None),
				(0x4108, None),
				(0xc108, None),
				(0xc108, None),
				(0x4502, None),
				(0x4502, None),
				(0xc02a, None),
				(0xc02a, None),
			]),

			// c-zero-imm.s
			("
				# These are valid instructions.
				li a0,0
				li a1,0
				andi a2,a2,0
				andi a3,a3,0
				addi x0,x0,0
				# compress to c.mv.
				addi a4,a4,0
				# Don't let these compress to hints.
				slli a0, a0, 0
				srli a1, a1, 0
				srai a2, a2, 0
			", &[
				(0x4501, None),
				(0x4581, None),
				(0x8a01, None),
				(0x8a81, None),
				(0x0001, None),
				(0x873a, None),
				(0x1513, Some(0x0005)),
				(0xd593, Some(0x0005)),
				(0x5613, Some(0x4006)),
			]),

			// c-zero-reg.s
			("
				# Don't let these compress to hints.
				li x0, 5
				lui x0, 6
				slli x0, x0, 7
				mv x0, x1
				add x0, x0, x1
			", &[
				(0x0013, Some(0x0050)),
				(0x6037, Some(0x0000)),
				(0x1013, Some(0x0070)),
				// gas wants this to be incompressible, ie `(0x8013, Some(0x0000))`,
				// because the original is `c.mv` which expands to `add x0, x0, x1`,
				// and `add x0, x0, !x0` is a HINT.
				//
				// We don't differentiate between `mv` and `c.mv` so we treat the input as `addi x0, x0, x1`,
				// which is compressible.
				(0x0001, None),
				(0x0033, Some(0x0010)),
			]),

			// dis-addr-overflow.s
			("
				addi t6, t6, -20

				# Use addresses relative to gp
				lw t0, 0x400(gp)
				lw t1, -0x400(gp)
				# Use addresses relative to zero
				lw t2, 0x100(zero)
				lw t3, -0x800(zero)
				jalr t4, 0x104(zero)
				jalr t5, -0x7fc(zero)
			", &[
				(0x1fb1, None),
				(0xa283, Some(0x4001)),
				(0xa303, Some(0xc001)),
				(0x2383, Some(0x1000)),
				(0x2e03, Some(0x8000)),
				(0x0ee7, Some(0x1040)),
				(0x0f67, Some(0x8040)),
			]),

			// li32.s
			("
				li  a0, 0x8001
				li  a0, 0x1f01
				li  a0, 0x12345001
				li  a0, 0xf2345001
			", &[
				(0x6521, None),
				(0x0505, None),
				(0x6509, None),
				(0x0513, Some(0xf015)),
				(0x5537, Some(0x1234)),
				(0x0505, None),
				(0x5537, Some(0xf234)),
				(0x0505, None),
			]),

			// zca.s
			("
				li x1, 31
				li x2, 0
				lui x1, 1
				lui x3, 31
				lw x8, (x9)
				lw x9, 32(x10)
				lw a0, (sp)
				c.lwsp x1, (x2)
				sw x8, (x9)
				sw x9, 32(x10)
				sw a0, (sp)
				c.swsp x1, (x2)
				addi x0, x0, 0
				nop
				add x1, x1, x2
				addi a1, a1, 31
				addi x2, x2, 0
				addi4spn x8, x2, 4
				addi16sp x2, 32
				sub x8, x8, x9
				and x8, x8, x9
				andi x8, x8, 31
				or x8, x8, x9
				xor x8, x8, x9
				mv x0, x1
				slli x0, x0, 1
				beqz x8, -80
				bnez x8, -82
				j -84
				jr ra
				jalr ra
			", &[
				(0x40fd, None),
				(0x4101, None),
				(0x6085, None),
				(0x61fd, None),
				(0x4080, None),
				(0x5104, None),
				(0x4502, None),
				(0x4082, None),
				(0xc080, None),
				(0xd104, None),
				(0xc02a, None),
				(0xc006, None),
				(0x0001, None),
				(0x0001, None),
				(0x908a, None),
				(0x05fd, None),
				// gas wants this to be `(0x0101, None)` because the original is `c.addi` and `c.addi _, 0` is a HINT.
				//
				// We don't differentiate between `addi` and `c.addi` so we compress it as `c.mv` instead.
				(0x810a, None),
				(0x0040, None),
				(0x6105, None),
				(0x8c05, None),
				(0x8c65, None),
				(0x887d, None),
				(0x8c45, None),
				(0x8c25, None),
				// gas wants this to be `(0x8006, None)` because the original is `c.mv` which expands to `add x0, x0, x1`,
				// and `add x0, x0, !x0` is a HINT.
				//
				// We don't differentiate between `mv` and `c.mv` so we treat the input as `addi x0, x0, x1`
				(0x0001, None),
				// gas wants this to be `(0x0006, None)` because the original is `c.slli` and `slli x0, _` is a HINT.
				//
				// We don't differentiate between `slli` and `c.slli` so we don't compress it.
				(0x1013, Some(0x0010)),
				(0xd845, None),
				(0xf45d, None),
				(0xb775, None),
				(0x8082, None),
				(0x9082, None),
			]),

			// zcb.s
			("
				lbu x8,2(x8)
				lbu x8,(x15)
				lhu x8,2(x8)
				lhu x8,(x15)
				lh x8,2(x8)
				lh x8,(x15)
				sb x8,2(x8)
				sb x8,(x15)
				sh x8,2(x8)
				sh x8,(x15)
				zext.b x8,x8
				zext.b x15,x15
				not x8,x8
				not x15,x15
			", &[
				(0x8020, None),
				(0x8380, None),
				(0x8420, None),
				(0x8780, None),
				(0x8460, None),
				(0x87c0, None),
				(0x8820, None),
				(0x8b80, None),
				(0x8c20, None),
				(0x8f80, None),
				(0x9c61, None),
				(0x9fe1, None),
				(0x9c75, None),
				(0x9ff5, None),
			]),

			// zihintntl.s
			//
			// gas compresses `c.ntl.*` and `c.add x0, *` but does not compress `add x0, x0, *`.
			// We treat `ntl.*` as a pseudo-instruction and don't differentiate between `add` and `c.add`,
			// so we don't compress them.
			("
				ntl.p1
				sb s11, 8(t0)
				ntl.pall
				sb s11, 10(t0)
				ntl.s1
				sb s11, 12(t0)
				ntl.all
				sb s11, 14(t0)
			", &[
				(0x900a, None),
				(0x8423, Some(0x01b2)),
				(0x900e, None),
				(0x8523, Some(0x01b2)),
				(0x9012, None),
				(0x8623, Some(0x01b2)),
				(0x9016, None),
				(0x8723, Some(0x01b2)),
			]),

			// zihintntl-base.s
			//
			// gas compresses `c.ntl.*` and `c.add x0, *` but does not compress `add x0, x0, *`.
			// We treat `ntl.*` as a pseudo-instruction and don't differentiate between `add` and `c.add`,
			// so we compress them.
			("
				add x0, x0, x2
				sb s11, 8(t0)
				add x0, x0, x3
				sb s11, 10(t0)
				add x0, x0, x4
				sb s11, 12(t0)
				add x0, x0, x5
				sb s11, 14(t0)
			", &[
				(0x900a, None),
				(0x8423, Some(0x01b2)),
				(0x900e, None),
				(0x8523, Some(0x01b2)),
				(0x9012, None),
				(0x8623, Some(0x01b2)),
				(0x9016, None),
				(0x8723, Some(0x01b2)),
			]),
		];
		for &(input, expected) in TESTS {
			const SUPPORTED_EXTENSIONS: crate::SupportedExtensions = crate::SupportedExtensions::RV32C_ZCB;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), SUPPORTED_EXTENSIONS)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, SUPPORTED_EXTENSIONS).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn gas_uncompressed64() {
		static TESTS: &[(&str, &[(u16, u16)])] = &[
			// b-ext-64.s
			("
				sh1add.uw a0, a1, a2
				sh2add.uw a0, a1, a2
				sh3add.uw a0, a1, a2
				add.uw a0, a1, a2
				zext.w a0, a1
				slli.uw a0, a1, 2
			", &[
				(0xa53b, 0x20c5),
				(0xc53b, 0x20c5),
				(0xe53b, 0x20c5),
				(0x853b, 0x08c5),
				(0x853b, 0x0805),
				(0x951b, 0x0825),
			]),

			// csr.s
			("
				# User Counter/Timers
				csrr a0, cycle
				csrw cycle, a1
				csrr a0, time
				csrw time, a1
				csrr a0, instret
				csrw instret, a1
				csrr a0, misa
				csrw misa, a1
			", &[
				(0x2573, 0xc000),
				(0x9073, 0xc005),
				(0x2573, 0xc010),
				(0x9073, 0xc015),
				(0x2573, 0xc020),
				(0x9073, 0xc025),
				(0x2573, 0x3010),
				(0x9073, 0x3015),
			]),

			// csr-insns-pseudo.s
			("
				# i-ext
				csrr t0, 0x0
				csrw 0x0, t0
				csrs 0x0, t0
				csrc 0x0, t0
				csrwi 0x0, 31
				csrsi 0x0, 31
				csrci 0x0, 31

				rdcycle t0
				rdtime t0
				rdinstret t0
			", &[
				(0x22f3, 0x0000),
				(0x9073, 0x0002),
				(0xa073, 0x0002),
				(0xb073, 0x0002),
				(0xd073, 0x000f),
				(0xe073, 0x000f),
				(0xf073, 0x000f),
				(0x22f3, 0xc000),
				(0x22f3, 0xc010),
				(0x22f3, 0xc020),
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
				# C.ADDI
				lui t6, 0xffff9

				# ADDIW (not compressed)
				lui s6, 0xffff8
				addiw s7, s6, -24
				# C.ADDIW
				lui s8, 0xffff7

				# Use addresses relative to gp
				lw t0, 0x400(gp)
				lw t1, -0x400(gp)
				# Use addresses relative to zero
				lw t2, 0x100(zero)
				lw t3, -0x800(zero)
				jalr t4, 0x104(zero)
				jalr t5, -0x7fc(zero)
			", &[
				(0xf2b7, 0xffff),
				(0xa903, 0xffc2),
				(0xe337, 0xffff),
				(0x2c23, 0xff33),
				(0xd3b7, 0xffff),
				(0x80e7, 0x0003),
				(0xce37, 0xffff),
				(0x00e7, 0xff4e),
				(0xbeb7, 0xffff),
				(0x8a67, 0x000e),
				(0xaf37, 0xffff),
				(0x0a93, 0xff0f),
				(0x9fb7, 0xffff),
				(0x8b37, 0xffff),
				(0x0b9b, 0xfe8b),
				(0x7c37, 0xffff),
				(0xa283, 0x4001),
				(0xa303, 0xc001),
				(0x2383, 0x1000),
				(0x2e03, 0x8000),
				(0x0ee7, 0x1040),
				(0x0f67, 0x8040),
			]),
		];
		for &(input, expected) in TESTS {
			let supported_extensions: crate::SupportedExtensions = crate::SupportedExtensions::RV64I | crate::SupportedExtensions::ZBA;

			std::eprintln!("{input}");

			let expected = expected.iter().map(|&(lo, hi)| (lo, Some(hi))).collect::<Vec<_>>();
			let actual =
				super::parse_program(input.lines().map(str::as_bytes), supported_extensions)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, supported_extensions).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}

	#[test]
	fn gas_compressed64() {
		static TESTS: &[(&str, &[(u16, Option<u16>)])] = &[
			// c-ld.s
			("
				ld a0, (a0)  # 'Cl'
				ld a0, 0(a0) # 'Cl'
				sd a0, (a0)  # 'Cl'
				sd a0, 0(a0) # 'Cl'
				ld a0, (sp)  # 'Cn'
				ld a0, 0(sp) # 'Cn'
				sd a0, (sp)  # 'CN'
				sd a0, 0(sp) # 'CN'
			", &[
				(0x6108, None),
				(0x6108, None),
				(0xe108, None),
				(0xe108, None),
				(0x6502, None),
				(0x6502, None),
				(0xe02a, None),
				(0xe02a, None),
			]),

			// c-zero-imm-64.s
			("
				# These are valid instructions.
				addiw a6,a6,0
				addiw a7,a7,0
			", &[
				(0x2801, None),
				(0x2881, None),
			]),

			// dis-addr-addiw.s
			("
				# _start + 0x00
				auipc t0, 0
				addiw t1, t0, 0x18
				# _start + 0x08
				auipc t2, 0
				addiw t3, t2, 0x1c

				# _start + 0x10
				auipc t4, 0
				addiw t4, t4, 0x0c
				# _start + 0x16
				auipc t5, 0
				addiw t5, t5, 0x12
			", &[
				(0x0297, Some(0x0000)),
				(0x831b, Some(0x0182)),
				(0x0397, Some(0x0000)),
				(0x8e1b, Some(0x01c3)),
				(0x0e97, Some(0x0000)),
				(0x2eb1, None),
				(0x0f17, Some(0x0000)),
				(0x2f49, None),
			]),

			// dis-addr-overflow.s
			("
				addi t6, t6, -20

				addiw s8, s8, -28

				# Use addresses relative to gp
				lw t0, 0x400(gp)
				lw t1, -0x400(gp)
				# Use addresses relative to zero
				lw t2, 0x100(zero)
				lw t3, -0x800(zero)
				jalr t4, 0x104(zero)
				jalr t5, -0x7fc(zero)
			", &[
				(0x1fb1, None),
				(0x3c11, None),
				(0xa283, Some(0x4001)),
				(0xa303, Some(0xc001)),
				(0x2383, Some(0x1000)),
				(0x2e03, Some(0x8000)),
				(0x0ee7, Some(0x1040)),
				(0x0f67, Some(0x8040)),
			]),

			// li64.s
			/*
			// TODO: Support li for large constants
			("
				li  a0, 0x8001
				li  a0, 0x1f01
				li  a0, 0x12345001
				li  a0, 0xf2345001
				li  a0, 0xf12345001
				li  a0, 0xff00ff00ff001f01
				li  a0, 0x7ffffffff2345001
				li  a0, 0x7f0f243ff2345001
			", &[
				(0x6521, None),
				(0x2505, None),
				(0x6509, None),
				(0x051b, Some(0xf015)),
				(0x5537, Some(0x1234)),
				(0x2505, None),
				(0x2537, Some(0x000f)),
				(0x051b, Some(0x3455)),
				(0x0532, None),
				(0x0505, None),
				(0x2537, Some(0x00f1)),
				(0x051b, Some(0x3455)),
				(0x0532, None),
				(0x0505, None),
				(0x0537, Some(0xff01)),
				(0x051b, Some(0xf015)),
				(0x054e, None),
				(0x0513, Some(0x8015)),
				(0x0536, None),
				(0x0513, Some(0xf015)),
				(0x051b, Some(0x0010)),
				(0x151a, None),
				(0x1565, None),
				(0x0536, None),
				(0x0513, Some(0x3455)),
				(0x0532, None),
				(0x0505, None),
				(0x4537, Some(0x01fc)),
				(0x051b, Some(0xc915)),
				(0x0536, None),
				(0x1565, None),
				(0x0536, None),
				(0x0513, Some(0x3455)),
				(0x0532, None),
				(0x0505, None),
			]),
			*/

			// zca.s
			("
				li x1, 31
				li x2, 0
				lui x1, 1
				lui x3, 31
				lw x8, (x9)
				lw x9, 32(x10)
				lw a0, (sp)
				c.lwsp x1, (x2)
				ld x8, (x15)
				ld x9, 8(x10)
				ld a0,(sp)
				c.ldsp x1, (sp)
				sw x8, (x9)
				sw x9, 32(x10)
				sw a0, (sp)
				c.swsp x1, (x2)
				sd x8, (x15)
				sd x9, 8(x10)
				sd a0, (sp)
				c.sdsp x1, (sp)
				addi x0, x0, 0
				nop
				add x1, x1, x2
				addi a1, a1, 31
				addi x2, x2, 0
				addiw a1, a1, 31
				addiw x2, x2, 0
				addi4spn x8, x2, 4
				addi16sp x2, 32
				addw x8, x8, x9
				sub x8, x8, x9
				subw x8, x8, x9
				and x8, x8, x9
				andi x8, x8, 31
				or x8, x8, x9
				xor x8, x8, x9
				mv x0, x1
				slli x0, x0, 1
				beqz x8, -80
				bnez x8, -82
				j -84
				jr ra
				jalr ra
			", &[
				(0x40fd, None),
				(0x4101, None),
				(0x6085, None),
				(0x61fd, None),
				(0x4080, None),
				(0x5104, None),
				(0x4502, None),
				(0x4082, None),
				(0x6380, None),
				(0x6504, None),
				(0x6502, None),
				(0x6082, None),
				(0xc080, None),
				(0xd104, None),
				(0xc02a, None),
				(0xc006, None),
				(0xe380, None),
				(0xe504, None),
				(0xe02a, None),
				(0xe006, None),
				(0x0001, None),
				(0x0001, None),
				(0x908a, None),
				(0x05fd, None),
				// gas wants this to be `(0x0101, None)` because the original is `c.addi` and `c.addi _, 0` is a HINT.
				//
				// We don't differentiate between `addi` and `c.addi` so we compress it as `c.mv` instead.
				(0x810a, None),
				(0x25fd, None),
				(0x2101, None),
				(0x0040, None),
				(0x6105, None),
				(0x9c25, None),
				(0x8c05, None),
				(0x9c05, None),
				(0x8c65, None),
				(0x887d, None),
				(0x8c45, None),
				(0x8c25, None),
				// gas wants this to be `(0x8006, None)` because the original is `c.mv` which expands to `add x0, x0, x1`,
				// and `add x0, x0, !x0` is a HINT.
				//
				// We don't differentiate between `mv` and `c.mv` so we treat the input as `addi x0, x0, x1`
				(0x0001, None),
				// gas wants this to be `(0x0006, None)` because the original is `c.slli` and `slli x0, _` is a HINT.
				//
				// We don't differentiate between `slli` and `c.slli` so we don't compress it.
				(0x1013, Some(0x0010)),
				(0xd845, None),
				(0xf45d, None),
				(0xb775, None),
				(0x8082, None),
				(0x9082, None),
			]),

			// zcb.s
			("
				zext.w x8,x8
				zext.w x15,x15
			", &[
				(0x9c71, None),
				(0x9ff1, None),
			]),
		];
		for &(input, expected) in TESTS {
			let supported_extensions: crate::SupportedExtensions = crate::SupportedExtensions::RV64C_ZCB | crate::SupportedExtensions::ZBA;

			std::eprintln!("{input}");

			let actual =
				super::parse_program(input.lines().map(str::as_bytes), supported_extensions)
				.map(|i| -> Result<_, String> {
					let i = i.map_err(|err| err.to_string())?;
					let encoded = crate::Instruction::encode(i, supported_extensions).map_err(|err| err.to_string())?;
					Ok(encoded)
				})
				.collect::<Result<Vec<_>, _>>()
				.unwrap();
			assert_eq!(expected[..], actual[..]);
		}
	}
}
