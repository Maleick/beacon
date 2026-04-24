#!/usr/bin/env node
import { parseArgs } from "node:util";
import {
  mkdir,
  writeFile,
  readFile,
  copyFile,
  readdir,
  stat,
} from "node:fs/promises";
import { resolve, join } from "node:path";
import { homedir } from "node:os";

const PACKAGE_ROOT = resolve(import.meta.dirname, "..");
const VERSION = (await readFile(join(PACKAGE_ROOT, "VERSION"), "utf8")).trim();

interface Config {
  plugin?: string[];
  [key: string]: unknown;
}

function resolveConfigDir(): string {
  if (process.env.OPENCODE_CONFIG_DIR) {
    return process.env.OPENCODE_CONFIG_DIR;
  }
  if (process.env.XDG_CONFIG_HOME) {
    return join(process.env.XDG_CONFIG_HOME, "opencode");
  }
  return join(homedir(), ".config", "opencode");
}

async function copyDir(src: string, dest: string): Promise<void> {
  await mkdir(dest, { recursive: true });
  const entries = await readdir(src);
  for (const entry of entries) {
    const srcPath = join(src, entry);
    const destPath = join(dest, entry);
    const st = await stat(srcPath);
    if (st.isDirectory()) {
      await copyDir(srcPath, destPath);
    } else {
      await copyFile(srcPath, destPath);
    }
  }
}

async function loadConfig(path: string): Promise<Config> {
  try {
    return JSON.parse(await readFile(path, "utf8"));
  } catch {
    return {};
  }
}

async function saveConfig(path: string, config: Config): Promise<void> {
  await writeFile(path, JSON.stringify(config, null, 2) + "\n", "utf8");
}

async function install() {
  const configDir = resolveConfigDir();
  const autoshipDir = join(configDir, ".autoship");

  console.log(`Installing opencode-autoship v${VERSION} to ${configDir}`);

  await mkdir(autoshipDir, { recursive: true });

  const items = [
    { src: join(PACKAGE_ROOT, "hooks"), dest: join(autoshipDir, "hooks") },
    { src: join(PACKAGE_ROOT, "commands"), dest: join(autoshipDir, "commands") },
    { src: join(PACKAGE_ROOT, "skills"), dest: join(autoshipDir, "skills") },
    { src: join(PACKAGE_ROOT, "AGENTS.md"), dest: join(autoshipDir, "AGENTS.md") },
    { src: join(PACKAGE_ROOT, "VERSION"), dest: join(autoshipDir, "VERSION") },
  ];

  for (const item of items) {
    try {
      const st = await stat(item.src);
      if (st.isDirectory()) {
        await copyDir(item.src, item.dest);
      } else {
        await copyFile(item.src, item.dest);
      }
    } catch {
      console.warn(`Warning: ${item.src} not found, skipping`);
    }
  }

  const configPath = join(configDir, "opencode.json");
  let config = await loadConfig(configPath);

  const newPlugin = "opencode-autoship";
  let plugins = config.plugin ?? [];
  if (typeof plugins === "string") {
    plugins = [plugins];
  }
  if (!plugins.includes(newPlugin)) {
    plugins = [...plugins, newPlugin];
  }

  plugins = plugins.filter(
    (p) =>
      typeof p === "string" &&
      !p.includes("autoship.ts") &&
      !p.endsWith("/autoship.ts")
  );

  config.plugin = plugins;
  await saveConfig(configPath, config);

  console.log(`\nSuccessfully installed opencode-autoship v${VERSION}`);
  console.log(`Config: ${configPath}`);
  console.log("\nNext: Run 'opencode-autoship --help' to get started");
}

async function doctor() {
  console.log("opencode-autoship doctor");
  console.log("=====================");
  console.log("This command is not yet implemented.");
  console.log("Full diagnostics will be available in future releases.");
}

function help() {
  console.log(`opencode-autoship v${VERSION}

Usage: opencode-autoship <command>

Commands:
  install   Install opencode-autoship to OpenCode config directory
  doctor   Run diagnostics (not yet implemented)
  help     Show this help message

Examples:
  opencode-autoship install
  opencode-autoship doctor
`);
}

async function main() {
  const args = process.argv.slice(2);
  const command = args[0] ?? "help";

  switch (command) {
    case "install":
      await install();
      break;
    case "doctor":
      await doctor();
      break;
    case "help":
    case "--help":
    case "-h":
      help();
      break;
    default:
      console.error(`Unknown command: ${command}`);
      help();
      process.exit(1);
  }
}

main().catch((err) => {
  console.error("Error:", err.message);
  process.exit(1);
});