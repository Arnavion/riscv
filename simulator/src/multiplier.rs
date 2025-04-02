//! Ref: `booth_multiplier_multi_cycle.sv`

mod awint {
	use awint::{Bits, InlAwi};

	type Awi64 = awint::inlawi_ty!(64);
	type Awi65 = awint::inlawi_ty!(65);
	type Awi66 = awint::inlawi_ty!(66);
	type Awi132 = awint::inlawi_ty!(132);

	#[derive(Clone, Copy, Debug)]
	#[repr(transparent)]
	pub(super) struct I65(Awi65);

	impl From<i64> for I65 {
		fn from(i: i64) -> Self {
			let i: Awi64 = i.into();
			let mut result = Awi65::zero();
			result.sign_resize_(&i);
			Self(result)
		}
	}

	impl From<u64> for I65 {
		fn from(i: u64) -> Self {
			let i: Awi64 = i.into();
			let mut result = Awi65::zero();
			result.zero_resize_(&i);
			Self(result)
		}
	}

	#[derive(Clone, Copy, Debug)]
	#[repr(transparent)]
	pub(super) struct I66(Awi66);

	impl From<i64> for I66 {
		fn from(i: i64) -> Self {
			let i: Awi64 = i.into();
			let mut result = Awi66::zero();
			result.sign_resize_(&i);
			Self(result)
		}
	}

	impl From<u64> for I66 {
		fn from(i: u64) -> Self {
			let i: Awi64 = i.into();
			let mut result = Awi66::zero();
			result.zero_resize_(&i);
			Self(result)
		}
	}

	#[derive(Clone, Copy, Debug)]
	#[repr(transparent)]
	pub(crate) struct I132(Awi132);

	impl I132 {
		pub(super) fn field_to_1(i: I65) -> Self {
			Self(awint::inlawi!(0u66, &i.0, 0u1 ; ..132).unwrap())
		}

		pub(super) fn to_u8(self) -> u8 {
			self.0.to_u8()
		}

		pub(super) fn i32_at(self, i: usize) -> i32 {
			awint::inlawi!(self.0[i..(i + 32)]).unwrap().to_i32()
		}

		pub(super) fn i64_at(self, i: usize) -> i64 {
			awint::inlawi!(self.0[i..(i + 64)]).unwrap().to_i64()
		}

		// self[66..] +=/-= rhs
		pub(super) fn add_upper(
			self,
			neg: bool,
			rhs: I66,
		) -> Self {
			let mut lhs = awint::inlawi!(&self.0[66..132]).unwrap();
			lhs.neg_add_(neg, &rhs.0).unwrap();
			Self(awint::inlawi!(lhs, &self.0[..66] ; ..132).unwrap())
		}
	}

	impl std::ops::Shr<usize> for I132 {
		type Output = Self;

		fn shr(self, rhs: usize) -> Self::Output {
			let mut inner = self.0;
			inner.ashr_(rhs).unwrap();
			Self(inner)
		}
	}
}
use awint::{I65, I66};
pub(crate) use awint::I132;

#[derive(Debug)]
pub(crate) enum State {
	Pending { i: u8, p: I132 },
	Mulw { i: u8, p: I132, mulw: i32 },
	Mul { mul: i64, mulh: i64 },
}

impl State {
	pub(crate) fn initial(r_is_signed: bool, r: i64) -> (u8, I132) {
		let r: I65 = if r_is_signed { r.into() } else { r.cast_unsigned().into() };
		(0, I132::field_to_1(r))
	}
}

pub(crate) fn round(
	m_is_signed: bool,
	m: i64,
	i: u8,
	p: I132,
) -> State {
	let a: I66 = if m_is_signed { m.into() } else { m.cast_unsigned().into() };

	if i == 0 {
		let p = match p.to_u8() & 0b10 {
			0b00 => p >> 1,
			0b10 => p.add_upper(true, a) >> 1,
			_ => unreachable!(),
		};
		State::Pending { i: i + 1, p }
	}
	else {
		#[allow(clippy::match_same_arms)]
		let p = match p.to_u8() & 0b111 {
			0b000 => p >> 2,

			0b001 |
			0b010 => p.add_upper(false, a) >> 2,

			0b011 => (p >> 1).add_upper(false, a) >> 1,

			0b100 => (p >> 1).add_upper(true, a) >> 1,

			0b101 |
			0b110 => p.add_upper(true, a) >> 2,

			0b111 => p >> 2,

			_ => unreachable!(),
		};

		match i {
			16 => State::Mulw { i: i + 1, p, mulw: p.i32_at(33) },
			32 => State::Mul { mul: p.i64_at(1), mulh: p.i64_at(65) },
			i => State::Pending { i: i + 1, p },
		}
	}
}

#[cfg(test)]
mod tests {
	use super::{State, round};

	#[test]
	fn it_works() {
		const TESTS: &[(i64, i64)] = &[
			(0, 0),
			(0, 1),
			(1, 0),
			(1, 1),

			(1, 1),
			(1, -1),
			(-1, 1),
			(-1, -1),

			(-0x8000_0000_0000_0000, -0x8000_0000_0000_0000),

			(15, 6),
			(-15, 6),
			(15, -6),
			(-15, -6),

			(0xa0b6_b812_9b5b_dfd9_u64.cast_signed(), 0xbcba_1c19_8109_3535_u64.cast_signed()),
			(0xbcba_1c19_8109_3535_u64.cast_signed(), 0xa0b6_b812_9b5b_dfd9_u64.cast_signed()),
		];
		for &(m, r) in TESTS {
			for (m_is_signed, r_is_signed) in [
				(false, false),
				(false, true),
				(true, false),
				(true, true),
			] {
				let (mut i, mut p) = State::initial(r_is_signed, r);
				let mut mulw = None;
				let mul;
				let mulh;
				loop {
					match round(m_is_signed, m, i, p) {
						State::Pending { i: i_, p: p_ } => {
							i = i_;
							p = p_;
						},

						State::Mulw { i: i_, p: p_, mulw: mulw_ } => {
							i = i_;
							p = p_;
							assert!(mulw.replace(mulw_).is_none());
						},

						State::Mul { mul: mul_, mulh: mulh_ } => {
							mul = mul_;
							mulh = mulh_;
							break;
						},
					}
				};
				let mulw = mulw.unwrap();
				println!(
					"0x{m:016x}_{}64 * 0x{r:016x}_{}64 -> 0x{mulh:016x}_{mul:016x} / 0x{mulw:08x}",
					if m_is_signed { "i" } else { "u" },
					if r_is_signed { "i" } else { "u" },
				);

				let expected_mulw = {
					#[allow(clippy::cast_possible_truncation)]
					let m = i64::from(m as i32);
					#[allow(clippy::cast_possible_truncation)]
					let r = i64::from(r as i32);
					#[allow(clippy::cast_possible_truncation)]
					let expected = m.wrapping_mul(r) as i32;
					expected
				};

				let (expected_mul, expected_mulh) = {
					let m: i128 = if m_is_signed { m.into() } else { m.cast_unsigned().into() };
					let r: i128 = if r_is_signed { r.into() } else { r.cast_unsigned().into() };
					let expected = m.wrapping_mul(r);
					#[allow(clippy::cast_possible_truncation)]
					(expected as i64, (expected >> 64) as i64)
				};

				assert_eq!(mulw, expected_mulw);
				assert_eq!(mul, expected_mul);
				assert_eq!(mulh, expected_mulh);
			}
		}
	}
}
