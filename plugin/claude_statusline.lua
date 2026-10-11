if vim.g.loaded_claude_statusline then
	return
end
vim.g.loaded_claude_statusline = true

-- `:ClaudeStatusline` works without setup().
require("claude_statusline").create_command()
