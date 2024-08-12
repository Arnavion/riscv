#!/bin/bash

set -euo pipefail

usage() {
	echo "Usage: $0 [--flatten] [--lut <MAX_ADDRESS_WIDTH>] [--parameter <NAME> <VALUE>] [--top <MODULE_NAME>] <file.sv|file.v>"
}

f=''
flatten=''
lut=''
declare -A parameters
top=''

while (( $# )); do
	case "$1" in
		'--help')
			usage
			exit 0
			;;

		'--flatten')
			flatten='1'
			;;

		'--lut')
			shift
			if [ -z "${1:-}" ]; then
				usage >&2
				exit 1
			fi
			lut="$1"
			;;

		'--parameter')
			shift
			if [ -z "${1:-}" ]; then
				usage >&2
				exit 1
			fi
			parameter_name="$1"
			shift
			if [ -z "${1:-}" ]; then
				usage >&2
				exit 1
			fi
			parameters[$parameter_name]="$1"
			;;

		'--top')
			shift
			if [ -z "${1:-}" ]; then
				usage >&2
				exit 1
			fi
			top="$1"
			;;

		*)
			if [ -z "$f" ]; then
				f="$1"
			else
				usage >&2
				exit 1
			fi
			;;
	esac

	shift
done

if [ -z "${f:-}" ]; then
	usage >&2
	exit 1
fi

if [[ "$f" == *.sv ]]; then
	if [ -z "$top" ]; then
		top="$(basename "$f")"
		top="${top%.sv}"
	fi
	if yosys -p "read_verilog -sv $f" &>/dev/null; then
		command="read_verilog -defer -sv $f
"
	else
		# `--exclude=Always` ought to be included, but sv2v miscompiles `foreach` loops and `for` loops containing declarations.
		#
		# Ref: https://github.com/zachjs/sv2v/issues/319
		sv2v \
			--exclude=Assert \
			--exclude=Interface \
			--exclude=Logic \
			--exclude=SeverityTask \
			--exclude=UnbasedUnsized \
			--top "$top" \
			"$f" >"tc/sv/vis/$top.sv"
		trap "rm -f 'tc/sv/vis/$top.sv'" EXIT
		command="read_verilog -defer -sv tc/sv/vis/$top.sv
"
	fi
elif [[ "$f" == *.v ]]; then
	if [ -z "$top" ]; then
		top="$(basename "$f")"
		top="${top%.v}"
	fi
	command="read_verilog -defer $f
"
else
	usage >&2
	exit 1
fi

for parameter_name in ${!parameters[@]}; do
	command="${command}chparam -set $parameter_name ${parameters[$parameter_name]} $top
"
done

command="${command}hierarchy -top $top
"

if [ -n "$flatten" ]; then
command="${command}flatten
"
fi

if [ -n "$lut" ]; then
	command="${command}synth -top $top -flowmap -lut $lut
"
else
	command="${command}proc
opt
memory -nomap
wreduce -mux_undef
opt -full
"
fi

command="${command}write_json tc/sv/vis/netlist.json
"

yosys -p "$command"

if ! [ -d tc/sv/vis/node_modules ]; then
	podman run -i --rm -v "$PWD/tc/sv/vis:/src" docker.io/node bash -c 'cd /src && npm install'
fi

<tc/sv/vis/netlist.json podman run -i --rm -v "$PWD/tc/sv/vis:/src" docker.io/node node /src/index.js "$top" "$(xdg-user-dir DOWNLOAD)" >"$PWD/tc/sv/vis/vis.html"

rm tc/sv/vis/netlist.json

echo "xdg-open file://${PWD}/tc/sv/vis/vis.html"
