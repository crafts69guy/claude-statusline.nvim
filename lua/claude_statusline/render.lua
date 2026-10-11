-- Pure renderer: Claude Code session JSON (+ `git`, `agents`) -> one ANSI line.
-- Output mirrors the original bash/jq status line byte for byte.
local M = {}

local function rgb(r, g, b)
	return ("\27[38;2;%d;%d;%dm"):format(r, g, b)
end
local BOLD, DIM, RST = "\27[1m", "\27[2m", "\27[0m"
-- Nerd Font icons as byte escapes (private-use glyphs are invisible in many editors).
local ICON = {
	repo = "\239\144\129", -- U+F401
	branch = "\239\144\152", -- U+F418
	tokens = "\239\145\169", -- U+F469
	diff = "\239\147\146", -- U+F4D2
}
M.SEP = " " .. DIM .. rgb(90, 90, 90) .. "|" .. RST .. " "

--- Walk nested tables; nil on any non-table hop or JSON null.
local function get(t, ...)
	for i = 1, select("#", ...) do
		if type(t) ~= "table" then
			return nil
		end
		t = t[select(i, ...)]
	end
	if t == vim.NIL then
		return nil
	end
	return t
end

local function str(v)
	return type(v) == "string" and v ~= "" and v or nil
end

local function num(v)
	return tonumber(v) or 0
end

--- claude-sonnet-5-5 -> Sonnet 5.5; unparseable ids pass through capitalized.
function M.model_name(id)
	id = str(id)
	if not id then
		return nil
	end
	local fam, major, minor = id:match("^claude%-(%l+)%-(%d+)%-(%d+)")
	local name = fam and ("%s %s.%s"):format(fam, major, minor) or id
	return name:sub(1, 1):upper() .. name:sub(2)
end

--- Session tokens: 999 -> "999", 12345 -> "12.3k".
function M.tokens(n)
	n = math.floor(n)
	return n >= 1000 and ("%.1fk"):format(n / 1000) or tostring(n)
end

local function dir(ctx)
	return str(get(ctx, "workspace", "current_dir")) or vim.uv.cwd()
end

M.segments = {}

function M.segments.repo(ctx)
	local name = str(get(ctx, "workspace", "repo", "name")) or vim.fs.basename(dir(ctx))
	return BOLD .. rgb(255, 210, 0) .. ICON.repo .. " " .. name .. RST
end

function M.segments.branch(ctx)
	local branch = str(get(ctx, "git", "branch"))
	return branch and BOLD .. rgb(0, 220, 220) .. ICON.branch .. " " .. branch .. RST
end

function M.segments.context(ctx)
	local used = tonumber(("%.0f"):format(num(get(ctx, "context_window", "used_percentage"))))
	local filled = math.min(math.floor(used * 20 / 100), 20)
	local icon, pct
	if used < 20 then
		icon, pct = "󰾆", rgb(0, 220, 80)
	elseif used < 70 then
		icon, pct = "󰊚", rgb(220, 200, 0)
	elseif used < 90 then
		icon, pct = "󰓅", rgb(220, 100, 0)
	else
		icon, pct = "󰀦", rgb(220, 40, 20)
	end
	-- gradient green(0,200,80) -> yellow(220,200,0) at block 10 -> red
	local out = {}
	for i = 0, filled - 1 do
		local r, g, b
		if i <= 10 then
			r, g, b = i * 22, 200, 80 - i * 8
		else
			r, g, b = 220, 200 - (i - 10) * 16, (i - 10) * 2
		end
		out[#out + 1] = rgb(r, math.max(g, 0), math.max(b, 0)) .. "█"
	end
	if filled < 20 then
		out[#out + 1] = rgb(60, 60, 60) .. ("█"):rep(20 - filled)
	end
	return table.concat(out) .. RST .. " " .. pct .. BOLD .. icon .. " " .. ("%d%%"):format(used) .. RST
end

function M.segments.tokens(ctx)
	local total = num(get(ctx, "context_window", "total_input_tokens"))
		+ num(get(ctx, "context_window", "total_output_tokens"))
	return rgb(255, 210, 0) .. BOLD .. ICON.tokens .. " " .. M.tokens(total) .. " tok" .. RST
end

function M.segments.diff(ctx)
	local add, del = num(get(ctx, "git", "added")), num(get(ctx, "git", "deleted"))
	if add <= 0 and del <= 0 then
		return nil
	end
	local plus = rgb(0, 220, 80) .. BOLD .. "+" .. add .. RST
	local minus = rgb(220, 60, 40) .. BOLD .. "-" .. del .. RST
	return rgb(150, 150, 150) .. ICON.diff .. " " .. plus .. minus
end

function M.segments.model(ctx)
	local name = str(get(ctx, "model", "display_name")) or "Claude"
	return rgb(200, 80, 220) .. BOLD .. "󰙴 " .. name .. RST
end

function M.segments.agents(ctx)
	local list = {}
	for _, a in ipairs(type(ctx.agents) == "table" and ctx.agents or {}) do
		local t = str(get(a, "type")) or "agent"
		list[#list + 1] = t .. "·" .. (M.model_name(get(a, "model")) or "…")
	end
	return #list > 0 and rgb(120, 170, 255) .. BOLD .. "󰚩 " .. table.concat(list, ", ") .. RST or nil
end

M.order = { "repo", "branch", "context", "tokens", "diff", "model", "agents" }

---@param ctx table decoded Claude JSON plus `git` and `agents`
---@param opts? { segments?: string[] } ordered segment names; omit one to disable it
---@return string
function M.render(ctx, opts)
	ctx = type(ctx) == "table" and ctx or {}
	local parts = {}
	for _, name in ipairs(get(opts, "segments") or M.order) do
		local seg = M.segments[name]
		local s = seg and seg(ctx)
		if s then
			parts[#parts + 1] = s
		end
	end
	return table.concat(parts, M.SEP)
end

return M
