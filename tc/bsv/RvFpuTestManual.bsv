`ifdef TESTING
import BuildVector::*;
import GetPut::*;
import StmtFSM::*;
import Vector::*;

import Common::*;
import RvFpu::*;

(* synthesize *)
module mkTest();
	let test_cases = vec(
		TestCase {
			request: tagged Multiply { rm: Rne, width: D, arg1: { '1, 64'hc0035f74d9e4a66e }, arg2: { '1, 64'hc1c000800000003f } },
			expected_response: RvFpuResponse { result: { '1, 64'h41d3600fd58b75df }, flags: unpack(5'b00001) }
		},
		TestCase {
			request: tagged Add { rm: Rne, width: D, arg1: { '1, 64'h41d3600fd58b75df }, arg2: { '1, 64'h402fe04a50d62ff8 } },
			expected_response: RvFpuResponse { result: { '1, 64'h41d3600fd9877f29 }, flags: unpack(5'b00001) }
		},
		TestCase {
			request: tagged FusedMultiplyAdd { rm: Rne, width: D, arg1: { '1, 64'hc0035f74d9e4a66e }, arg2: { '1, 64'hc1c000800000003f }, arg3: { '1, 64'h402fe04a50d62ff8 } },
			expected_response: RvFpuResponse { result: { '1, 64'h41d3600fd9877f2a }, flags: unpack(5'b00001) }
		}
	);

	RvFpu fpu <- mkRvFpu;
	Reg#(RvFpuResponse) response <- mkRegU;

	function Stmt test_case_seq(TestCase test_case) = seq
		fpu.request.put(test_case.request);
		response <= fpu.response.first;
		fpu.response.deq;
		assert_eq(
			test_case.expected_response,
			response,
			$swriteAV(
				"{ ",
				fshow(test_case.request),
				" } -> expected ",
				fshow(test_case.expected_response),
				" but got ",
				fshow(response)
			)
		);
	endseq;

	let m <- mkTestModuleCases(test_cases, test_case_seq);
	return m;
endmodule
`endif
