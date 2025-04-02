use crate::{RegisterValue, Tag};

#[derive(Debug)]
pub(crate) struct Csrs {
	cycle: i64,
	instret: i64,
	time: i64,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Csr {
	Cycle,
	Instret,
	Time,
}

impl Csrs {
	pub(crate) fn load(&self, csr: Csr) -> RegisterValue {
		match csr {
			Csr::Cycle => RegisterValue::Value(self.cycle),
			Csr::Instret => RegisterValue::Value(self.instret),
			Csr::Time => RegisterValue::Value(self.time),
		}
	}

	#[allow(clippy::unused_self)]
	pub(crate) fn rename(&mut self, csr: Csr, _tag: Tag) -> bool {
		#[allow(clippy::match_same_arms)]
		match csr {
			Csr::Cycle => false,
			Csr::Instret => false,
			Csr::Time => false,
		}
	}

	#[allow(clippy::unused_self)]
	pub(crate) fn store(&mut self, csr: Csr, _tag: Tag, _value: i64) {
		match csr {
			Csr::Cycle => panic!("cycle CSR is read-only"),
			Csr::Instret => panic!("instret CSR is read-only"),
			Csr::Time => panic!("time CSR is read-only"),
		}
	}

	#[allow(clippy::unused_self)]
	pub(crate) fn reset_all_tags(
		&mut self,
		_tags: impl IntoIterator<Item = (Csr, Tag, Option<i64>)>,
	) {}

	pub(crate) fn cycle(&self) -> i64 {
		self.cycle
	}

	pub(crate) fn tick(&mut self, cycles: i64, instret: i64) {
		self.cycle += cycles;
		self.instret += instret;
		self.time = nanos_since_unix_epoch();
	}
}

impl Default for Csrs {
	fn default() -> Self {
		Self {
			cycle: 0,
			instret: 0,
			time: nanos_since_unix_epoch(),
		}
	}
}

impl std::fmt::Display for Csrs {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		writeln!(f, "cycle:   0x{:016x}", self.cycle)?;
		writeln!(f, "time:    0x{:016x}", self.time)?;
		writeln!(f, "instret: 0x{:016x}", self.instret)?;
		Ok(())
	}
}

impl TryFrom<u32> for Csr {
	type Error = ();

	fn try_from(raw: u32) -> Result<Self, Self::Error> {
		Ok(match raw {
			0xc00 => Self::Cycle,
			0xc01 => Self::Time,
			0xc02 => Self::Instret,
			_ => return Err(()),
		})
	}
}

fn nanos_since_unix_epoch() -> i64 {
	std::time::SystemTime::now()
		.duration_since(std::time::SystemTime::UNIX_EPOCH)
		.unwrap()
		.as_nanos()
		.try_into().unwrap()
}
