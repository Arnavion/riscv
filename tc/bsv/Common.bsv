import GetPut::*;
import FIFO::*;

interface Server#(type req_type, type resp_type);
	interface Put#(req_type) request;
	interface GetS#(resp_type) response;
endinterface

function GetS#(resp_type) toGetS(FIFO#(req_type) args, FIFO#(resp_type) result) =
	interface GetS#(resp_type);
		method resp_type first = result.first;

		method Action deq;
			args.deq;
			result.deq;
		endmethod
	endinterface;

`ifdef TESTING
import StmtFSM::*;
import Vector::*;

typedef enum {
	Ready,
	Running
} TestFsmState deriving(Bits);

module mkTestModule#(
	Stmt test_seq
)();
	FSM test_fsm <- mkFSM(test_seq);

	Reg#(TestFsmState) state <- mkReg(Ready);

	rule run(state matches Ready);
		$display("Test started");
		state <= Running;
		test_fsm.start;
	endrule

	rule done(state matches Running &&& test_fsm.done);
		$display("Test passed");
		$finish;
	endrule
endmodule

module mkTestModuleCases#(
	Vector#(num_test_cases, test_case_t) test_cases,
	function Stmt test_case_seq(test_case_t test_case)
)();
	Reg#(UInt#(32)) i <- mkReg(0);

	Stmt test_seq = seq
		for (i <= 0; i < fromInteger(valueOf(num_test_cases)); i <= i + 1) seq
			test_case_seq(test_cases[i]);
		endseq
	endseq;

	let m <- mkTestModule(test_seq);
	return m;
endmodule

function Action assert_eq(t a, t b, ActionValue#(m) message)
provisos(
	Bits#(t, a__),
	Eq#(t),
	Bits#(m, 4096)
) = action
	if (a != b) begin
		$display("Assertion failed: 0x%h != 0x%h: %s", a, b, message);
		$finish;
	end
endaction;
`endif
