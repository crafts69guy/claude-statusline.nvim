-- Claude Code status line entry: `nvim -l /path/to/bin/statusline.lua` (session JSON on stdin).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local opts
if #arg > 0 then
	local err
	if arg[1] == "--config" and #arg == 2 then
		opts, err = require("claude_statusline.config").load(arg[2])
	else
		err = "usage: statusline.lua [--config <file>]"
	end
	if err then
		-- selene: allow(incorrect_standard_library_use)
		io.stderr:write("claude-statusline: " .. err .. "\n")
		os.exit(1)
	end
end
local ok, ctx = pcall(vim.json.decode, io.read("*a") or "", { luanil = { object = true, array = true } })
ctx = ok and type(ctx) == "table" and ctx or {}
require("claude_statusline.collect").run(ctx, opts)
io.write(require("claude_statusline.render").render(ctx, opts), "\n")
