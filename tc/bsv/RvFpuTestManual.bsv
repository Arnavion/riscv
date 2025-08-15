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
			request: tagged Convert { rm: Rne, in: S, out: H, arg: { '1, 32'hdf7effff } },
			expected_response: RvFpuResponse { result: { '1, 16'hfc00 } }
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
				" } -> expected 0x%h but got 0x%h",
				test_case.expected_response.result,
				response.result
			)
		);
	endseq;

	let m <- mkTestModuleCases(test_cases, test_case_seq);
	return m;
endmodule
`endif
