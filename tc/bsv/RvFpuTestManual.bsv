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
			request: tagged Subtract { rm: Rne, width: D, arg1: { '1, 64'h0000000000000000 }, arg2: { '1, 64'ha57f319ede38f755 } },
			expected_response: RvFpuResponse { result: { '1, 64'h257f319ede38f755 }, flags: unpack(5'b00000) }
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
