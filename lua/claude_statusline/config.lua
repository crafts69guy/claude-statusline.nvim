local M = {}

--- Read and validate a renderer config; return a diagnostic instead of raising.
---@param path string
---@return claude_statusline.Config? config
---@return string? diagnostic
function M.load(path)
	local f = io.open(path, "rb")
	if not f then
		return nil, "cannot read config: " .. path
	end
	local body = f:read("*a")
	f:close()
	local ok, cfg = pcall(vim.json.decode, body)
	if not ok or type(cfg) ~= "table" or type(cfg.palette) ~= "table" or type(cfg.segments) ~= "table" then
		return nil, "config requires palette and segments objects"
	end
	local roles = {
		"text.primary",
		"text.secondary",
		"text.accent",
		"accent.primary",
		"accent.secondary",
		"border.subtle",
		"status.success",
		"status.warning",
		"status.error",
		"status.info",
	}
	for _, role in ipairs(roles) do
		if cfg.palette[role] == nil then
			return nil, "missing palette role: " .. role
		end
	end
	for role, hex in pairs(cfg.palette) do
		if type(role) ~= "string" or type(hex) ~= "string" or not hex:match("^#%x%x%x%x%x%x$") then
			return nil, "palette values must be #RRGGBB"
		end
	end
	if not vim.islist(cfg.segments) then
		return nil, "segments must be an array"
	end
	for _, name in ipairs(cfg.segments) do
		if type(name) ~= "string" or not require("claude_statusline.render").segments[name] then
			return nil, "unknown segment: " .. tostring(name)
		end
	end
	return cfg
end

--- Encode Claude session settings with shell-escaped statusline command paths.
---@param mood string Hue mood identifier
---@param entry string absolute Lua entry path
---@param config string absolute renderer config path
---@return string JSON settings
function M.settings(mood, entry, config)
	return vim.json.encode({
		theme = "custom:hue-theme:hue-" .. mood,
		statusLine = {
			type = "command",
			command = "nvim -l " .. vim.fn.shellescape(entry) .. " --config " .. vim.fn.shellescape(config),
		},
	})
end

return M
