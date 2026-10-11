# claude-statusline.nvim

A [Claude Code](https://docs.claude.com/en/docs/claude-code) status line written in Lua and run by Neovim,
plus a playground in Neovim for tuning it live.

```
 my-app |  main | ████████████████████ 󰊚 42% |  53.3k tok |  +12-3 | 󰙴 Opus 5.5 | 󰚩 Explore·Sonnet 5.5
```

Segments, in order: repo, git branch, context bar (20-block gradient), session tokens, uncommitted diff,
model, and running subagents. You need a Nerd Font and a truecolor terminal.

## Install

lazy.nvim / LazyVim:

```lua
-- lua/plugins/claude-statusline.lua
return {
  "crafts69guy/claude-statusline.nvim",
  main = "claude_statusline",
  cmd = "ClaudeStatusline",
  opts = {
    -- optional: reorder or drop segments (default shown)
    -- segments = { "repo", "branch", "context", "tokens", "diff", "model", "agents" },
  },
}
```

## Use it as the Claude Code status line

The entry script runs without your Neovim config and without lazy.nvim (it sets `package.path` from its own
location). In `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "nvim -l ~/.local/share/nvim/lazy/claude-statusline.nvim/bin/statusline.lua"
  }
}
```

Point it at wherever the plugin is checked out. `opts.segments` only applies inside Neovim (the playground).
The CLI always uses the default order.

## Playground

`:ClaudeStatusline playground` opens a new tab. The left side is an editable JSON fixture. The right side is a
terminal buffer that shows the rendered ANSI line and re-renders as you type. If the JSON is invalid, the preview
shows the decode error.

Fixtures include mock `git` and `agents` keys, so you don't need a real repo or session. Live collect (`gl`)
replaces them with real data read from `workspace.current_dir` and `transcript_path`.

| Key         | Action                                                                                       |
| ----------- | -------------------------------------------------------------------------------------------- |
| `]p` / `[p` | next / previous preset (empty, low, mid, high, critical, subagents, no-git, long-names)      |
| `+` / `-`   | `context_window.used_percentage` ±5                                                          |
| `g1`…`g7`   | toggle segment N on/off (the numbers are shown in the preview winbar)                        |
| `gw`        | also render the line truncated at 40/60/80/100/120 cells                                     |
| `gl`        | toggle live collect (real git + subagents)                                                   |
| `gy` / `gY` | yank the raw ANSI line / the current JSON (into `"` and `+`)                                 |
| `q`         | close the playground tab                                                                     |

## Development

Requirements: Neovim 0.10+, `stylua`, `selene` (`brew install selene`), and `luarocks` for coverage only.

| Target           | What it does                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `make test`      | `nvim -l tests/run.lua`: self-checks, a headless playground drive, and byte parity with the bash script |
| `make coverage`  | installs luacov into `./.rocks` (repo-local, LuaJIT/5.1) if missing, runs the tests under luacov, prints the summary, and fails below 98% (override with `MIN=`) |
| `make lint`      | `selene lua plugin bin tests` (config: `selene.toml`, plus the `vim.yml` std)                       |
| `make fmt`       | `stylua .`                                                                                         |
| `make fmt-check` | `stylua --check .`                                                                                 |
| `make check`     | runs `fmt-check`, then `lint`, then `coverage`                                                     |
| `make clean`     | removes `.rocks/` and the luacov output                                                            |

```sh
cat fixtures/mid.json | nvim -l bin/statusline.lua
```

The parity test compares against `tests/statusline-command.sh`, a copy of the original bash/jq status line.
Set `CLAUDE_STATUSLINE_BASH` to compare against a different script. Note that the bash script's diff segment never
renders, because it passes `git diff --no-lock-index`, which isn't a valid flag. The parity sandbox is a clean repo,
so this difference doesn't come up.
