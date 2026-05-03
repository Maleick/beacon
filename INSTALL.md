# Install AutoShip

AutoShip is an OpenCode plugin that turns GitHub issues into verified pull requests. It plans eligible issues, dispatches OpenCode workers, verifies results, and creates pull requests with local runtime state in `.autoship/`.

## OpenCode Handoff

Paste this into OpenCode if you want the agent to install and verify AutoShip for you:

```text
Fetch and follow instructions from https://raw.githubusercontent.com/Maleick/AutoShip/refs/tags/v2.2.1/INSTALL.md
```

## Prerequisites

- OpenCode installed and available in your shell.
- Node.js 18 or newer with npm, or Bun for one-time package execution.
- Git installed and available in your shell.
- GitHub CLI (`gh`) authenticated with access to the target repository.
- `jq` installed and available on `PATH`.
- A GitHub repository with issues labeled `agent:ready`.

## npm Global Install

For normal OpenCode usage, install the CLI globally and register the bundled plugin assets:

```bash
npm install -g opencode-autoship
opencode-autoship install
opencode-autoship doctor
```

Restart OpenCode after installation. Then open the target repository and run:

```text
/autoship-setup
/autoship
```

## One-Time Bun Path

If your environment supports one-time package execution through Bun:

```bash
bunx opencode-autoship install
bunx opencode-autoship doctor
```

Use the npm global install for long-term usage.

## OpenCode Plugin Assets

`opencode-autoship install` updates your OpenCode config and copies bundled assets into the OpenCode config directory:

```text
~/.config/opencode/opencode.json
~/.config/opencode/.autoship/
```

The installer adds `opencode-autoship` to the top-level `plugin` array without removing unrelated settings.

## Project Setup

Run setup inside the repository you want AutoShip to operate on:

```text
/autoship-setup
```

Setup discovers live models from `opencode models`, writes `.autoship/config.json`, and writes `.autoship/model-routing.json`. Do not commit `.autoship/`; it is local runtime state.

## Verification

These checks do not require publishing credentials:

```bash
npm view opencode-autoship version
npm view opencode-autoship dist-tags
opencode-autoship doctor
```

For a local clone:

```bash
npm install
npm run build
npm run typecheck
bash hooks/opencode/verify-package.sh
bash hooks/opencode/check.sh
bash -n hooks/opencode/*.sh hooks/*.sh
```

To verify command availability, restart OpenCode in a GitHub-backed repository and run:

```text
/autoship-status
```

## Updating

For npm global installs:

```bash
npm install -g opencode-autoship@latest
opencode-autoship install
opencode-autoship doctor
```

For reproducible installs, pin a published version:

```bash
npm install -g opencode-autoship@2.2.1
opencode-autoship install
```

## Troubleshooting

### Plugin Not Loading

- Confirm `opencode.json` is valid JSON.
- Confirm `opencode-autoship` appears in the top-level `plugin` array.
- Restart OpenCode after changing the config.
- Rerun `opencode-autoship install` if commands are missing.

### Doctor Reports Missing Project Config

- Open the target GitHub repository in OpenCode.
- Run `/autoship-setup` from that repository.
- Confirm `.autoship/config.json` and `.autoship/model-routing.json` exist locally.

### No Issues Are Planned

- Confirm `gh auth status` succeeds.
- Confirm the repository has open GitHub issues labeled `agent:ready`.
- Check `/autoship-plan` before starting `/autoship`.

### Runtime State

- Do not commit `.autoship/`; it is project-local runtime state.
- Use `/autoship-stop` before manually cleaning running workspaces.
- Run `opencode-autoship doctor` after upgrading.

## Links

- OpenCode install details: https://github.com/Maleick/AutoShip/blob/main/docs/OPENCODE_INSTALL.md
- OpenCode agent install entrypoint: https://github.com/Maleick/AutoShip/blob/main/.opencode/INSTALL.md
- Releases: https://github.com/Maleick/AutoShip/releases
- Issues: https://github.com/Maleick/AutoShip/issues
