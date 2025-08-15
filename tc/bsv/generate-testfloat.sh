#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit

TESTFLOAT_GEN="${TESTFLOAT_GEN:-submodules/berkeley-testfloat-3/build/Linux-x86_64-GCC/testfloat_gen}"
if ! [ -e "$TESTFLOAT_GEN" ]; then
	(cd submodules/berkeley-softfloat-3/build/Linux-x86_64-GCC/ && make clean && make -j)
	(cd submodules/berkeley-testfloat-3/build/Linux-x86_64-GCC/ && make clean && make -j)
	TESTFLOAT_GEN='submodules/berkeley-testfloat-3/build/Linux-x86_64-GCC/testfloat_gen'
fi

declare -A f_bsv_to_testfloat=(
	['H']='f16'
	['S']='f32'
	['D']='f64'
)

declare -A f_bsv_width=(
	['H']='16'
	['S']='32'
	['D']='64'
)

declare -A rm_bsv_to_testfloat=(
	['Rne']='rnear_even'
	['Rtz']='rminMag'
	['Rdn']='rmin'
	['Rup']='rmax'
	['Rmm']='rnear_maxMag'
)

template_header='`ifdef TESTING
import BuildVector::*;
import GetPut::*;
import StmtFSM::*;
import Vector::*;

import Common::*;
import RvFpu::*;

(* synthesize *)
module mkTest();
'

template_footer='
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
'

test_case="${1:-}"
if [ -z "$test_case" ]; then
	echo "Usage: $0 <TEST_CASE>" >&2
	exit 1
fi

<<< "$test_case" IFS='-' read -ra test_case_parts
out_f="target/bsv/RvFpuTest-${test_case}.bsv"

mkdir -p target/bsv/
rm -f "$out_f"

case "${test_case_parts[0]}" in
	'convert')
		convert_src_bsv="${test_case_parts[1]}"
		convert_src_testfloat="${f_bsv_to_testfloat["$convert_src_bsv"]}"

		convert_dest_bsv="${test_case_parts[2]}"
		convert_dest_testfloat="${f_bsv_to_testfloat["$convert_dest_bsv"]}"

		rm_bsv="${test_case_parts[3]}"
		rm_testfloat="${rm_bsv_to_testfloat["$rm_bsv"]}"

		convert_src_width="${f_bsv_width["$convert_src_bsv"]}"
		convert_dest_width="${f_bsv_width["$convert_dest_bsv"]}"

		num_test_cases="$("$TESTFLOAT_GEN" -level 1 -canonicalnan -tininessafter "-${rm_testfloat}" "${convert_src_testfloat}_to_${convert_dest_testfloat}" | wc -l)"

		(
			printf '%s' "$template_header"
			printf "\\tTestCase test_cases_[%d] = {\\n" "$num_test_cases"
			"$TESTFLOAT_GEN" -level 1 -canonicalnan -tininessafter "-${rm_testfloat}" "${convert_src_testfloat}_to_${convert_dest_testfloat}" |
				awk "
					BEGIN {
						first = 1
					}

					{
						if (first)
							first = 0
						else
							print \",\"
						print \"\\t\\tTestCase {\"
						printf \"\\t\\t\\trequest: tagged Convert { rm: ${rm_bsv}, in: ${convert_src_bsv}, out: ${convert_dest_bsv}, arg: { '1, ${convert_src_width}'h%s } },\\n\", \$1
						printf \"\\t\\t\\texpected_response: RvFpuResponse { result: { '1, ${convert_dest_width}'h%s } }\\n\", \$2
						printf \"\\t\\t}\"
					}
				"
			printf '\n\t};\n'
			printf "\\tVector#(%d, TestCase) test_cases = arrayToVector(test_cases_);\\n" "$num_test_cases"
			printf '%s' "$template_footer"
		) >"$out_f"
		;;

	'multiply')
		multiply_arg_bsv="${test_case_parts[1]}"
		multiply_arg_testfloat="${f_bsv_to_testfloat["$multiply_arg_bsv"]}"

		rm_bsv="${test_case_parts[2]}"
		rm_testfloat="${rm_bsv_to_testfloat["$rm_bsv"]}"

		multiply_arg_width="${f_bsv_width["$multiply_arg_bsv"]}"

		num_test_cases="$("$TESTFLOAT_GEN" -level 1 -canonicalnan -tininessafter "-${rm_testfloat}" "${multiply_arg_testfloat}_mul" | wc -l)"

		(
			printf '%s' "$template_header"
			printf "\\tTestCase test_cases_[%d] = {\\n" "$num_test_cases"
			"$TESTFLOAT_GEN" -level 1 -canonicalnan -tininessafter "-${rm_testfloat}" "${multiply_arg_testfloat}_mul" |
				awk "
					BEGIN {
						first = 1
					}

					{
						if (first)
							first = 0
						else
							print \",\"
						print \"\\t\\tTestCase {\"
						printf \"\\t\\t\\trequest: tagged Multiply { rm: ${rm_bsv}, width: ${multiply_arg_bsv}, arg1: { '1, ${multiply_arg_width}'h%s }, arg1: { '1, ${multiply_arg_width}'h%s } },\\n\", \$1, \$2
						printf \"\\t\\t\\texpected_response: RvFpuResponse { result: { '1, ${multiply_arg_width}'h%s } }\\n\", \$3
						printf \"\\t\\t}\"
					}
				"
			printf '\n\t};\n'
			printf "\\tVector#(%d, TestCase) test_cases = arrayToVector(test_cases_);\\n" "$num_test_cases"
			printf '%s' "$template_footer"
		) >"$out_f"
		;;

	*)
		echo "unrecognized test case [${test_case}]" >&2
		exit 1
		;;
esac
