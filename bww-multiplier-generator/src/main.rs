//! Verilog generator for a Baugh-Wooley multiplier, modified to support both signed and unsigned inputs,
//! and the partial products are summed using a Wallace tree.
//!
//! Example:
//!
//!     cargo run -p bww-multiplier-generator -- 8 >./tc/sv/bwww_multiplier.sv

use std::collections::{BinaryHeap, BTreeMap, VecDeque};

use num_bigint::{BigInt, BigUint};
use num_traits::{One as _, Zero as _};

fn main() {
	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let width = parse_args(args, &argv0);

	let width_minus_one = width - 1;

	println!("module bww_multiplier (");
	println!("\tinput bit[{width_minus_one}:0] a,");
	println!("\tinput bit a_is_signed,");
	println!("\tinput bit[{width_minus_one}:0] b,");
	println!("\tinput bit b_is_signed,");
	println!();
	println!("\toutput bit[{width_minus_one}:0] mul,");
	println!("\toutput bit[{width_minus_one}:0] mulh");
	println!(");");

	let mut products = BTreeMap::<_, BigUint>::new();

	for b in 0_u8..(width * 2) {
		for a in 0_u8..(width * 2) {
			let pos = u64::from(a) + u64::from(b);
			if pos >= u64::from(width) * 2 { break; }

			let a = if a < width { InputWire::Index(a) } else { InputWire::SignExtended(width - 1) };
			let b = if b < width { InputWire::Index(b) } else { InputWire::SignExtended(width - 1) };
			*products.entry((a, b)).or_default() += BigUint::one() << pos;
		}
	}

	let mut cols: VecDeque<_> = vec![BinaryHeap::new(); usize::from(width) * 2].into();
	let mut constant = BigInt::ZERO;
	for ((a, b), mut count) in products {
		let mut col_i = 0_u8;
		while let Some(col) = cols.get_mut(usize::from(col_i)) {
			let Some(trailing_zeros) = count.trailing_zeros() else { break; };
			if trailing_zeros > 0 {
				col_i += u8::try_from(trailing_zeros).unwrap();
				count >>= trailing_zeros;
				continue;
			}

			let delay =
				(match a { InputWire::Index(_) => 0, InputWire::SignExtended(_) => 1 }) +
				(match b { InputWire::Index(_) => 0, InputWire::SignExtended(_) => 1 }) +
				1;

			let trailing_ones = count.trailing_ones();
			if trailing_ones == 1 {
				col.push(std::cmp::Reverse(Wire { delay, kind: WireKind::InputsAnd { a, b } }));
				count -= 1_u8;
			}
			else {
				col.push(std::cmp::Reverse(Wire { delay, kind: WireKind::InputsNand { a, b } }));
				constant -= BigInt::one() << col_i;
				count += 1_u8;
			}
		}
	}

	for col in &mut cols {
		if constant.is_zero() {
			break;
		}
		if constant.bit(0) {
			col.push(std::cmp::Reverse(Wire { delay: 0, kind: WireKind::One }));
		}
		constant >>= 1;
	}

	let mut adder_next_id = 0_u64;
	let mut outputs = vec![];

	while let Some(mut col) = cols.pop_front() {
		loop {
			let std::cmp::Reverse(a) = col.pop().unwrap();

			let Some(std::cmp::Reverse(b)) = col.pop() else {
				outputs.push(a);
				break;
			};

			let Some(std::cmp::Reverse(c)) = col.pop() else {
				let adder_id = adder_next_id;
				adder_next_id += 1;

				println!("\twire s{adder_id}, c{adder_id};");
				println!("\thalf_adder adder{adder_id}({a}, {b}, s{adder_id}, c{adder_id});");

				outputs.push(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Sum { adder_id } });

				if let Some(cols) = cols.front_mut() {
					cols.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 1, kind: WireKind::Carry { adder_id } }));
				}

				break;
			};

			match (&a.kind, &b.kind, &c.kind) {
				(WireKind::One, WireKind::One, WireKind::One) => {
					col.push(std::cmp::Reverse(Wire { delay: 0, kind: WireKind::One }));
					if let Some(col) = cols.front_mut() {
						col.push(std::cmp::Reverse(Wire { delay: 0, kind: WireKind::One }));
					}
				},

				(WireKind::One, WireKind::One, _) => {
					col.push(std::cmp::Reverse(c));
					if let Some(col) = cols.front_mut() {
						col.push(std::cmp::Reverse(Wire { delay: 0, kind: WireKind::One }));
					}
				},

				(WireKind::One, _, _) => {
					let adder_id = adder_next_id;
					adder_next_id += 1;

					println!("\twire s{adder_id}, c{adder_id};");
					println!("\thalf_adder_plus_one adder{adder_id} ({b}, {c}, s{adder_id}, c{adder_id});");

					col.push(std::cmp::Reverse(Wire { delay: b.delay.max(c.delay) + 2, kind: WireKind::Sum { adder_id } }));

					if let Some(col) = cols.front_mut() {
						col.push(std::cmp::Reverse(Wire { delay: b.delay.max(c.delay) + 1, kind: WireKind::Carry { adder_id } }));
					}
				},

				(_, _, _) => {
					let adder_id = adder_next_id;
					adder_next_id += 1;

					println!("\twire s{adder_id}, c{adder_id};");
					println!("\tfull_adder adder{adder_id} ({a}, {b}, {c}, s{adder_id}, c{adder_id});");

					col.push(std::cmp::Reverse(Wire { delay: (a.delay.max(b.delay) + 2).max(c.delay) + 2, kind: WireKind::Sum { adder_id } }));
					if let Some(col) = cols.front_mut() {
						col.push(std::cmp::Reverse(Wire { delay: (a.delay.max(b.delay) + 1).max(c.delay) + 2, kind: WireKind::Carry { adder_id } }));
					}
				},
			}
		}
	}

	let mut first = true;
	print!("\tassign {{mulh, mul}} = {{");
	for wire in outputs.into_iter().rev() {
		if first {
			first = false;
		}
		else {
			print!(",");
		}
		print!("\n\t\t{wire}");
	}
	println!("\n\t}};");

	println!("endmodule");
	println!();
	println!("module half_adder (");
	println!("\tinput bit a,");
	println!("\tinput bit b,");
	println!("\toutput bit sum,");
	println!("\toutput bit carry");
	println!(");");
	println!("\tassign {{carry, sum}} = {{1'b0, a}} + {{1'b0, b}};");
	println!("endmodule");
	println!();
	println!("module half_adder_plus_one (");
	println!("\tinput bit a,");
	println!("\tinput bit b,");
	println!("\toutput bit sum,");
	println!("\toutput bit carry");
	println!(");");
	println!("\tassign {{carry, sum}} = {{1'b0, a}} + {{1'b0, b}} + 2'b01;");
	println!("endmodule");
	println!();
	println!("module full_adder (");
	println!("\tinput bit a,");
	println!("\tinput bit b,");
	println!("\tinput bit c,");
	println!("\toutput bit sum,");
	println!("\toutput bit carry");
	println!(");");
	println!("\tassign {{carry, sum}} = {{1'b0, a}} + {{1'b0, b}} + {{1'b0, c}};");
	println!("endmodule");
	println!();
	println!("/*module test_bww_multiplier;");
	println!("\tbit[{width_minus_one}:0] a;");
	println!("\tbit a_is_signed;");
	println!("\tbit[{width_minus_one}:0] b;");
	println!("\tbit b_is_signed;");
	println!("\twire[{width_minus_one}:0] mul;");
	println!("\twire[{width_minus_one}:0] mulh;");
	println!("\tbww_multiplier bww_multiplier_module (");
	println!("\t\ta, a_is_signed,");
	println!("\t\tb, b_is_signed,");
	println!("\t\tmul, mulh");
	println!("\t);");
	println!();
	println!("\tinitial begin");
	println!("\t\ta = -{width}'d1;");
	println!("\t\ta_is_signed = '0;");
	println!("\t\tb = -{width}'d1;");
	println!("\t\tb_is_signed = '0;");
	println!("\t\t#1");
	println!("\t\tassert(mul == {width}'d1);");
	println!("\t\tassert(mulh == -{width}'d2);");
	println!();
	println!("\t\ta = -{width}'d1;");
	println!("\t\ta_is_signed = '1;");
	println!("\t\tb = -{width}'d1;");
	println!("\t\tb_is_signed = '0;");
	println!("\t\t#1");
	println!("\t\tassert(mul == {width}'d1);");
	println!("\t\tassert(mulh == -{width}'d1);");
	println!();
	println!("\t\ta = -{width}'d1;");
	println!("\t\ta_is_signed = '0;");
	println!("\t\tb = -{width}'d1;");
	println!("\t\tb_is_signed = '1;");
	println!("\t\t#1");
	println!("\t\tassert(mul == {width}'d1);");
	println!("\t\tassert(mulh == -{width}'d1);");
	println!();
	println!("\t\ta = -{width}'d1;");
	println!("\t\ta_is_signed = '1;");
	println!("\t\tb = -{width}'d1;");
	println!("\t\tb_is_signed = '1;");
	println!("\t\t#1");
	println!("\t\tassert(mul == {width}'d1);");
	println!("\t\tassert(mulh == {width}'d0);");
	println!("\tend");
	println!("endmodule*/");
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct Wire {
	delay: u64,
	kind: WireKind,
}

impl PartialOrd for Wire {
	fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
		Some(self.cmp(other))
	}
}

impl Ord for Wire {
	fn cmp(&self, other: &Self) -> std::cmp::Ordering {
		self.delay.cmp(&other.delay).then(self.kind.cmp(&other.kind))
	}
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum WireKind {
	One,
	InputsAnd { a: InputWire, b: InputWire },
	InputsNand { a: InputWire, b: InputWire },
	Sum { adder_id: u64 },
	Carry { adder_id: u64 },
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum InputWire {
	Index(u8),
	SignExtended(u8),
}

impl std::fmt::Display for Wire {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		match &self.kind {
			WireKind::One => f.write_str("1'b1"),

			WireKind::InputsAnd { a, b } => {
				match a {
					InputWire::Index(a) => write!(f, "a[{a}]")?,
					InputWire::SignExtended(a) => write!(f, "a[{a}] & a_is_signed")?,
				}
				f.write_str(" & ")?;
				match b {
					InputWire::Index(b) => write!(f, "b[{b}]")?,
					InputWire::SignExtended(b) => write!(f, "b[{b}] & b_is_signed")?,
				}
				Ok(())
			},

			WireKind::InputsNand { a, b } => {
				f.write_str("~(")?;
				match a {
					InputWire::Index(a) => write!(f, "a[{a}]")?,
					InputWire::SignExtended(a) => write!(f, "a[{a}] & a_is_signed")?,
				}
				f.write_str(" & ")?;
				match b {
					InputWire::Index(b) => write!(f, "b[{b}]")?,
					InputWire::SignExtended(b) => write!(f, "b[{b}] & b_is_signed")?,
				}
				f.write_str(")")?;
				Ok(())
			},

			WireKind::Sum { adder_id } => write!(f, "s{adder_id}"),

			WireKind::Carry { adder_id } => write!(f, "c{adder_id}"),
		}
	}
}

impl PartialOrd for WireKind {
	fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
		Some(self.cmp(other))
	}
}

impl Ord for WireKind {
	fn cmp(&self, other: &Self) -> std::cmp::Ordering {
		#[allow(clippy::match_same_arms)]
		match (self, other) {
			(Self::One, Self::One) => std::cmp::Ordering::Equal,
			(Self::One, _) => std::cmp::Ordering::Less,
			(_, Self::One) => std::cmp::Ordering::Greater,

			(Self::InputsAnd { a: a1, b: b1 }, Self::InputsAnd { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::InputsAnd { a: a1, b: b1 }, Self::InputsNand { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Less),

			(Self::InputsAnd { .. }, _) => std::cmp::Ordering::Less,

			(Self::InputsNand { a: a1, b: b1 }, Self::InputsAnd { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Greater),

			(Self::InputsNand { a: a1, b: b1 }, Self::InputsNand { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::InputsNand { .. }, _) => std::cmp::Ordering::Less,

			(Self::Sum { .. }, Self::InputsAnd { .. } | Self::InputsNand { .. }) =>
				std::cmp::Ordering::Greater,

			(Self::Sum { adder_id: id1 }, Self::Sum { adder_id: id2 }) =>
				id1.cmp(id2),

			(Self::Sum { adder_id: id1 }, Self::Carry { adder_id: id2 }) =>
				id1.cmp(id2).then(std::cmp::Ordering::Less),

			(Self::Carry { .. }, Self::InputsAnd { .. } | Self::InputsNand { .. }) =>
				std::cmp::Ordering::Greater,

			(Self::Carry { adder_id: id1 }, Self::Carry { adder_id: id2 }) =>
				id1.cmp(id2),

			(Self::Carry { adder_id: id1 }, Self::Sum { adder_id: id2 }) =>
				id1.cmp(id2).then(std::cmp::Ordering::Greater),
		}
	}
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> u8 {
	let mut width = None;

	for opt in &mut args {
		match opt.to_str() {
			Some("--help") => {
				write_usage(std::io::stdout(), argv0);
				std::process::exit(0);
			},

			Some(value) if width.is_none() => match value.parse() {
				Ok(value) => width = Some(value),
				Err(_) => write_usage_and_crash(argv0),
			},

			_ => write_usage_and_crash(argv0),
		}
	}

	let None = args.next() else { write_usage_and_crash(argv0); };

	let Some(width) = width else { write_usage_and_crash(argv0); };
	width
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} <width>", argv0.to_string_lossy());
}
