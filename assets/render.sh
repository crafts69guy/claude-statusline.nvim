#!/usr/bin/env bash
# Render README media with VHS + ffmpeg (same approach as cocoindex.nvim).
#
#   ./assets/render.sh [scene...]
#
# VHS records raw frames (`Output <dir>/`); this script composites the text and
# cursor layers itself, so it works even when VHS's own encoder step does not.
# Neovim runs with a throwaway init that only adds this repo to 'rtp', so the
# media doesn't depend on anyone's config.
# Scenes: statusline playground widths demo (default: all).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
ASSETS="$ROOT/assets"
BG="0x1e1e2e" # Catppuccin Mocha base, matches the VHS theme below
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for bin in vhs ffmpeg nvim; do
	command -v "$bin" >/dev/null || {
		echo "missing: $bin" >&2
		exit 1
	}
done

cat >"$WORK/init.lua" <<EOF
vim.opt.rtp:prepend("$ROOT")
vim.o.termguicolors = true
vim.o.number = true
vim.o.laststatus = 0
vim.o.showtabline = 0
vim.o.shortmess = vim.o.shortmess .. "I"
vim.cmd.colorscheme("default")
vim.api.nvim_set_hl(0, "Normal", { fg = "#cdd6f4" }) -- transparent: VHS theme background shows through
vim.api.nvim_set_hl(0, "WinBar", { fg = "#a6adc8", bg = "#313244", bold = true })
vim.api.nvim_set_hl(0, "WinBarNC", { fg = "#a6adc8", bg = "#313244" })
EOF

# The rendered line per preset, mock git/agents included (what the playground shows).
cat >"$WORK/lines.lua" <<EOF
package.path = "$ROOT/lua/?.lua;" .. package.path
local Render = require("claude_statusline.render")
for _, name in ipairs({ "low", "mid", "high", "critical", "subagents" }) do
	local ctx = vim.json.decode(table.concat(vim.fn.readfile("$ROOT/fixtures/" .. name .. ".json"), "\n"))
	io.write(("\27[2m%-10s\27[0m"):format(name), Render.render(ctx), "\n\n")
end
EOF

header() {
	cat <<EOF
Output "$WORK/$1/"
Set Shell "bash"
Set FontFamily "FiraCode Nerd Font Mono"
Set FontSize 16
Set Width ${2:-1440}
Set Height ${3:-640}
Set Padding 0
Set Framerate 24
Set Theme "Catppuccin Mocha"
Set TypingSpeed 60ms
EOF
}

# Open the playground off camera.
open_playground() {
	cat <<EOF
Hide
Type \`cd "$ROOT" && clear && nvim -u "$WORK/init.lua" -i NONE\`
Enter
Sleep 1500ms
Type ":ClaudeStatusline playground"
Enter
Sleep 800ms
Type ":echo"
Enter
EOF
}

statusline_steps() {
	header statusline 1600 300
	cat <<EOF
Hide
Type \`cd "$ROOT" && clear && nvim -l "$WORK/lines.lua"\`
Enter
Sleep 1500ms
Show
Sleep 500ms
EOF
}

playground_steps() {
	header playground
	open_playground
	cat <<'EOF'
Type "]p]p"
Sleep 500ms
Show
Sleep 500ms
EOF
}

widths_steps() {
	header widths
	open_playground
	cat <<'EOF'
Type "]p]p]p"
Sleep 300ms
Type "gw"
Sleep 500ms
Show
Sleep 500ms
EOF
}

demo_steps() {
	header demo
	open_playground
	cat <<'EOF'
Type "[p"
Sleep 300ms
Show
Sleep 1200ms
Type "]p"
Sleep 1000ms
Type "]p"
Sleep 1000ms
Type "]p"
Sleep 1200ms
Type "]p"
Sleep 1500ms
Type "--"
Sleep 800ms
Type "-"
Sleep 800ms
Type "++"
Sleep 1000ms
Type "g6"
Sleep 1200ms
Type "g6"
Sleep 1000ms
Type "gw"
Sleep 2500ms
Type "gw"
Sleep 600ms
Type "ggA broken"
Sleep 1800ms
Escape
Type "u"
Sleep 1800ms
EOF
}

# Pad the terminal frame so it sits on a card-like background.
PAD="pad=iw+48:ih+48:24:24:color=$BG"

record() {
	local scene=$1
	"${scene}_steps" >"$WORK/$scene.tape"
	vhs -q "$WORK/$scene.tape" >/dev/null
}

still() {
	local scene=$1 text
	record "$scene"
	text=$(ls "$WORK/$scene"/frame-text-*.png | tail -1)
	ffmpeg -y -loglevel error -i "$text" -i "${text/frame-text/frame-cursor}" \
		-filter_complex "overlay,$PAD" "$ASSETS/$scene.png"
	echo "wrote assets/$scene.png"
}

gif() {
	record demo
	ffmpeg -y -loglevel error -framerate 24 -i "$WORK/demo/frame-text-%05d.png" \
		-framerate 24 -i "$WORK/demo/frame-cursor-%05d.png" \
		-filter_complex "[0][1]overlay,$PAD,fps=10,scale=1080:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4" \
		"$ASSETS/demo.gif"
	echo "wrote assets/demo.gif"
}

scenes=("$@")
[[ ${#scenes[@]} -eq 0 ]] && scenes=(statusline playground widths demo)
for scene in "${scenes[@]}"; do
	case $scene in
	demo) gif ;;
	statusline | playground | widths) still "$scene" ;;
	*)
		echo "unknown scene: $scene" >&2
		exit 1
		;;
	esac
done
