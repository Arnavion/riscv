use crate::{RegisterValue, Tag};

#[derive(Debug, Default)]
pub(crate) struct XRegs {
	inner: [(i64, Option<Tag>); 32],
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum XReg {
	X0,
	X1,
	X2,
	X3,
	X4,
	X5,
	X6,
	X7,
	X8,
	X9,
	X10,
	X11,
	X12,
	X13,
	X14,
	X15,
	X16,
	X17,
	X18,
	X19,
	X20,
	X21,
	X22,
	X23,
	X24,
	X25,
	X26,
	X27,
	X28,
	X29,
	X30,
	X31,
}

impl XRegs {
	pub(crate) fn load(&self, x_reg: XReg) -> RegisterValue {
		let i = usize::from(x_reg);
		let reg = self.inner[i];
		if let Some(tag) = reg.1 {
			RegisterValue::Tag(tag)
		}
		else {
			RegisterValue::Value(reg.0)
		}
	}

	pub(crate) fn rename(&mut self, x_reg: XReg, tag: Tag) -> bool {
		let i = usize::from(x_reg);
		if i == 0 {
			false
		}
		else {
			self.inner[i].1 = Some(tag);
			true
		}
	}

	pub(crate) fn store(&mut self, x_reg: XReg, tag: Tag, value: i64) {
		let i = usize::from(x_reg);
		if i != 0 {
			let reg = &mut self.inner[i];
			reg.0 = value;
			if reg.1 == Some(tag) {
				reg.1 = None;
			}
		}
	}

	pub(crate) fn reset_all_tags(
		&mut self,
		tags: impl IntoIterator<Item = (XReg, Tag, Option<i64>)>,
	) {
		for reg in &mut self.inner {
			reg.1 = None;
		}

		for (x_reg, tag, _) in tags {
			let i = usize::from(x_reg);
			if i != 0 {
				self.inner[i].1 = Some(tag);
			}
		}
	}
}

impl std::fmt::Display for XRegs {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		for row in 0_usize..8 {
			if row != 0 {
				writeln!(f)?;
			}

			for col in 0_usize..4 {
				if col != 0 {
					write!(f, " | ")?;
				}

				let i = row + col * 8;
				let (value, tag) = self.inner[i];
				write!(f, "x{i:<2}: 0x{value:016x}")?;
				match tag {
					Some(tag) => write!(f, " # {tag:3} #")?,
					None => write!(f, " #     #")?,
				}
			}
		}

		Ok(())
	}
}

impl TryFrom<u8> for XReg {
	type Error = ();

	fn try_from(raw: u8) -> Result<Self, Self::Error> {
		u32::from(raw).try_into()
	}
}

impl TryFrom<u16> for XReg {
	type Error = ();

	fn try_from(raw: u16) -> Result<Self, Self::Error> {
		u32::from(raw).try_into()
	}
}

impl TryFrom<u32> for XReg {
	type Error = ();

	fn try_from(raw: u32) -> Result<Self, Self::Error> {
		Ok(match raw {
			0 => Self::X0,
			1 => Self::X1,
			2 => Self::X2,
			3 => Self::X3,
			4 => Self::X4,
			5 => Self::X5,
			6 => Self::X6,
			7 => Self::X7,
			8 => Self::X8,
			9 => Self::X9,
			10 => Self::X10,
			11 => Self::X11,
			12 => Self::X12,
			13 => Self::X13,
			14 => Self::X14,
			15 => Self::X15,
			16 => Self::X16,
			17 => Self::X17,
			18 => Self::X18,
			19 => Self::X19,
			20 => Self::X20,
			21 => Self::X21,
			22 => Self::X22,
			23 => Self::X23,
			24 => Self::X24,
			25 => Self::X25,
			26 => Self::X26,
			27 => Self::X27,
			28 => Self::X28,
			29 => Self::X29,
			30 => Self::X30,
			31 => Self::X31,
			_ => return Err(()),
		})
	}
}

impl From<XReg> for u8 {
	fn from(x_reg: XReg) -> Self {
		match x_reg {
			XReg::X0 => 0,
			XReg::X1 => 1,
			XReg::X2 => 2,
			XReg::X3 => 3,
			XReg::X4 => 4,
			XReg::X5 => 5,
			XReg::X6 => 6,
			XReg::X7 => 7,
			XReg::X8 => 8,
			XReg::X9 => 9,
			XReg::X10 => 10,
			XReg::X11 => 11,
			XReg::X12 => 12,
			XReg::X13 => 13,
			XReg::X14 => 14,
			XReg::X15 => 15,
			XReg::X16 => 16,
			XReg::X17 => 17,
			XReg::X18 => 18,
			XReg::X19 => 19,
			XReg::X20 => 20,
			XReg::X21 => 21,
			XReg::X22 => 22,
			XReg::X23 => 23,
			XReg::X24 => 24,
			XReg::X25 => 25,
			XReg::X26 => 26,
			XReg::X27 => 27,
			XReg::X28 => 28,
			XReg::X29 => 29,
			XReg::X30 => 30,
			XReg::X31 => 31,
		}
	}
}

impl From<XReg> for usize {
	fn from(x_reg: XReg) -> Self {
		u8::from(x_reg).into()
	}
}
