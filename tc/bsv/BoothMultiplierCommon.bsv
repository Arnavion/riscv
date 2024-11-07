import Common::*;

typedef Server#(MultiplierRequest#(width), MultiplierResponse#(width)) Multiplier#(numeric type width);

typedef struct {
	Int#(width) arg1;
	Bool arg1_is_signed;
	Int#(width) arg2;
	Bool arg2_is_signed;
} MultiplierRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(width) mulh;
	Int#(width) mul;
} MultiplierResponse#(numeric type width) deriving(Bits, Eq);

`ifdef TESTING
import BuildVector::*;
import GetPut::*;
import StmtFSM::*;
import Vector::*;

module mkTestMultiplierModule#(Multiplier#(64) multiplier)();
	function TestCase make_test_case_inner(Int#(64) arg1, Bool arg1_is_signed, Int#(64) arg2, Bool arg2_is_signed);
		Int#(128) arg1_ = arg1_is_signed ? signExtend(arg1) : zeroExtend(arg1);
		Int#(128) arg2_ = arg2_is_signed ? signExtend(arg2) : zeroExtend(arg2);
		Int#(128) expected = arg1_ * arg2_;
		return TestCase {
			request: MultiplierRequest { arg1: arg1, arg1_is_signed: arg1_is_signed, arg2: arg2, arg2_is_signed: arg2_is_signed },
			expected_response: MultiplierResponse { mulh: truncate(expected >> 64), mul: truncate(expected) }
		};
	endfunction

	function TestCase make_test_case(Vector#(num_pairs, Tuple2#(Int#(64), Int#(64))) pairs, Integer i);
		match { .arg1, .arg2 } = pairs[i / 8];
		case (i % 8) matches
			0: return make_test_case_inner(arg1, False, arg2, False);
			1: return make_test_case_inner(arg1, False, arg2, True);
			2: return make_test_case_inner(arg1, True, arg2, False);
			3: return make_test_case_inner(arg1, True, arg2, True);
			4: return make_test_case_inner(arg2, False, arg1, False);
			5: return make_test_case_inner(arg2, False, arg1, True);
			6: return make_test_case_inner(arg2, True, arg1, False);
			7: return make_test_case_inner(arg2, True, arg1, True);
		endcase
	endfunction

	Vector#(64, TestCase) test_cases = genWith(make_test_case(vec(
		tuple2(64'h0000000000000000, 64'h0000000000000000),
		tuple2(64'h0000000000000001, 64'h0000000000000001),
		tuple2(64'hffffffffffffffff, 64'hffffffffffffffff),
		tuple2(64'ha0b6b8129b5bdfd9, 64'hbcba1c1981093535),
		tuple2(64'h2bc5ef4ad9b598c9, 64'he5f4626f4875716c),
		tuple2(64'h0dfb92cdbf099338, 64'hefadab9de0fc1ded),
		tuple2(64'hb82f30df91701f8c, 64'h106cbced76ae4c94),
		tuple2(64'h6f683ce7c71964fd, 64'h34491aa4bdea1abb)
	)));

	Reg#(MultiplierResponse#(64)) response <- mkRegU;

	function Stmt test_case_seq(TestCase test_case) = seq
		multiplier.request.put(test_case.request);
		response <= multiplier.response.first;
		multiplier.response.deq;
		assert_eq(
			test_case.expected_response,
			response,
			$swriteAV(
				"{ arg1: 0x%h, arg1_is_signed: ",
				test_case.request.arg1,
				fshow(test_case.request.arg1_is_signed),
				", arg2: 0x%h, arg2_is_signed: ",
				test_case.request.arg2,
				fshow(test_case.request.arg2_is_signed),
				" } -> expected { mulh: 0x%h, mul: 0x%h } but got { mulh: 0x%h, mul: 0x%h }",
				test_case.expected_response.mulh,
				test_case.expected_response.mul,
				response.mulh,
				response.mul
			)
		);
	endseq;

	let m <- mkTestModuleCases(test_cases, test_case_seq);
	return m;
endmodule

typedef struct {
	MultiplierRequest#(64) request;
	MultiplierResponse#(64) expected_response;
} TestCase deriving(Bits);
`endif
