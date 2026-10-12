-- Interactive playground: editable JSON fixture (left) + live ANSI preview in a terminal buffer (right).
local Render = require("claude_statusline.render")
local Collect = require("claude_statusline.collect")

local M = {}

M.fixtures = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h") .. "/fixtures"
M.presets = { "empty", "low", "mid", "high", "critical", "subagents", "no-git", "long-names" }
M.widths = { 40, 60, 80, 100, 120 }

local HELP = " ]p/[p preset  +/- ctx  g1-g%d segment  gw widths  gl live  gy ansi  gY json  q quit"

--- Cut an ANSI string to `width` display cells, keeping escape sequences.
---@param s string
---@param width integer
function M.truncate(s, width)
	local out, used, i = {}, 0, 1
	while i <= #s do
		local esc = s:match("^\27%[[%d;]*m", i)
		if esc then
			out[#out + 1] = esc
			i = i + #esc
		else
			local ch = s:match("^[%z\1-\127\194-\244][\128-\191]*", i) or s:sub(i, i)
			used = used + vim.fn.strdisplaywidth(ch)
			if used > width then
				break
			end
			out[#out + 1] = ch
			i = i + #ch
		end
	end
	return table.concat(out) .. "\27[0m"
end

local S -- playground state, one instance at a time

local function segments()
	return vim.tbl_filter(function(name)
		return not S.off[name]
	end, S.segments)
end

local function update_winbars()
	if vim.api.nvim_win_is_valid(S.json_win) then
		vim.wo[S.json_win].winbar = (" preset: %s |"):format(M.presets[S.preset]) .. HELP:format(#S.segments)
	end
	if vim.api.nvim_win_is_valid(S.term_win) then
		local segs = {}
		for i, name in ipairs(S.segments) do
			segs[#segs + 1] = ("%d:%s%s"):format(i, name, S.off[name] and "✗" or "✓")
		end
		vim.wo[S.term_win].winbar = (" live: %s | %s"):format(S.live and "on" or "off", table.concat(segs, " "))
	end
end

local function json_text()
	return table.concat(vim.api.nvim_buf_get_lines(S.json_buf, 0, -1, false), "\n")
end

function M.render()
	if not (S and vim.api.nvim_buf_is_valid(S.term_buf)) then
		return
	end
	local ok, ctx = pcall(vim.json.decode, json_text(), { luanil = { object = true, array = true } })
	local lines
	if not ok or type(ctx) ~= "table" then
		S.ansi = nil
		lines = { "\27[1;38;2;220;40;20mJSON error:\27[0m " .. tostring(ok and "top level must be an object" or ctx) }
	else
		if S.live then
			Collect.run(ctx)
		end
		local okr, line = pcall(Render.render, ctx, { segments = segments() })
		S.ansi = okr and line or nil
		lines = { okr and line or ("\27[1;38;2;220;40;20mrender error:\27[0m " .. tostring(line)) }
		if okr and S.show_widths then
			lines[#lines + 1] = ""
			for _, w in ipairs(M.widths) do
				lines[#lines + 1] = ("\27[2m%3d│\27[0m%s"):format(w, M.truncate(line, w))
			end
		end
	end
	vim.api.nvim_chan_send(S.chan, "\27[H\27[2J\27[3J" .. table.concat(lines, "\r\n"))
	update_winbars()
end

local function load_preset(idx)
	S.preset = (idx - 1) % #M.presets + 1
	local lines = vim.fn.readfile(("%s/%s.json"):format(M.fixtures, M.presets[S.preset]))
	vim.api.nvim_buf_set_lines(S.json_buf, 0, -1, false, lines)
	M.render()
end

local function bump(delta)
	local lines = vim.api.nvim_buf_get_lines(S.json_buf, 0, -1, false)
	for i, l in ipairs(lines) do
		local pre, n, post = l:match('^(.-"used_percentage"%s*:%s*)(%-?[%d%.]+)(.*)$')
		if n and tonumber(n) then
			local v = math.max(0, math.min(100, tonumber(n) + delta))
			vim.api.nvim_buf_set_lines(S.json_buf, i - 1, i, false, { pre .. ("%g"):format(v) .. post })
			return M.render()
		end
	end
	vim.notify("No numeric context_window.used_percentage in the fixture", vim.log.levels.WARN)
end

local function yank(text, what)
	if not text then
		return vim.notify("Nothing to yank (fix the JSON first)", vim.log.levels.WARN)
	end
	vim.fn.setreg('"', text)
	pcall(vim.fn.setreg, "+", text)
	vim.notify("Yanked " .. what)
end

local function close()
	if not pcall(vim.cmd.tabclose) then
		vim.cmd("enew | only")
	end
end

function M.open()
	if S and vim.api.nvim_tabpage_is_valid(S.tab) then
		return vim.api.nvim_set_current_tabpage(S.tab)
	end
	local cfg = require("claude_statusline").opts
	S = { segments = vim.deepcopy(cfg.segments or Render.order), off = {}, live = false, show_widths = false }

	vim.cmd.tabnew()
	S.tab = vim.api.nvim_get_current_tabpage()
	S.json_win, S.json_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	vim.bo[S.json_buf].buftype = "nofile"
	vim.bo[S.json_buf].bufhidden = "wipe"
	vim.bo[S.json_buf].filetype = "json"
	pcall(vim.api.nvim_buf_set_name, S.json_buf, "claude-statusline://fixture.json")

	-- Below the JSON at full width, tall enough for the `gw` width check.
	vim.cmd("rightbelow 10new")
	S.term_win, S.term_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	vim.bo[S.term_buf].bufhidden = "wipe"
	vim.wo[S.term_win].number = false
	vim.wo[S.term_win].relativenumber = false
	vim.wo[S.term_win].signcolumn = "no"
	S.chan = vim.api.nvim_open_term(S.term_buf, {})
	vim.api.nvim_set_current_win(S.json_win)

	local function map(lhs, fn, desc, bufs)
		for _, buf in ipairs(bufs or { S.json_buf }) do
			vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, desc = "ClaudeStatusline: " .. desc })
		end
	end
	map("]p", function()
		load_preset(S.preset + 1)
	end, "next preset")
	map("[p", function()
		load_preset(S.preset - 1)
	end, "previous preset")
	map("+", function()
		bump(5)
	end, "context +5%")
	map("-", function()
		bump(-5)
	end, "context -5%")
	for i, name in ipairs(S.segments) do
		map("g" .. i, function()
			S.off[name] = not S.off[name] or nil
			M.render()
		end, "toggle " .. name)
	end
	map("gw", function()
		S.show_widths = not S.show_widths
		M.render()
	end, "toggle width check")
	map("gl", function()
		S.live = not S.live
		M.render()
	end, "toggle live collect")
	map("gy", function()
		yank(S.ansi, "ANSI line")
	end, "yank ANSI output")
	map("gY", function()
		yank(json_text(), "fixture JSON")
	end, "yank JSON")
	map("q", close, "close", { S.json_buf, S.term_buf })

	vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = S.json_buf, callback = M.render })
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = S.json_buf,
		callback = function()
			S = nil
		end,
	})
	load_preset(3)
end

return M
