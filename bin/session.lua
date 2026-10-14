-- Launcher helper: validate the palette before emitting session-only settings.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. package.path
local Config = require("claude_statusline.config")
if #arg ~= 3 then
	-- selene: allow(incorrect_standard_library_use)
	io.stderr:write("claude-statusline: usage: session.lua <mood> <entry> <config>\n")
	os.exit(1)
end
local cfg, err = Config.load(arg[3])
if not cfg then
	-- selene: allow(incorrect_standard_library_use)
	io.stderr:write("claude-statusline: " .. err .. "\n")
	os.exit(1)
end
io.write(Config.settings(arg[1], arg[2], arg[3]), "\n")
