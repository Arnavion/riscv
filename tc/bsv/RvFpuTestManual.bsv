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
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h37e0000000000000 } },
			expected_response: RvFpuResponse { result: { '1, 32'h00100000 }, flags: unpack(5'b00000) }
		},
		TestCase {
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h380ffffff0000000 } },
			expected_response: RvFpuResponse { result: { '1, 32'h00800000 }, flags: unpack(5'b00001) }
		},
		TestCase {
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h380fffffe0000000 } },
			expected_response: RvFpuResponse { result: { '1, 32'h00800000 }, flags: unpack(5'b00011) }
		},
		TestCase {
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h0000000000000001 } },
			expected_response: RvFpuResponse { result: { '1, 32'h00000000 }, flags: unpack(5'b00011) }
		},
		TestCase {
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h37e07fff7fffffff } },
			expected_response: RvFpuResponse { result: { '1, 32'h00107fff }, flags: unpack(5'b00011) }
		},
		TestCase {
			request: tagged Convert { rm: Rne, in: D, out: S, arg: { '1, 64'h7ff4000000000000 } },
			expected_response: RvFpuResponse { result: { '1, 32'h7fc00000 }, flags: unpack(5'b10000) }
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
