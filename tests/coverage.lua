-- Run after `COVERAGE=1 nvim -l tests/run.lua`: writes luacov.report.out, prints the summary, gates on MIN.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/.rocks/share/lua/5.1/?.lua;" .. root .. "/.rocks/share/lua/5.1/?/init.lua;" .. package.path
local min = tonumber(vim.env.MIN) or 98

require("luacov.runner").load_config(root .. "/.luacov")
require("luacov.reporter").report()
local report = table.concat(vim.fn.readfile(root .. "/luacov.report.out"), "\n")
local summary = report:match("\n(=+\nSummary\n.*)$") or report
-- Paths are absolute; drop the repo prefix and shrink the header/rule/total padding to match.
local cut = #root + 1
local pretty = summary:gsub(vim.pesc(root .. "/"), ""):gsub("[^\n]+", function(l)
	if l:find("^File") or l:find("^Total") then
		return (l:gsub(" " .. (" "):rep(cut), " ", 1))
	elseif l:find("^%-+$") then
		return l:sub(cut + 1)
	end
end)
io.write(pretty, "\n")

local total = tonumber(summary:match("Total%s+%d+%s+%d+%s+([%d%.]+)%%"))
if not total or total < min then
	io.write(("coverage %s%% < %d%%\n"):format(tostring(total), min))
	os.exit(1)
end
io.write(("coverage %.2f%% >= %d%%\n"):format(total, min))
