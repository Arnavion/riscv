#!/bin/bash

set -euo pipefail

usage() {
	echo "Usage: $0 [--engine <digitaljs|netlistsvg>] [--flatten] [--lut <MAX_ADDRESS_WIDTH>] [--parameter <NAME> <VALUE>] [--top <MODULE_NAME>] <file.bsv|file.sv|file.v>"
}

f=''
flatten=''
lut=''
declare -A parameters
top=''
engine='digitaljs'

while (( $# )); do
	case "$1" in
		'--help')
			usage
			exit 0
			;;

		'--engine')
			shift
			if [ -z "${1:-}" ]; then
				usage >&2
				exit 1
			fi
			engine="$1"
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

if [[ "$f" == *.bsv ]]; then
	if [ -z "$top" ]; then
		top="mk$(basename "$f")"
		top="${top%.bsv}"
	fi
	d="$(dirname "$f")"
	(cd "$d" && rm -f *.bo *.v && bsc -verilog -u "$(basename "$f")")
	trap "rm -f $d/*.bo $d/*.v" EXIT
	command=''
	for v in tc/bsv/*.v; do
		command="${command}read_verilog -defer $v
"
	done

elif [[ "$f" == *.sv ]]; then
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
			"$f" >"tc/vis/$top.sv"
		trap "rm -f 'tc/vis/$top.sv'" EXIT
		command="read_verilog -defer -sv tc/vis/$top.sv
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

command="${command}write_json tc/vis/netlist.json
"

yosys -p "$command"

if ! [ -d tc/vis/node_modules ]; then
	podman run -i --rm -v "$PWD/tc/vis:/src" docker.io/node bash -c 'cd /src && npm install'

	# "The netlistsvg situation"
	#
	# netlistsvg package published to npmjs.org is v1.0.2 from the original author's repo https://github.com/nturley/netlistsvg
	# This repo has had occasional commits since v1.0.2 but no new releases. The v1.0.2 release cannot handle current yosys netlist
	# because it enforces a JSON schema that is missing some properties. This is fixed in master.
	#
	# netlistsvg also has a PR at https://github.com/nturley/netlistsvg/pull/92 which contains a nice feature of inlining nested modules.
	# However this PR is based on v1.0.2, and has conflicts when trying to rebase onto master that I can't be bothered to figure out.
	# It also has a bug reported in the comments about a stack overflow from recursion.
	#
	# Teros Technology has their own fork of netlistsvg which they use in their TerosHDL IDE. This fork has the above PR
	# rebased onto a commit close to master, plus a fix for the stack overflow,
	# at https://github.com/TerosTechnology/netlistsvg/tree/hierarchy_fix_recursive . This is the version that I use here.
	#
	# Even this version has a bug that the browser JS version's `render()` entrypoint swallows the config parameter
	# instead of passing it to the internal function. This `sed` fixes that issue.
	sed -i -e 's/^    return lib.render(skinData, netlistData, cb);$/    return lib.render.apply(lib, arguments);/' tc/vis/node_modules/netlistsvg/built/netlistsvg.bundle.js
fi

<tc/vis/netlist.json podman run -i --rm -v "$PWD/tc/vis:/src" docker.io/node node /src/index.js "$top" "$(xdg-user-dir DOWNLOAD)" "$engine" >"$PWD/tc/vis/vis.html"

rm tc/vis/netlist.json

echo "xdg-open file://${PWD}/tc/vis/vis.html"
