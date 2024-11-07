import FIFO::*;
import GetPut::*;
import SpecialFIFOs::*;

import BoothMultiplierCommon::*;
import Common::*;

`ifndef WIDTH
	`ifdef TESTING
		`define WIDTH 64
	`else
		`define WIDTH 8
	`endif
`endif

(* synthesize *)
(* descending_urgency = "done, pending" *)
module mkBoothMultiplierMultiCycle(Multiplier#(`WIDTH));
	MultiplyRound#(`WIDTH) multiply_round <- mkMultiplyRound;

	Reg#(State#(`WIDTH)) state <- mkReg(tagged Ready);

	FIFO#(MultiplierRequest#(`WIDTH)) args_ <- mkBypassFIFO;
	GetS#(MultiplierRequest#(`WIDTH)) args = fifoToGetS(args_);
	FIFO#(MultiplierResponse#(`WIDTH)) result_ <- mkBypassFIFO;
	Put#(MultiplierResponse#(`WIDTH)) result = toPut(result_);

	rule pending(args.first matches MultiplierRequest { arg1: .arg1, arg1_is_signed: .arg1_is_signed, arg2: .arg2, arg2_is_signed: .arg2_is_signed });
		let next_state_pending = multiply_round.run(arg1, arg1_is_signed, arg2, arg2_is_signed, state);
		state <= tagged Pending next_state_pending;
	endrule

	rule done(
		args.first matches MultiplierRequest { arg1: .arg1, arg1_is_signed: .arg1_is_signed, arg2: .arg2, arg2_is_signed: .arg2_is_signed } &&&
		state matches tagged Pending (StatePending { i: .i }) &&& UInt#(`WIDTH)'(extend(i)) == `WIDTH / 2 - 1
	);
		match StatePending { p: .next_p } = multiply_round.run(arg1, arg1_is_signed, arg2, arg2_is_signed, state);
		let mul = truncate(next_p >> 1);
		let mulh = truncate(next_p >> (`WIDTH + 1));
		result.put(MultiplierResponse { mulh: mulh, mul: mul });
	endrule

	interface request = toPut(args_);

	interface GetS response;
		method MultiplierResponse#(`WIDTH) first = result_.first;

		method Action deq;
			args_.deq;
			state <= tagged Ready;
			result_.deq;
		endmethod
	endinterface
endmodule

interface MultiplyRound#(numeric type width);
	method StatePending#(width) run(
		Int#(width) arg1,
		Bool arg1_is_signed,
		Int#(width) arg2,
		Bool arg2_is_signed,

		State#(width) state
	);
endinterface

typedef union tagged {
	void Ready;
	StatePending#(width) Pending;
} State#(numeric type width) deriving(Bits);

typedef struct {
	UInt#(TLog#(TDiv#(width, 2))) i;
	Int#(TAdd#(TAdd#(width, 2), TAdd#(width, 1))) p;
} StatePending#(numeric type width) deriving(Bits);

(* synthesize *)
module mkMultiplyRound(MultiplyRound#(`WIDTH));
	Adder#(`WIDTH) adder <- mkAdder;

	method StatePending#(`WIDTH) run(
		Int#(`WIDTH) arg1,
		Bool arg1_is_signed,
		Int#(`WIDTH) arg2,
		Bool arg2_is_signed,

		State#(`WIDTH) state
	) = multiply_round(adder, arg1, arg1_is_signed, arg2, arg2_is_signed, state);
endmodule

function StatePending#(width) multiply_round(
	Adder#(width) adder,

	Int#(width) arg1,
	Bool arg1_is_signed,
	Int#(width) arg2,
	Bool arg2_is_signed,

	State#(width) state
);
	Int#(TAdd#(width, 1)) m = arg1_is_signed ? signExtend(arg1) : zeroExtend(arg1);

	let adder_request = case (state) matches
		tagged Ready: return AdderRequest { arg1: 0, arg2: ~m, cin: True };

		tagged Pending (StatePending { i: .i, p: .p }): begin
			let p3 = pack(p)[2:0];

			let adder_request_arg1 = case (p3[1:0] ^ signExtend(p3[2])) matches
				2'b00: return ?;

				.n &&& (n == 2'b01 || n == 2'b10): return truncate(p >> (valueOf(width) + 2));

				2'b11: return truncate(p >> (valueOf(width) + 3));
			endcase;
			return AdderRequest { arg1: adder_request_arg1, arg2: unpack(p3[2]) ? ~m : m, cin: unpack(p3[2]) };
		end
	endcase;
	let p_plus = adder.run(adder_request).add;

	case (state) matches
		tagged Ready: begin
			Int#(TAdd#(width, 1)) r = arg2_is_signed ? signExtend(arg2) : zeroExtend(arg2);
			let next_p = unpack({
				(pack(r)[0] != 0) ? pack(p_plus) : 0,
				pack(r)
			});
			return StatePending {
				i: 0,
				p: next_p
			};
		end

		tagged Pending (StatePending { i: .i, p: .p }): begin
			let p3 = pack(p)[2:0];

			let next_p = case (p3[1:0] ^ signExtend(p3[2])) matches
				2'b00: return p >> 2;

				.n &&& (n == 2'b01 || n == 2'b10): return unpack({
					pack(extend(p_plus)),
					pack(Int#(width)'(truncate(p >> 2)))
				});

				2'b11: return unpack({
					pack(p_plus),
					pack(truncate(p >> 2))
				});
			endcase;

			return StatePending {
				i: i + 1,
				p: next_p
			};
		end
	endcase
endfunction

interface Adder#(numeric type width);
	method AdderResponse#(width) run(AdderRequest#(width) request);
endinterface

typedef struct {
	Int#(width) arg1;
	Int#(TAdd#(width, 1)) arg2;
	Bool cin;
} AdderRequest#(numeric type width) deriving(Bits);

typedef struct {
	Int#(TAdd#(width, 2)) add;
} AdderResponse#(numeric type width) deriving(Bits);

(* synthesize *)
module mkAdder(Adder#(`WIDTH));
	method AdderResponse#(`WIDTH) run(AdderRequest#(`WIDTH) request);
		match AdderRequest { arg1: .arg1, arg2: .arg2, cin: .cin } = request;
		let add = extend(arg1) + extend(arg2) + (cin ? 1 : 0);
		return AdderResponse { add: add };
	endmethod
endmodule

`ifdef TESTING
(* synthesize *)
module mkTest();
	let multiplier <- mkBoothMultiplierMultiCycle;
	let m <- mkTestMultiplierModule(multiplier);
	return m;
endmodule
`endif
