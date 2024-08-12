import { argv, stdin, stdout } from "node:process"
import { text } from "node:stream/consumers"

import { transformCircuit } from "./node_modules/digitaljs/src/transform.mjs";
import { yosys2digitaljs, io_ui } from "yosys2digitaljs";

function write(out, s) {
	return new Promise((resolve, reject) => {
		out.write(s, err => {
			if (err === null) {
				resolve();
			}
			else {
				reject(err);
			}
		})
	});
}

const fileName = argv[2];

const downloadsDirectory = argv[3];
if (typeof downloadsDirectory !== "string") {
	throw new Error(`Usage: ${argv[0]} ${argv[1]} <DOWNLOADS_DIRECTORY>`);
}

await write(stdout, `
<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
		<script type="text/javascript" src="./node_modules/digitaljs/dist/main.js" charset="utf-8"></script>
		<script>
`);

const netlistJson = await text(process.stdin);
const netlist = JSON.parse(netlistJson);
for (const [_, module] of Object.entries(netlist.modules)) {
	let idsToDelete = [];
	for (const [id, cell] of Object.entries(module.cells)) {
		if (cell.type === "$scopeinfo") {
			idsToDelete.push(id);
		}
	}
	for (const id of idsToDelete) {
		delete module.cells[id];
	}
}
let topModule = yosys2digitaljs(netlist);
io_ui(topModule);
topModule = transformCircuit(topModule);
const topModuleString = JSON.stringify(topModule, (_, value) => typeof value === 'bigint' ? value.toString() : value);

await write(stdout, `
			addEventListener("load", () => {
				document.getElementById("export_png").addEventListener("click", () => {
					let svg = document.querySelector("#paper > svg");
					const width = svg.clientWidth;
					const height = svg.clientHeight;
					svg = svg.cloneNode(true);

					svg.setAttribute("width", \`\${ width }px\`);
					svg.setAttribute("height", \`\${ height }px\`);

					{
						let zoom = "";
						if (width > 32767 || height > 32767) {
							zoom = \`--zoom \${ 32767 / Math.max(width, height) } \`;
						}
						const rasterizeCommand = document.getElementById("rasterize_command");
						rasterizeCommand.innerText = \`rsvg-convert --output '${ downloadsDirectory }/${ fileName }.png' \${ zoom }'${ downloadsDirectory }/${ fileName }.svg'\`;
					}

					{
						const url =
							URL.createObjectURL(
								new File(
									[
										new XMLSerializer().serializeToString(svg),
									],
									"${ fileName }.svg",
									{ type: "image/svg+xml" },
								),
							);
						const anchor = document.createElement("a");
						anchor.href = url;
						anchor.download = "${ fileName }.svg";
						anchor.click();
					}
				});

				const circuit = new digitaljs.Circuit(${ topModuleString }, { engine: digitaljs.engines.BrowserSynchEngine });
				const paper = circuit.displayOn(document.querySelector("#paper"));
				circuit.start();
			});
		</script>
	</head>
	<body>
		<div>
			<button id="export_png">Export to .png</button>
		</div>
		<div id="rasterize_command"></div>
		<div id="paper"></div>
	</body>
</html>
`);
