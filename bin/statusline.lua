-- Claude Code status line entry: `nvim -l /path/to/bin/statusline.lua` (session JSON on stdin).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local ok, ctx = pcall(vim.json.decode, io.read("*a") or "", { luanil = { object = true, array = true } })
ctx = ok and type(ctx) == "table" and ctx or {}
require("claude_statusline.collect").run(ctx)
io.write(require("claude_statusline.render").render(ctx), "\n")
