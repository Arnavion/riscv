#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
#[repr(transparent)]
pub(crate) struct Tag(u16);

pub(crate) const EMPTY_TAG: Tag = Tag(0);

impl std::fmt::Display for Tag {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		self.0.fmt(f)
	}
}

#[repr(transparent)]
pub(crate) struct TagAllocator {
	next: Tag,
}

impl TagAllocator {
	pub(crate) fn allocate(&mut self) -> OneTickTags4 {
		let next = &mut self.next;
		let result = OneTickTags4(Tag(next.0), Tag(next.0.wrapping_add(1)), Tag(next.0.wrapping_add(2)), Tag(next.0.wrapping_add(3)));
		next.0 = next.0.wrapping_add(4);
		result
	}
}

impl Default for TagAllocator {
	fn default() -> Self {
		Self { next: EMPTY_TAG }
	}
}

pub(crate) struct OneTickTags4(Tag, Tag, Tag, Tag);

impl OneTickTags4 {
	pub(crate) fn allocate(self) -> (Tag, OneTickTags3) {
		(self.0, OneTickTags3(self.1, self.2, self.3))
	}
}

pub(crate) struct OneTickTags3(Tag, Tag, Tag);

impl OneTickTags3 {
	pub(crate) fn allocate(self) -> (Tag, OneTickTags2) {
		(self.0, OneTickTags2(self.1, self.2))
	}
}

pub(crate) struct OneTickTags2(Tag, Tag);

impl OneTickTags2 {
	pub(crate) fn allocate(self) -> (Tag, OneTickTags1) {
		(self.0, OneTickTags1(self.1))
	}
}

pub(crate) struct OneTickTags1(Tag);

impl OneTickTags1 {
	pub(crate) fn allocate(self) -> Tag {
		self.0
	}
}
