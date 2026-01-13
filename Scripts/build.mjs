#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";

const scriptDir = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);

const exitWith = (result) => {
  if (result.error) {
    console.error(result.error.message);
    process.exit(1);
  }
  process.exit(result.status ?? 1);
};

const runScript = (scriptName, extraArgs = []) => {
  const scriptPath = join(scriptDir, scriptName);
  const result = spawnSync("bash", [scriptPath, ...extraArgs, ...args], {
    stdio: "inherit",
  });
  exitWith(result);
};

switch (process.platform) {
  case "darwin":
    runScript("build.sh");
    break;
  case "linux":
    runScript("build-linux.sh");
    break;
  case "win32": {
    const scriptPath = join(scriptDir, "build.ps1");
    const pwshArgs = ["-File", scriptPath, ...args];
    let result = spawnSync("pwsh", pwshArgs, { stdio: "inherit" });
    if (result.error && result.error.code === "ENOENT") {
      result = spawnSync("powershell", pwshArgs, { stdio: "inherit" });
    }
    exitWith(result);
    break;
  }
  default:
    console.error(`Unsupported platform: ${process.platform}`);
    process.exit(1);
}
