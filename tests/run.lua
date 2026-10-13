-- Run: nvim -l tests/run.lua
-- Parity against the original bash script (tests/statusline-command.sh, override with CLAUDE_STATUSLINE_BASH).
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
if vim.env.COVERAGE then
	package.path = root .. "/.rocks/share/lua/5.1/?.lua;" .. root .. "/.rocks/share/lua/5.1/?/init.lua;" .. package.path
	jit.off() -- traced code skips line hooks
	require("luacov.runner")(root .. "/.luacov")
end

local Render = require("claude_statusline.render")
local Collect = require("claude_statusline.collect")
local Playground = require("claude_statusline.playground")

local failures, total = 0, 0
local function test(name, fn)
	total = total + 1
	local ok, err = pcall(fn)
	io.write(ok and "ok   " or "FAIL ", name, ok and "\n" or ("\n     " .. tostring(err) .. "\n"))
	failures = failures + (ok and 0 or 1)
end
local function has(s, sub)
	assert(s:find(sub, 1, true), ("missing %q in %q"):format(sub, s))
end
local function hasnt(s, sub)
	assert(not s:find(sub, 1, true), ("unexpected %q in %q"):format(sub, s))
end
local function decode(s)
	return vim.json.decode(s, { luanil = { object = true, array = true } })
end
local function ctx_used(p)
	return { workspace = { current_dir = "/x/app" }, context_window = { used_percentage = p } }
end

local fixtures = vim.fn.glob(root .. "/fixtures/*.json", false, true)

test("every fixture renders", function()
	assert(#fixtures >= 8)
	for _, f in ipairs(fixtures) do
		local line = Render.render(decode(table.concat(vim.fn.readfile(f), "\n")))
		has(line, "\27[1m\27[38;2;255;210;0m\239\144\129 ")
		has(line, " tok")
	end
end)

test("garbage input never errors", function()
	Render.render({})
	Render.render(nil)
	Render.render({ context_window = 5, model = "x", git = { added = "nope" }, agents = { 1, {} } })
	Render.render({ context_window = { used_percentage = "abc", total_input_tokens = vim.NIL } })
end)

test("icon/colour thresholds 20/70/90", function()
	local cases = {
		{ 0, "󰾆", "0;220;80" },
		{ 19, "󰾆", "0;220;80" },
		{ 20, "󰊚", "220;200;0" },
		{ 69, "󰊚", "220;200;0" },
		{ 70, "󰓅", "220;100;0" },
		{ 89, "󰓅", "220;100;0" },
		{ 90, "󰀦", "220;40;20" },
		{ 100, "󰀦", "220;40;20" },
	}
	for _, c in ipairs(cases) do
		local s = Render.segments.context(ctx_used(c[1]))
		has(s, ("\27[38;2;%sm\27[1m%s %d%%"):format(c[3], c[2], c[1]))
	end
end)

test("20-block gradient bar", function()
	local function blocks(p)
		local s = Render.segments.context(ctx_used(p))
		local n = select(2, s:gsub("█", ""))
		local gray = s:match("\27%[38;2;60;60;60m([^\27]*)") or ""
		return n, #gray / #"█"
	end
	assert(select(1, blocks(0)) == 20 and select(2, blocks(0)) == 20)
	local n, gray = blocks(55)
	assert(n == 20 and gray == 9, ("55%%: %d blocks, %d gray"):format(n, gray))
	n, gray = blocks(150)
	assert(n == 20 and gray == 0)
	local full = Render.segments.context(ctx_used(100))
	has(full, "\27[38;2;0;200;80m█") -- block 0 green
	has(full, "\27[38;2;220;200;0m█") -- block 10 yellow
	has(full, "\27[38;2;220;56;18m█") -- block 19 red
	has(Render.segments.context(ctx_used(42.5)), " 42%") -- %.0f rounds half to even, like bash printf
end)

test("token k formatting", function()
	assert(Render.tokens(0) == "0")
	assert(Render.tokens(999) == "999")
	assert(Render.tokens(1000) == "1.0k")
	assert(Render.tokens(53333) == "53.3k")
	has(Render.render({ context_window = { total_input_tokens = 45210, total_output_tokens = 8123 } }), " 53.3k tok")
end)

test("model name parsing", function()
	assert(Render.model_name("claude-sonnet-5-5") == "Sonnet 5.5")
	assert(Render.model_name("claude-haiku-4-5-20251001") == "Haiku 4.5")
	assert(Render.model_name("claude-opus-4-1-20250805") == "Opus 4.1")
	assert(Render.model_name(nil) == nil)
	local s = Render.segments.agents({ agents = { { type = "Explore", model = "claude-sonnet-5-5" }, {} } })
	has(s, "󰚩 Explore·Sonnet 5.5, agent·…")
end)

test("segments disable and reorder", function()
	local ctx = decode(table.concat(vim.fn.readfile(root .. "/fixtures/subagents.json"), "\n"))
	local full = Render.render(ctx)
	for _, icon in ipairs({ "󰙴", "󰚩", " main", "+12" }) do
		has(full, icon)
	end
	local s = Render.render(ctx, { segments = { "repo", "context" } })
	hasnt(s, "󰙴")
	hasnt(s, "󰚩")
	hasnt(s, " main")
	s = Render.render(ctx, { segments = { "model", "repo" } })
	assert(s:sub(1, #"\27[38;2;200;80;220m") == "\27[38;2;200;80;220m", "model should lead")
	assert(Render.render(ctx, { segments = {} }) == "")
end)

test("truncate keeps escapes and cuts cells", function()
	local s = Playground.truncate("\27[1mabcdef\27[0m", 3)
	assert(s == "\27[1mabc\27[0m", vim.inspect(s))
	assert(Playground.truncate("██████", 2) == "██\27[0m")
end)

-- Temp sandbox: clean git repo + transcript with running / finished / stale subagents.
local tmp = vim.fn.tempname()
local repo = tmp .. "/sandbox-repo"
local transcript = tmp .. "/session.jsonl"
local function write(path, s)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local f = assert(io.open(path, "w"))
	f:write(s)
	f:close()
end
vim.fn.mkdir(repo, "p")
for _, cmd in ipairs({
	{ "git", "init", "-q", "-b", "main" },
	{ "git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init" },
}) do
	assert(vim.system(cmd, { cwd = repo }):wait().code == 0)
end
local sub = tmp .. "/session/subagents"
write(
	sub .. "/agent-run.jsonl",
	'{"type":"user"}\n{"message":{"model":"claude-haiku-4-5-1"}}\n{"type":"assistant","message":{"model":"claude-sonnet-5-5","stop_reason":"tool_use"}}\n'
)
write(sub .. "/agent-run.meta.json", '{"agentType":"Explore"}')
write(
	sub .. "/agent-done.jsonl",
	'{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":"end_turn"}}\n'
)
write(sub .. "/agent-done.meta.json", '{"agentType":"Plan"}')
write(
	sub .. "/agent-handback.jsonl",
	'{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":null,"content":[{"type":"tool_use","name":"SubagentHandback"}]}}\n'
		.. '{"type":"user","message":{"content":[{"type":"tool_result"}]}}\n'
		.. '{"type":"attachment","attachment":{"type":"hook_blocking_error"}}\n'
)
write(
	sub .. "/agent-bash.jsonl",
	'{"type":"assistant","message":{"model":"claude-opus-5-5","stop_reason":null,"content":[{"type":"tool_use","name":"Bash"}]}}\n'
		.. '{"type":"attachment","attachment":{"type":"x"}}\n'
)
write(sub .. "/agent-bash.meta.json", '{"agentType":"Build"}')
write(sub .. "/agent-old.jsonl", '{"type":"user","message":{"model":"claude-opus-5-5"}}\n')
vim.uv.fs_utime(sub .. "/agent-old.jsonl", os.time() - 3 * 3600, os.time() - 3 * 3600)

test("collect: git + running subagents", function()
	local ctx = Collect.run({ workspace = { current_dir = repo }, transcript_path = transcript })
	assert(ctx.git.branch == "main" and ctx.git.added == 0, vim.inspect(ctx.git))
	assert(#ctx.agents == 2, vim.inspect(ctx.agents))
	local types = { ctx.agents[1].type, ctx.agents[2].type }
	table.sort(types)
	assert(types[1] == "Build" and types[2] == "Explore", vim.inspect(ctx.agents))
	write(repo .. "/f.txt", "a\nb\n")
	vim.system({ "git", "add", "f.txt" }, { cwd = repo }):wait()
	local g = Collect.git(repo)
	assert(g.added == 2 and g.deleted == 0, vim.inspect(g))
	vim.system({ "git", "rm", "-q", "--cached", "f.txt" }, { cwd = repo }):wait()
	os.remove(repo .. "/f.txt")
end)

test("collect: missing everything -> empty", function()
	local ctx = Collect.run({ workspace = { current_dir = tmp .. "/nope" }, transcript_path = tmp .. "/nope.jsonl" })
	assert(ctx.git == nil and #ctx.agents == 0)
	assert(#Collect.run({ transcript_path = 42 }).agents == 0)
end)

--- Run bin/statusline.lua in-process (so coverage sees it) with `input` as stdin.
local function run_cli(input)
	local inp, out = tmp .. "/cli.in", tmp .. "/cli.out"
	write(inp, input or "")
	io.input(inp)
	io.output(out)
	local ok, err = pcall(dofile, root .. "/bin/statusline.lua")
	io.input():close()
	io.output():close()
	io.input(io.stdin)
	io.output(io.stdout)
	assert(ok, err)
	return table.concat(vim.fn.readfile(out, "b"), "\n")
end

test("cli: fixture in, line out", function()
	local out = run_cli(table.concat(vim.fn.readfile(root .. "/fixtures/mid.json"), "\n"))
	has(out, "󰊚 42%")
	assert(out:sub(-1) == "\n")
end)

test("cli: broken JSON still prints a default line and exits 0", function()
	local broken = table.concat(vim.fn.readfile(root .. "/fixtures/invalid/broken.json"), "\n")
	for _, out in ipairs({ run_cli(broken), run_cli(nil) }) do
		has(out, "󰙴 Claude")
		has(out, " 0 tok")
	end
	local res = vim.system({ "nvim", "-l", root .. "/bin/statusline.lua" }, { stdin = broken }):wait()
	assert(res.code == 0, res.stderr)
	has(res.stdout, "󰾆 0%")
end)

test("collect: agent without meta.json is typed 'agent'", function()
	local t = tmp .. "/nometa.jsonl"
	write(tmp .. "/nometa/subagents/agent-x.jsonl", '{"type":"assistant","message":{"stop_reason":null}}')
	local agents = Collect.agents(t)
	assert(#agents == 1 and agents[1].type == "agent" and agents[1].model == nil, vim.inspect(agents))
end)

test("playground: command, every keymap, errors, close", function()
	local notes, notify = {}, vim.notify
	vim.notify = function(msg)
		notes[#notes + 1] = msg
	end
	local api, Init = vim.api, require("claude_statusline")
	local function keys(k)
		api.nvim_feedkeys(vim.keycode(k), "x", false)
	end
	local ok, err = pcall(function()
		Init.setup({})
		vim.cmd("ClaudeStatusline bogus")
		has(notes[#notes], "unknown subcommand bogus")
		assert(vim.tbl_contains(vim.fn.getcompletion("ClaudeStatusline ", "cmdline"), "playground"))

		vim.cmd("ClaudeStatusline")
		local tab, json_win, json_buf =
			api.nvim_get_current_tabpage(), api.nvim_get_current_win(), api.nvim_get_current_buf()
		local term_win = vim.fn.win_getid(2)
		local term_buf = api.nvim_win_get_buf(term_win)
		assert(vim.bo[json_buf].filetype == "json" and vim.bo[term_buf].buftype == "terminal")
		local function preview()
			vim.wait(20)
			return table.concat(api.nvim_buf_get_lines(term_buf, 0, -1, false), "")
		end
		local function json()
			return table.concat(api.nvim_buf_get_lines(json_buf, 0, -1, false), "\n")
		end
		local function set_json(s)
			api.nvim_buf_set_lines(json_buf, 0, -1, false, vim.split(s, "\n"))
			api.nvim_exec_autocmds("TextChanged", { buffer = json_buf })
		end
		has(preview(), "42%")
		has(vim.wo[json_win].winbar, "preset: mid")

		-- reopening jumps back to the existing tab
		vim.cmd("tabprevious")
		vim.cmd("ClaudeStatusline playground")
		assert(api.nvim_get_current_tabpage() == tab)

		keys("+")
		has(json(), '"used_percentage": 47.5')
		keys("--")
		has(json(), '"used_percentage": 37.5')
		has(preview(), "38%") -- %.0f rounds half to even
		set_json('{ "context_window": { "used_percentage": 98 } }')
		keys("+")
		has(json(), '"used_percentage": 100')
		set_json("{}")
		keys("+")
		has(notes[#notes], "No numeric")

		-- presets: mid -> [p x3 wraps to long-names -> ]p wraps to empty
		keys("]p")
		has(vim.wo[json_win].winbar, "preset: high")
		keys("[p[p[p[p")
		has(vim.wo[json_win].winbar, "preset: long-names")
		keys("]p")
		has(vim.wo[json_win].winbar, "preset: empty")

		-- segment toggles
		keys("]p]p]p]p]p") -- subagents
		for i, name in ipairs(Render.order) do
			keys("g" .. i)
			has(vim.wo[term_win].winbar, i .. ":" .. name .. "✗")
		end
		assert(vim.trim(preview()) == "", preview())
		keys("g1g2g3g4g5g6g7")
		has(preview(), "󰚩 Explore·Haiku 4.5")
		keys("g6")
		hasnt(preview(), "󰙴")
		keys("g6")

		keys("gw")
		has(preview(), " 40│")
		keys("gw")
		hasnt(preview(), " 40│")

		-- live collect replaces the mock git/agents
		set_json(vim.json.encode({ workspace = { current_dir = repo }, transcript_path = transcript }))
		hasnt(preview(), "Explore")
		keys("gl")
		has(vim.wo[term_win].winbar, "live: on")
		has(preview(), " main")
		has(preview(), "Explore·Sonnet 5.5")
		keys("gl")

		keys("gy")
		assert(vim.fn.getreg('"'):sub(1, 4) == "\27[1m", vim.fn.getreg('"'))
		keys("gY")
		assert(vim.fn.getreg('"') == json())

		set_json("42")
		has(preview(), "top level must be an object")
		keys("gy")
		has(notes[#notes], "Nothing to yank")
		set_json("{ broken")
		has(preview(), "JSON error:")
		local repo_seg = Render.segments.repo
		Render.segments.repo = function()
			error("boom")
		end
		set_json("{}")
		Render.segments.repo = repo_seg
		has(preview(), "render error:")

		-- q from the preview closes the tab; rendering afterwards is a no-op
		api.nvim_set_current_win(term_win)
		keys("q")
		assert(not api.nvim_tabpage_is_valid(tab) and not api.nvim_buf_is_valid(json_buf))
		Playground.render()

		-- q on the last tab falls back to an empty window
		vim.cmd("ClaudeStatusline playground")
		json_buf = api.nvim_get_current_buf()
		vim.cmd("tabonly")
		keys("q")
		assert(not api.nvim_buf_is_valid(json_buf) and #api.nvim_list_wins() == 1)
	end)
	vim.notify = notify
	assert(ok, err)
end)

local bash = vim.env.CLAUDE_STATUSLINE_BASH or root .. "/tests/statusline-command.sh"
if vim.fn.filereadable(bash) == 1 and vim.fn.executable("jq") == 1 then
	test("parity with bash script (sandbox repo + subagents)", function()
		for _, f in ipairs(fixtures) do
			local ctx = decode(table.concat(vim.fn.readfile(f), "\n"))
			ctx.git, ctx.agents = nil, nil -- bash collects for real; so does bin/statusline.lua
			ctx.workspace.current_dir, ctx.transcript_path = repo, transcript
			local input = vim.json.encode(ctx)
			local want = vim.system({ "bash", bash }, { stdin = input }):wait().stdout
			local got = vim.system({ "nvim", "-l", root .. "/bin/statusline.lua" }, { stdin = input }):wait().stdout
			assert(got == want, ("%s\n     bash: %q\n     lua:  %q"):format(vim.fs.basename(f), want, got))
		end
	end)
else
	io.write("skip parity (no bash script at ", bash, " or no jq)\n")
end

vim.fn.delete(tmp, "rf")
io.write(("\n%d/%d passed\n"):format(total - failures, total))
os.exit(failures == 0 and 0 or 1)
