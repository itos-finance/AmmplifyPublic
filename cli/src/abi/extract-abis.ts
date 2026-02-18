import { readFileSync, writeFileSync } from "fs";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";

const __dirname = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(__dirname, "../../../out");

const abis: Record<string, string> = {
  IMaker: "IMaker.sol/IMaker.json",
  ITaker: "ITaker.sol/ITaker.json",
  IView: "IView.sol/IView.json",
  IAdmin: "IAdmin.sol/IAdmin.json",
  IUniswapV3Pool: "IUniswapV3Pool.sol/IUniswapV3Pool.json",
  IERC20: "ERC20.sol/ERC20.json",
};

for (const [name, path] of Object.entries(abis)) {
  const fullPath = resolve(outDir, path);
  const json = JSON.parse(readFileSync(fullPath, "utf-8"));
  const abi = JSON.stringify(json.abi, null, 2);

  const output = `export const ${name}Abi = ${abi} as const;\n`;
  const outFile = resolve(__dirname, `${name}.ts`);
  writeFileSync(outFile, output);
  console.log(`Extracted ${name} -> ${outFile}`);
}

console.log("ABI extraction complete.");
