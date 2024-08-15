#[derive(Clone, Copy, Debug)]
pub struct SupportedExtensions(u8);

impl SupportedExtensions {
	pub const RV32I: Self = Self(0);
	pub const RVC: Self = Self(1 << 1);

	pub const RV32C: Self = Self(Self::RV32I.0 | Self::RVC.0);
}

impl SupportedExtensions {
	pub(crate) fn contains(self, other: Self) -> bool {
		self.0 & other.0 == other.0
	}
}

impl core::ops::BitAnd for SupportedExtensions {
	type Output = Self;

	fn bitand(self, other: Self) -> Self::Output {
		Self(self.0 & other.0)
	}
}

impl core::ops::BitAndAssign for SupportedExtensions {
	fn bitand_assign(&mut self, other: Self) {
		self.0 &= other.0;
	}
}

impl core::ops::BitOr for SupportedExtensions {
	type Output = Self;

	fn bitor(self, other: Self) -> Self::Output {
		Self(self.0 | other.0)
	}
}

impl core::ops::BitOrAssign for SupportedExtensions {
	fn bitor_assign(&mut self, other: Self) {
		self.0 |= other.0;
	}
}

impl core::ops::Not for SupportedExtensions {
	type Output = Self;

	fn not(self) -> Self::Output {
		Self(!self.0)
	}
}
