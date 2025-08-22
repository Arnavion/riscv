#!/bin/bash

set -euo pipefail
shopt -s inherit_errexit

TESTFLOAT_GEN="${TESTFLOAT_GEN:-submodules/berkeley-testfloat-3/build/Linux-x86_64-GCC/testfloat_gen}"

declare -A f_bsv_to_testfloat=(
    ['H']='f16'
    ['S']='f32'
    ['D']='f64'
)

declare -A nan_box_prefix=(
    ['H']='FFFFFFFFFFFF'
    ['S']='FFFFFFFF'
    ['D']=''
)

declare -A exponent_mask=(
    ['H']="0b0'11111'0000000000"
    ['S']="0b0'11111111'00000000000000000000000"
    ['D']="0b0'11111111111'0000000000000000000000000000000000000000000000000000"
)

declare -A canonical_nan=(
    ['H']='0xffffffffffff7e00'
    ['S']='0xffffffff7fc00000'
    ['D']='0x7ff8000000000000'
)

declare -A rm_bsv_to_testfloat=(
    ['Rne']='rnear_even'
    ['Rtz']='rminMag'
    ['Rdn']='rmin'
    ['Rup']='rmax'
    ['Rmm']='rnear_maxMag'
)

# ShellCheck thinks the ` means we're trying to embed an expression in the string but forgot to use double quotes.
#
# shellcheck disable=SC2016
bsv_template='`ifdef TESTING
import BuildVector::*;
import GetPut::*;
import StmtFSM::*;
import Vector::*;

import Common::*;
import RvFpu::*;

import "BDPI" function UInt#(32) test_case_num_test_cases();
%s
import "BDPI" function Bit#(64) test_case_expected_result_raw(UInt#(32) i);
import "BDPI" function Bit#(64) test_case_expected_result_canonicalized(UInt#(32) i);
import "BDPI" function Bit#(5) test_case_expected_flags(UInt#(32) i);

(* synthesize *)
module mkTest();
    RvFpu fpu <- mkRvFpu;
    Reg#(RvFpuResponse) response <- mkRegU;

    function Stmt test_case_seq(UInt#(32) i);
        let test_case = %s;
        return seq
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
    endfunction

    Reg#(UInt#(32)) i <- mkReg(0);

    let m <- mkTestModule(seq
        for (i <= 0; i < test_case_num_test_cases; i <= i + 1) seq
            test_case_seq(i);
        endseq
    endseq);
    return m;
endmodule
`endif
'

c_template_header='#include <stdint.h>

typedef struct {
    uint64_t arg;
    uint64_t expected_result;
    uint8_t expected_flags;
} TestCaseOneArg;

typedef struct {
    uint64_t arg1;
    uint64_t arg2;
    uint64_t expected_result;
    uint8_t expected_flags;
} TestCaseTwoArgs;

typedef struct {
    uint64_t arg1;
    uint64_t arg2;
    uint64_t arg3;
    uint64_t expected_result;
    uint8_t expected_flags;
} TestCaseThreeArgs;

static %s test_cases[] = {
'

c_template_one_arg='};

uint64_t test_case_arg(uint32_t i) {
    return test_cases[i].arg;
}
'

c_template_two_args='};

uint64_t test_case_arg1(uint32_t i) {
    return test_cases[i].arg1;
}

uint64_t test_case_arg2(uint32_t i) {
    return test_cases[i].arg2;
}
'

# TODO(unused)
#
# shellcheck disable=SC2034
c_template_three_args="$c_template_two_args
uint64_t test_case_arg3(uint32_t i) {
    return test_cases[i].arg3;
}
"

c_template_footer='
uint32_t test_case_num_test_cases() {
    return sizeof(test_cases) / sizeof(test_cases[0]);
}

static uint64_t canonicalize_nan(uint64_t f) {
    uint64_t exponent_mask = %s;
    uint64_t canonical_nan = %s;
    uint64_t significand_mask = (~exponent_mask) & (exponent_mask - 1);
    if (((f & exponent_mask) == exponent_mask) && ((f & significand_mask) != 0)) {
        return canonical_nan;
    }
    else {
        return f;
    }
}

uint64_t test_case_expected_result_raw(uint32_t i) {
    return test_cases[i].expected_result;
}

uint64_t test_case_expected_result_canonicalized(uint32_t i) {
    return canonicalize_nan(test_case_expected_result_raw(i));
}

uint8_t test_case_expected_flags(uint32_t i) {
    return test_cases[i].expected_flags;
}
'

test_case_one_arg() {
    local src_nan_box_prefix
    src_nan_box_prefix="$1"
    local dest_nan_box_prefix
    dest_nan_box_prefix="$2"

    awk '!x[$0]++' |
        sed -Ee "s/^(\S+) (\S+) (\S+)$/    { .arg = 0x${src_nan_box_prefix}\\1, .expected_result = 0x${dest_nan_box_prefix}\\2, .expected_flags = 0x\\3 },/"
}

test_case_two_args() {
    local nan_box_prefix
    nan_box_prefix="$1"

    awk '!x[$0]++' |
        sed -Ee "s/^(\S+) (\S+) (\S+) (\S+)$/    { .arg1 = 0x${nan_box_prefix}\\1, .arg2 = 0x${nan_box_prefix}\\2, .expected_result = 0x${nan_box_prefix}\\3, .expected_flags = 0x\\4 },/"
}

test_case_three_args() {
    local nan_box_prefix
    nan_box_prefix="$1"

    awk '!x[$0]++' |
        sed -Ee "s/^(\S+) (\S+) (\S+) (\S+) (\S+)$/    { .arg1 = 0x${nan_box_prefix}\\1, .arg2 = 0x${nan_box_prefix}\\2, .arg3 = 0x${nan_box_prefix}\\3, .expected_result = 0x${nan_box_prefix}\\4, .expected_flags = 0x\\5 },/"
}

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
    'cvt')
        cvt_src_bsv="${test_case_parts[1]}"
        cvt_src_testfloat="${f_bsv_to_testfloat["$cvt_src_bsv"]}"

        cvt_dest_bsv="${test_case_parts[2]}"
        cvt_dest_testfloat="${f_bsv_to_testfloat["$cvt_dest_bsv"]}"

        rm_bsv="${test_case_parts[3]}"
        rm_testfloat="${rm_bsv_to_testfloat["$rm_bsv"]}"

        cvt_src_nan_box_prefix="${nan_box_prefix["$cvt_src_bsv"]}"
        cvt_dest_nan_box_prefix="${nan_box_prefix["$cvt_dest_bsv"]}"

        cvt_dest_exponent_mask="${exponent_mask["$cvt_dest_bsv"]}"
        cvt_dest_canonical_nan="${canonical_nan["$cvt_dest_bsv"]}"

        # shellcheck disable=SC2059 # printf with a template
        printf "$bsv_template" \
            'import "BDPI" function Bit#(64) test_case_arg(UInt#(32) i);' \
            "$(
                printf 'TestCase {\n'
                printf '            request: tagged Convert { rm: %s, in: %s, out: %s, arg: test_case_arg(i) },\n' "$rm_bsv" "$cvt_src_bsv" "$cvt_dest_bsv"
                printf '            expected_response: RvFpuResponse { result: test_case_expected_result_canonicalized(i), flags: unpack(test_case_expected_flags(i)) }\n'
                printf '        }'
            )" \
            >"$out_f"

        (
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_header" 'TestCaseOneArg'
            "$TESTFLOAT_GEN" -level 2 -tininessafter "-${rm_testfloat}" "${cvt_src_testfloat}_to_${cvt_dest_testfloat}" |
                test_case_one_arg "$cvt_src_nan_box_prefix" "$cvt_dest_nan_box_prefix"
            printf '%s' "$c_template_one_arg"
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_footer" "$cvt_dest_exponent_mask" "$cvt_dest_canonical_nan"
        ) >"${out_f}.c"
        ;;

    'add'|'sub'|'mul')
        op_bsv="${test_case_parts[1]}"
        op_testfloat="${f_bsv_to_testfloat["$op_bsv"]}"

        rm_bsv="${test_case_parts[2]}"
        rm_testfloat="${rm_bsv_to_testfloat["$rm_bsv"]}"

        op_nan_box_prefix="${nan_box_prefix["$op_bsv"]}"

        op_exponent_mask="${exponent_mask["$op_bsv"]}"
        op_canonical_nan="${canonical_nan["$op_bsv"]}"

        # shellcheck disable=SC2059 # printf with a template
        printf "$bsv_template" \
            "$(
                printf 'import "BDPI" function Bit#(64) test_case_arg1(UInt#(32) i);\n'
                printf 'import "BDPI" function Bit#(64) test_case_arg2(UInt#(32) i);'
            )" \
            "$(
                printf 'TestCase {\n'
                printf '            request: tagged '
                case "${test_case_parts[0]}" in
                    'add')
                        printf 'Add'
                        ;;
                    'sub')
                        printf 'Subtract'
                        ;;
                    'mul')
                        printf 'Multiply'
                        ;;
                esac
                printf ' { rm: %s, width: %s, arg1: test_case_arg1(i), arg2: test_case_arg2(i) },\n' "$rm_bsv" "$op_bsv"
                printf '            expected_response: RvFpuResponse { result: test_case_expected_result_canonicalized(i), flags: unpack(test_case_expected_flags(i)) }\n'
                printf '        }'
            )" \
            >"$out_f"

        (
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_header" 'TestCaseTwoArgs'
            "$TESTFLOAT_GEN" -level 1 -tininessafter "-${rm_testfloat}" "${op_testfloat}_${test_case_parts[0]}" |
                test_case_two_args "$op_nan_box_prefix"
            printf '%s' "$c_template_two_args"
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_footer" "$op_exponent_mask" "$op_canonical_nan"
        ) >"${out_f}.c"
        ;;

    'sqrt')
        op_bsv="${test_case_parts[1]}"
        op_testfloat="${f_bsv_to_testfloat["$op_bsv"]}"

        rm_bsv="${test_case_parts[2]}"
        rm_testfloat="${rm_bsv_to_testfloat["$rm_bsv"]}"

        op_nan_box_prefix="${nan_box_prefix["$op_bsv"]}"

        op_exponent_mask="${exponent_mask["$op_bsv"]}"
        op_canonical_nan="${canonical_nan["$op_bsv"]}"

        # shellcheck disable=SC2059 # printf with a template
        printf "$bsv_template" \
            'import "BDPI" function Bit#(64) test_case_arg(UInt#(32) i);' \
            "$(
                printf 'TestCase {\n'
                printf '            request: tagged Sqrt { rm: %s, width: %s, arg: test_case_arg(i) },\n' "$rm_bsv" "$op_bsv"
                printf '            expected_response: RvFpuResponse { result: test_case_expected_result_canonicalized(i), flags: unpack(test_case_expected_flags(i)) }\n'
                printf '        }'
            )" \
            >"$out_f"

        (
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_header" 'TestCaseOneArg'
            "$TESTFLOAT_GEN" -level 2 -tininessafter "-${rm_testfloat}" "${op_testfloat}_${test_case_parts[0]}" |
                test_case_one_arg "$op_nan_box_prefix" "$op_nan_box_prefix"
            printf '%s' "$c_template_one_arg"
            # shellcheck disable=SC2059 # printf with a template
            printf "$c_template_footer" "$op_exponent_mask" "$op_canonical_nan"
        ) >"${out_f}.c"
        ;;

    *)
        echo "unrecognized test case [${test_case}]" >&2
        exit 1
        ;;
esac
