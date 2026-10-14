local M = {}

---@class claude_statusline.Config
---@field segments? string[] ordered segment names (see render.order); omit one to disable it
---@field palette? table<string, string> semantic roles mapped to #RRGGBB
M.opts = {}

---@param opts? claude_statusline.Config
function M.setup(opts)
	M.opts = vim.tbl_deep_extend("force", M.opts, opts or {})
	M.create_command()
end

M.subcommands = {
	playground = function()
		require("claude_statusline.playground").open()
	end,
}

function M.create_command()
	vim.api.nvim_create_user_command("ClaudeStatusline", function(o)
		local name = o.fargs[1] or "playground"
		local run = M.subcommands[name]
		if not run then
			return vim.notify("ClaudeStatusline: unknown subcommand " .. name, vim.log.levels.ERROR)
		end
		run()
	end, {
		nargs = "?",
		desc = "Claude Code status line",
		complete = function()
			return vim.tbl_keys(M.subcommands)
		end,
	})
end

return M
