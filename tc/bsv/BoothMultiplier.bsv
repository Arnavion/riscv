import ClientServer::*;
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
module mkBoothMultiplier(Multiplier#(`WIDTH));
	FIFO#(MultiplierRequest#(`WIDTH)) args_ <- mkBypassFIFO;
	GetS#(MultiplierRequest#(`WIDTH)) args = fifoToGetS(args_);
	FIFO#(MultiplierResponse#(`WIDTH)) result_ <- mkBypassFIFO;
	Put#(MultiplierResponse#(`WIDTH)) result = toPut(result_);

	rule run(args.first matches MultiplierRequest { arg1: .arg1, arg1_is_signed: .arg1_is_signed, arg2: .arg2, arg2_is_signed: .arg2_is_signed });
		match { .mulh, .mul } = multiply(arg1, arg1_is_signed, arg2, arg2_is_signed);
		result.put(MultiplierResponse { mulh: mulh, mul: mul });
	endrule

	interface request = toPut(args_);
	interface response = toGetS(args_, result_);
endmodule

function Tuple2#(Int#(width), Int#(width)) multiply(
	Int#(width) arg1,
	Bool arg1_is_signed,
	Int#(width) arg2,
	Bool arg2_is_signed
)
provisos (
	Add#(TAdd#(width, 2), TAdd#(width, 1), p_width),
	Add#(TAdd#(width, 3), width, p_width)
);
	Int#(TAdd#(width, 1)) m = arg1_is_signed ? signExtend(arg1) : zeroExtend(arg1);
	Int#(TAdd#(width, 1)) r = arg2_is_signed ? signExtend(arg2) : zeroExtend(arg2);

	Int#(p_width) p = unpack({
		signExtend(pack(r)[0]) & Bit#(TAdd#(width, 1))'(pack(-m)),
		?
	}) >> 2;

	for (Integer i = 0; i < valueOf(width); i = i + 2) begin
		let r3 = pack(r >> i)[2:0];

		if (unpack(& (r3[1:0] ^ signExtend(r3[2]))))
			p = p >> 1;

		if (unpack(| (r3[1:0] ^ signExtend(r3[2])))) begin
			Tuple2#(Bit#(TAdd#(width, 2)), Bit#(TAdd#(width, 1))) p_parts = split(pack(p));
			match { .p_hi, .p_lo } = p_parts;
			p_hi = pack(unpack(p_hi) + extend((unpack(r3[2]) ? -m : m)));
			p = unpack({ p_hi, p_lo });
		end

		if (unpack(& (r3[1:0] ^ signExtend(r3[2]))))
			p = p >> 1;
		else
			p = p >> 2;
	end

	let mul = truncate(p);
	let mulh = truncate(p >> valueOf(width));
	return tuple2(mulh, mul);
endfunction

`ifdef TESTING
(* synthesize *)
module mkTest();
	let multiplier <- mkBoothMultiplier;
	let m <- mkTestMultiplierModule(multiplier);
	return m;
endmodule
`endif
