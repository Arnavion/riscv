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
	throw new Error(`Usage: ${argv[0]} ${argv[1]} <DOWNLOADS_DIRECTORY> <ENGINE>`);
}

const engine = argv[4];

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

await write(stdout, `
<!DOCTYPE html>
<html>
	<head>
		<meta charset="UTF-8">
`);

switch(engine) {
	case "digitaljs":
		let topModule = yosys2digitaljs(netlist);
		io_ui(topModule);
		topModule = transformCircuit(topModule);
		const topModuleString = JSON.stringify(topModule, (_, value) => typeof value === 'bigint' ? value.toString() : value);

		await write(stdout, `
		<script type="text/javascript" src="../../tc/vis/node_modules/digitaljs/dist/main.js" charset="utf-8"></script>
		<script>
			addEventListener("load", () => {
				const circuit = new digitaljs.Circuit(${ topModuleString }, { engine: digitaljs.engines.BrowserSynchEngine });
				const paper = circuit.displayOn(document.querySelector("#paper"));
				circuit.start();
			});
		</script>
`);
		break;

	case "netlistsvg":
		const netlistString = JSON.stringify(netlist, (_, value) => typeof value === 'bigint' ? value.toString() : value);

		await write(stdout, `
		<script type="text/javascript" src="../../tc/vis/node_modules/elkjs/lib/elk.bundled.js" charset="utf-8"></script>
		<script type="text/javascript" src="../../tc/vis/node_modules/netlistsvg/built/netlistsvg.bundle.js" charset="utf-8"></script>
		<script>
			addEventListener("load", async () => {
				const circuit = await netlistsvg.render(netlistsvg.digitalSkin, ${ netlistString }, undefined, undefined, {
					"hierarchy": {
						"enable": "all",
						"expandLevel": 0,
						"expandModules": {
							"types": [],
							"ids": []
						}
					},
					"top": {
						"enable": false,
						"module": ""
					}
				});
				const paper = document.querySelector("#paper");
				paper.innerHTML = circuit;
			});
		</script>
`);
		break;

	default:
		throw new Error(`unknown engine ${ engine }, expected "digitaljs" or "netlistsvg"`);
}

await write(stdout, `
		<script>
			addEventListener("load", () => {
				document.getElementById("export").addEventListener("click", () => {
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
			});
		</script>
	</head>
	<body>
		<div>
			<button id="export">Export to .svg</button>
		</div>
		<div id="rasterize_command"></div>
		<div id="paper"></div>
	</body>
</html>
`);
