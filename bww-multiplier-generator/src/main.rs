//! Verilog generator for a Baugh-Wooley multiplier, modified to support both signed and unsigned inputs,
//! and the partial products are summed using a Wallace tree.
//!
//! Example:
//!
//!     cargo run -p bww-multiplier-generator -- --mulh 8 >./tc/sv/bww_multiplier.sv

use num_traits::{One as _, Zero as _};

fn main() {
	let mut args = std::env::args_os();
	let argv0 = args.next().unwrap_or_else(|| env!("CARGO_BIN_NAME").into());
	let (fma, mulh, width) = parse_args(args, &argv0);

	let width_minus_one = width - 1;

	println!("module bww_multiplier (");

	println!("\tinput bit[{width_minus_one}:0] a,");
	if mulh {
		println!("\tinput bit a_is_signed,");
	}

	println!("\tinput bit[{width_minus_one}:0] b,");
	if mulh {
		println!("\tinput bit b_is_signed,");
	}

	if fma {
		println!("\tinput bit[{width_minus_one}:0] c,");
	}

	println!();
	print!("\toutput bit[{width_minus_one}:0] mul");

	if mulh {
		print!(",\n\toutput bit[{width_minus_one}:0] mulh");
	}

	println!("\n);");

	let mut products = std::collections::BTreeMap::<_, num_bigint::BigUint>::new();

	for b in 0_u8..(if mulh { width * 2 } else { width }) {
		for a in 0_u8..(if mulh { width * 2 } else { width }) {
			let pos = u64::from(a) + u64::from(b);
			if pos >= u64::from(width) * 2 { break; }

			let a = if a < width { InputWire::Index(a) } else { InputWire::SignExtended(width - 1) };
			let b = if b < width { InputWire::Index(b) } else { InputWire::SignExtended(width - 1) };
			*products.entry((a, b)).or_default() += num_bigint::BigUint::one() << pos;
		}
	}

	let mut cols: std::collections::VecDeque<_> = vec![std::collections::BinaryHeap::new(); usize::from(width) * if mulh { 2 } else { 1 }].into();
	let mut constant = num_bigint::BigInt::ZERO;
	for ((a, b), mut count) in products {
		let mut col_i = 0_u8;
		while let Some(col) = cols.get_mut(usize::from(col_i)) {
			let Some(trailing_zeros) = count.trailing_zeros() else { break; };
			if trailing_zeros > 0 {
				col_i += u8::try_from(trailing_zeros).unwrap();
				count >>= trailing_zeros;
				continue;
			}

			let delay = a.delay().max(b.delay()) + 1;

			let trailing_ones = count.trailing_ones();
			if trailing_ones == 1 {
				col.push(std::cmp::Reverse(Wire { delay, kind: WireKind::InputsAnd { a, b } }));
				count -= 1_u8;
			}
			else {
				col.push(std::cmp::Reverse(Wire { delay, kind: WireKind::InputsNand { a, b } }));
				constant -= num_bigint::BigInt::one() << col_i;
				count += 1_u8;
			}
		}
	}

	if fma {
		for (col_i, col) in cols.iter_mut().enumerate() {
			col.push(std::cmp::Reverse(Wire {
				delay: 0,
				kind: WireKind::Addend { i: InputWire::Index(u8::try_from(col_i).unwrap().min(width - 1)) }
			}));
		}
	}

	for col in &mut cols {
		if constant.is_zero() {
			break;
		}
		if constant.bit(0) {
			col.push(std::cmp::Reverse(Wire { delay: u64::MAX, kind: WireKind::One }));
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
				if let Some(next_col) = cols.front_mut() {
					let adder_id = adder_next_id;
					adder_next_id += 1;

					println!("\twire s{adder_id}, c{adder_id};");
					println!("\thalf_adder adder{adder_id}(.a({a}), .b({b}), .sum(s{adder_id}), .carry(c{adder_id}));");

					outputs.push(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Sum { adder_id } });

					next_col.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 1, kind: WireKind::Carry { adder_id } }));
				}
				else {
					outputs.push(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Xor { a: Box::new(a.kind), b: Box::new(b.kind) } });
				}

				break;
			};

			match (&a.kind, &b.kind, &c.kind) {
				(_, WireKind::One, WireKind::One) => {
					col.push(std::cmp::Reverse(a));
					if let Some(next_col) = cols.front_mut() {
						next_col.push(std::cmp::Reverse(Wire { delay: u64::MAX, kind: WireKind::One }));
					}
				},

				(_, _, WireKind::One) => {
					let d = col.pop();
					if let Some(std::cmp::Reverse(Wire { kind: WireKind::One, .. })) = &d {
						col.push(std::cmp::Reverse(a));
						col.push(std::cmp::Reverse(b));
						if let Some(next_col) = cols.front_mut() {
							next_col.push(std::cmp::Reverse(Wire { delay: u64::MAX, kind: WireKind::One }));
						}
					}
					else {
						assert_eq!(d, None, "cannot have anything greater than WireKind::One");

						if let Some(next_col) = cols.front_mut() {
							let adder_id = adder_next_id;
							adder_next_id += 1;

							println!("\twire s{adder_id}, c{adder_id};");
							println!("\thalf_adder_plus_one adder{adder_id} (.a({a}), .b({b}), .sum(s{adder_id}), .carry(c{adder_id}));");

							col.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Sum { adder_id } }));
							next_col.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 1, kind: WireKind::Carry { adder_id } }));
						}
						else {
							col.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Xnor { a: Box::new(b.kind), b: Box::new(c.kind) } }));
						}
					}
				},

				(_, _, _) => {
					if let Some(next_col) = cols.front_mut() {
						let adder_id = adder_next_id;
						adder_next_id += 1;

						println!("\twire s{adder_id}, c{adder_id};");
						println!("\tfull_adder adder{adder_id} (.a({a}), .b({b}), .c({c}), .sum(s{adder_id}), .carry(c{adder_id}));");

						col.push(std::cmp::Reverse(Wire { delay: (a.delay.max(b.delay) + 2).max(c.delay) + 2, kind: WireKind::Sum { adder_id } }));
						next_col.push(std::cmp::Reverse(Wire { delay: (a.delay.max(b.delay) + 1).max(c.delay) + 2, kind: WireKind::Carry { adder_id } }));
					}
					else {
						col.push(std::cmp::Reverse(c));
						col.push(std::cmp::Reverse(Wire { delay: a.delay.max(b.delay) + 2, kind: WireKind::Xor { a: Box::new(a.kind), b: Box::new(b.kind) } }));
					}
				},
			}
		}
	}

	let mut first = true;
	if mulh {
		print!("\tassign {{mulh, mul}} = {{");
	}
	else {
		print!("\tassign mul = {{");
	}
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
	println!("\tassign {{carry, sum}} = 2'(a) + 2'(b);");
	println!("endmodule");
	println!();
	println!("module half_adder_plus_one (");
	println!("\tinput bit a,");
	println!("\tinput bit b,");
	println!("\toutput bit sum,");
	println!("\toutput bit carry");
	println!(");");
	println!("\tassign {{carry, sum}} = 2'(a) + 2'(b) + 2'b01;");
	println!("endmodule");
	println!();
	println!("module full_adder (");
	println!("\tinput bit a,");
	println!("\tinput bit b,");
	println!("\tinput bit c,");
	println!("\toutput bit sum,");
	println!("\toutput bit carry");
	println!(");");
	println!("\tassign {{carry, sum}} = 2'(a) + 2'(b) + 2'(c);");
	println!("endmodule");

	println!();
	println!("`ifdef TESTING");
	println!("module test_bww_multiplier;");
	println!("\tbit[{width_minus_one}:0] a;");
	if mulh {
		println!("\tbit a_is_signed;");
	}
	println!("\tbit[{width_minus_one}:0] b;");
	if mulh {
		println!("\tbit b_is_signed;");
	}
	if fma {
		println!("\tbit[{width_minus_one}:0] c;");
	}
	println!("\twire[{width_minus_one}:0] mul;");
	if mulh {
		println!("\twire[{width_minus_one}:0] mulh;");
	}
	println!("\tbww_multiplier bww_multiplier_module (");
	print!("\t\t.a(a),");
	if mulh {
		print!(" .a_is_signed(a_is_signed),");
	}
	print!("\n\t\t.b(b),");
	if mulh {
		print!(" .b_is_signed(b_is_signed),");
	}
	println!();
	if fma {
		println!("\t\t.c(c),");
	}
	print!("\t\t.mul(mul)");
	if mulh {
		print!(", .mulh(mulh)");
	}
	println!("\n\t);");
	println!();
	println!("\tinitial begin");

	println!("\t\ta = -{width}'d1;");
	if mulh {
		println!("\t\ta_is_signed = '0;");
	}
	println!("\t\tb = -{width}'d1;");
	if mulh {
		println!("\t\tb_is_signed = '0;");
	}
	if fma {
		println!("\t\tc = {width}'d0;");
	}
	println!("\t\t#1");
	println!("\t\tassert(mul == {width}'d1) else $fatal;");
	if mulh {
		println!("\t\tassert(mulh == -{width}'d2) else $fatal;");
	}

	if fma {
		println!();
		println!("\t\ta = -{width}'d1;");
		if mulh {
			println!("\t\ta_is_signed = '0;");
		}
		println!("\t\tb = -{width}'d1;");
		if mulh {
			println!("\t\tb_is_signed = '0;");
		}
		println!("\t\tc = -{width}'d1;");
		println!("\t\t#1");
		println!("\t\tassert(mul == {width}'d0) else $fatal;");
		if mulh {
			println!("\t\tassert(mulh == -{width}'d2) else $fatal;");
		}
	}

	if mulh {
		println!();
		println!("\t\ta = -{width}'d1;");
		println!("\t\ta_is_signed = '1;");
		println!("\t\tb = -{width}'d1;");
		println!("\t\tb_is_signed = '0;");
		if fma {
			println!("\t\tc = {width}'d0;");
		}
		println!("\t\t#1");
		println!("\t\tassert(mul == {width}'d1) else $fatal;");
		println!("\t\tassert(mulh == -{width}'d1) else $fatal;");

		if fma {
			println!();
			println!("\t\ta = -{width}'d1;");
			println!("\t\ta_is_signed = '1;");
			println!("\t\tb = -{width}'d1;");
			println!("\t\tb_is_signed = '0;");
			println!("\t\tc = -{width}'d1;");
			println!("\t\t#1");
			println!("\t\tassert(mul == {width}'d0) else $fatal;");
			println!("\t\tassert(mulh == -{width}'d1) else $fatal;");
		}

		println!();
		println!("\t\ta = -{width}'d1;");
		println!("\t\ta_is_signed = '0;");
		println!("\t\tb = -{width}'d1;");
		println!("\t\tb_is_signed = '1;");
		if fma {
			println!("\t\tc = {width}'d0;");
		}
		println!("\t\t#1");
		println!("\t\tassert(mul == {width}'d1) else $fatal;");
		println!("\t\tassert(mulh == -{width}'d1) else $fatal;");

		if fma {
			println!();
			println!("\t\ta = -{width}'d1;");
			println!("\t\ta_is_signed = '0;");
			println!("\t\tb = -{width}'d1;");
			println!("\t\tb_is_signed = '1;");
			println!("\t\tc = -{width}'d1;");
			println!("\t\t#1");
			println!("\t\tassert(mul == {width}'d0) else $fatal;");
			println!("\t\tassert(mulh == -{width}'d1) else $fatal;");
		}

		println!();
		println!("\t\ta = -{width}'d1;");
		println!("\t\ta_is_signed = '1;");
		println!("\t\tb = -{width}'d1;");
		println!("\t\tb_is_signed = '1;");
		if fma {
			println!("\t\tc = {width}'d0;");
		}
		println!("\t\t#1");
		println!("\t\tassert(mul == {width}'d1) else $fatal;");
		println!("\t\tassert(mulh == {width}'d0) else $fatal;");

		if fma {
			println!();
			println!("\t\ta = -{width}'d1;");
			println!("\t\ta_is_signed = '1;");
			println!("\t\tb = -{width}'d1;");
			println!("\t\tb_is_signed = '1;");
			println!("\t\tc = -{width}'d1;");
			println!("\t\t#1");
			println!("\t\tassert(mul == {width}'d0) else $fatal;");
			println!("\t\tassert(mulh == {width}'d0) else $fatal;");
		}
	}

	println!("\tend");
	println!("endmodule");
	println!("`endif");
}

#[derive(Clone, Debug, Eq, PartialEq)]
struct Wire {
	delay: u64,
	kind: WireKind,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum WireKind {
	One,
	Addend { i: InputWire },
	InputsAnd { a: InputWire, b: InputWire },
	InputsNand { a: InputWire, b: InputWire },
	Sum { adder_id: u64 },
	Carry { adder_id: u64 },
	Xor { a: Box<WireKind>, b: Box<WireKind> },
	Xnor { a: Box<WireKind>, b: Box<WireKind> },
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
enum InputWire {
	Index(u8),
	SignExtended(u8),
}

impl std::fmt::Display for Wire {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		self.kind.fmt(f)
	}
}

impl PartialOrd for Wire {
	fn partial_cmp(&self, other: &Self) -> Option<std::cmp::Ordering> {
		Some(self.cmp(other))
	}
}

impl Ord for Wire {
	fn cmp(&self, other: &Self) -> std::cmp::Ordering {
		self.delay.cmp(&other.delay).then_with(|| self.kind.cmp(&other.kind))
	}
}

impl std::fmt::Display for WireKind {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		match self {
			Self::One => panic!("WireKind::One should never be emitted"),

			Self::Addend { i } => match i {
				InputWire::Index(c) => write!(f, "c[{c}]"),
				InputWire::SignExtended(c) => write!(f, "c[{c}] & c_is_signed"),
			},

			Self::InputsAnd { a, b } => {
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

			Self::InputsNand { a, b } => {
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

			Self::Sum { adder_id } => write!(f, "s{adder_id}"),

			Self::Carry { adder_id } => write!(f, "c{adder_id}"),

			Self::Xor { a, b } => write!(f, "({a}) ^ ({b})"),

			Self::Xnor { a, b } => write!(f, "~({a}) ^ ({b})"),
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
			(_, Self::One) => other.cmp(self).reverse(),

			(Self::Addend { i: i1 }, Self::Addend { i: i2 }) => i1.cmp(i2),
			(Self::Addend { .. }, _) => std::cmp::Ordering::Less,
			(_, Self::Addend { .. }) => other.cmp(self).reverse(),

			(Self::InputsAnd { a: a1, b: b1 }, Self::InputsAnd { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::InputsAnd { a: a1, b: b1 }, Self::InputsNand { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Less),

			(Self::InputsNand { a: a1, b: b1 }, Self::InputsAnd { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Greater),

			(Self::InputsNand { a: a1, b: b1 }, Self::InputsNand { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::InputsAnd { .. } | Self::InputsNand { .. }, _) => std::cmp::Ordering::Less,

			(_, Self::InputsAnd { .. } | Self::InputsNand { .. }) => other.cmp(self).reverse(),

			(Self::Sum { adder_id: id1 }, Self::Sum { adder_id: id2 }) =>
				id1.cmp(id2),

			(Self::Sum { adder_id: id1 }, Self::Carry { adder_id: id2 }) =>
				id1.cmp(id2).then(std::cmp::Ordering::Less),

			(Self::Carry { adder_id: id1 }, Self::Carry { adder_id: id2 }) =>
				id1.cmp(id2),

			(Self::Carry { adder_id: id1 }, Self::Sum { adder_id: id2 }) =>
				id1.cmp(id2).then(std::cmp::Ordering::Greater),

			(Self::Sum { .. } | Self::Carry { .. }, _) => std::cmp::Ordering::Less,

			(_, Self::Sum { .. } | Self::Carry { .. }) => other.cmp(self).reverse(),

			(Self::Xor { a: a1, b: b1 }, Self::Xor { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::Xor { a: a1, b: b1 }, Self::Xnor { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Less),

			(Self::Xnor { a: a1, b: b1 }, Self::Xnor { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)),

			(Self::Xnor { a: a1, b: b1 }, Self::Xor { a: a2, b: b2 }) =>
				a1.cmp(a2).then_with(|| b1.cmp(b2)).then(std::cmp::Ordering::Greater),
		}
	}
}

impl InputWire {
	fn delay(self) -> u64 {
		match self {
			Self::Index(_) => 0,
			Self::SignExtended(_) => 1,
		}
	}
}

fn parse_args(mut args: impl Iterator<Item = std::ffi::OsString>, argv0: &std::ffi::OsStr) -> (bool, bool, u8) {
	let mut fma = false;
	let mut mulh = false;
	let mut width = None;

	for opt in &mut args {
		match opt.to_str() {
			Some("--help") => {
				write_usage(std::io::stdout(), argv0);
				std::process::exit(0);
			},

			Some("--fma") => fma = true,

			Some("--mulh") => mulh = true,

			Some(value) if width.is_none() => match value.parse() {
				Ok(value) => width = Some(value),
				Err(_) => write_usage_and_crash(argv0),
			},

			_ => write_usage_and_crash(argv0),
		}
	}

	let None = args.next() else { write_usage_and_crash(argv0); };

	let Some(width) = width else { write_usage_and_crash(argv0); };
	(fma, mulh, width)
}

fn write_usage_and_crash(argv0: &std::ffi::OsStr) -> ! {
	write_usage(std::io::stderr(), argv0);
	std::process::exit(1);
}

fn write_usage(mut w: impl std::io::Write, argv0: &std::ffi::OsStr) {
	_ = writeln!(w, "Usage: {} [--fma] [--mulh] <width>", argv0.to_string_lossy());
}
