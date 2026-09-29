# Logos in the listing preview

`preview.png` (built by `make preview`) shows the coding agents Local AI opens, Omarchy, and the GPU makers whose cards it runs models on, each in a circle joined to Local AI. These marks identify compatibility and nothing else. Each is a trademark of its owner; Local AI is not affiliated with or endorsed by any of them.

| File | Mark | Source | Licence of the file |
|---|---|---|---|
| `pi.svg` | pi | [Simple Icons](https://github.com/simple-icons/simple-icons) `pi` (from pi.dev) | CC0-1.0 |
| `claude-code.svg` | Claude Code | [LobeHub icons](https://github.com/lobehub/lobe-icons) `claudecode` | MIT |
| `codex.svg` | Codex | LobeHub icons `codex` | MIT |
| `opencode.svg` | OpenCode | Simple Icons `opencode` | CC0-1.0 |
| `omp.svg` | omp | [can1357/oh-my-pi](https://github.com/can1357/oh-my-pi) `assets/icon.svg` | MIT |
| `crush.png` | Crush | [charmbracelet/crush](https://github.com/charmbracelet/crush) `internal/ui/notification/crush-icon-solo.png` | Crush's own licence |
| `grok.svg` | Grok | LobeHub icons `grok` | MIT |
| `copilot.svg` | GitHub Copilot | Simple Icons `githubcopilot` | CC0-1.0 |
| `hermes.svg` | Hermes Agent | LobeHub icons `hermesagent` | MIT |
| `omarchy.svg` | Omarchy | Simple Icons `omarchy` | CC0-1.0 |
| `nvidia.svg` | NVIDIA (eye and wordmark) | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:NVIDIA_logo.svg) `NVIDIA logo.svg` | trademark of NVIDIA; see the file's page |
| `intel.svg` | Intel | Simple Icons `intel` | CC0-1.0 |
| `amd.svg` | AMD | Simple Icons `amd` | CC0-1.0 |

The build draws every SVG in one colour from the marketplace's dark theme (omp keeps its own orange) and Crush's heart in grey. The files here are the sources unchanged. To add an agent, put its logo here and name it in `LOGOS` in `../build.py`.
