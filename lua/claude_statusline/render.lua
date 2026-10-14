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

local function color(opts, role, r, g, b)
	local hex = get(opts, "palette", role)
	return hex and rgb(tonumber(hex:sub(2, 3), 16), tonumber(hex:sub(4, 5), 16), tonumber(hex:sub(6, 7), 16))
		or rgb(r, g, b)
end

local function display(s, opts)
	return get(opts, "palette") and s:gsub("[%z\1-\31\127]", "") or s
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

function M.segments.repo(ctx, opts)
	local name = str(get(ctx, "workspace", "repo", "name")) or vim.fs.basename(dir(ctx))
	return BOLD .. color(opts, "text.accent", 255, 210, 0) .. ICON.repo .. " " .. display(name, opts) .. RST
end

---@param ctx table
---@param opts? claude_statusline.Config
---@return string
function M.segments.directory(ctx, opts)
	return color(opts, "text.primary", 255, 210, 0) .. BOLD .. display(vim.fs.basename(dir(ctx)), opts) .. RST
end

function M.segments.branch(ctx, opts)
	local branch = str(get(ctx, "git", "branch"))
	return branch
		and BOLD .. color(opts, "accent.secondary", 0, 220, 220) .. ICON.branch .. " " .. display(branch, opts) .. RST
end

function M.segments.context(ctx, opts)
	if get(opts, "palette") then
		-- A fresh session reports no usage yet; draw it as an empty bar.
		local used = num(get(ctx, "context_window", "used_percentage"))
		used = used == used and math.max(0, math.min(100, used)) or 0
		local filled = math.min(math.floor(used * 20 / 100), 20)
		local fallback = { ["status.success"] = "#00DC50", ["status.warning"] = "#DCC800", ["status.error"] = "#DC2814" }
		local function hex(role)
			local h = get(opts, "palette", role) or fallback[role]
			return tonumber(h:sub(2, 3), 16), tonumber(h:sub(4, 5), 16), tonumber(h:sub(6, 7), 16)
		end
		local function mix(a, b, t)
			local r1, g1, b1 = hex(a)
			local r2, g2, b2 = hex(b)
			return rgb(
				math.floor(r1 + (r2 - r1) * t + 0.5),
				math.floor(g1 + (g2 - g1) * t + 0.5),
				math.floor(b1 + (b2 - b1) * t + 0.5)
			)
		end
		local out = {}
		for i = 0, filled - 1 do
			local c = i <= 10 and mix("status.success", "status.warning", i / 10)
				or mix("status.warning", "status.error", (i - 10) / 9)
			out[#out + 1] = c .. "█"
		end
		if filled < 20 then
			local role = get(opts, "palette", "border.faint") and "border.faint" or "border.subtle"
			out[#out + 1] = color(opts, role, 60, 60, 60) .. ("█"):rep(20 - filled)
		end
		local role = used < 20 and "status.success" or used < 90 and "status.warning" or "status.error"
		local icon = used < 20 and "󰾆" or used < 70 and "󰊚" or used < 90 and "󰓅" or "󰀦"
		return table.concat(out)
			.. RST
			.. " "
			.. color(opts, role, 150, 150, 150)
			.. BOLD
			.. icon
			.. " "
			.. ("%.0f%%"):format(used)
			.. RST
	end
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

function M.segments.tokens(ctx, opts)
	local total = num(get(ctx, "context_window", "total_input_tokens"))
		+ num(get(ctx, "context_window", "total_output_tokens"))
	return color(opts, "text.accent", 255, 210, 0) .. BOLD .. ICON.tokens .. " " .. M.tokens(total) .. " tok" .. RST
end

function M.segments.diff(ctx, opts)
	local add, del = num(get(ctx, "git", "added")), num(get(ctx, "git", "deleted"))
	if add <= 0 and del <= 0 then
		return nil
	end
	local plus = color(opts, "status.success", 0, 220, 80) .. BOLD .. "+" .. add .. RST
	local minus = color(opts, "status.error", 220, 60, 40) .. BOLD .. "-" .. del .. RST
	return color(opts, "text.secondary", 150, 150, 150) .. ICON.diff .. " " .. plus .. minus
end

function M.segments.model(ctx, opts)
	local name = str(get(ctx, "model", "display_name")) or "Claude"
	return color(opts, "accent.primary", 200, 80, 220) .. BOLD .. "󰙴 " .. display(name, opts) .. RST
end

function M.segments.agents(ctx, opts)
	local list = {}
	for _, a in ipairs(type(ctx.agents) == "table" and ctx.agents or {}) do
		local t = str(get(a, "type")) or "agent"
		list[#list + 1] = t .. "·" .. (M.model_name(get(a, "model")) or "…")
	end
	return #list > 0
			and color(opts, "status.info", 120, 170, 255) .. BOLD .. "󰚩 " .. display(table.concat(list, ", "), opts) .. RST
		or nil
end

M.order = { "repo", "branch", "context", "tokens", "diff", "model", "agents" }

---@param ctx table decoded Claude JSON plus `git` and `agents`
---@param opts? claude_statusline.Config ordered segment names and optional semantic palette
---@return string
function M.render(ctx, opts)
	ctx = type(ctx) == "table" and ctx or {}
	local parts = {}
	for _, name in ipairs(get(opts, "segments") or M.order) do
		local seg = M.segments[name]
		local s = seg and seg(ctx, opts)
		if s then
			parts[#parts + 1] = s
		end
	end
	local sep = get(opts, "palette") and (" " .. DIM .. color(opts, "border.subtle", 90, 90, 90) .. "|" .. RST .. " ")
		or M.SEP
	return table.concat(parts, sep)
end

return M
