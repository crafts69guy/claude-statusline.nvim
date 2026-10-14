-- IO side: fills ctx.git and ctx.agents from the real repo and subagent transcripts.
-- Never errors: anything missing or unreadable yields nil / {}.
local M = {}

local function read(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local s = f:read("*a")
	f:close()
	return s
end

local function decode(s)
	local ok, v = pcall(vim.json.decode, s or "", { luanil = { object = true, array = true } })
	return ok and type(v) == "table" and v or nil
end

---@param dir string
---@param diff? boolean collect diff counts; defaults to true
---@return { branch: string, added: integer, deleted: integer }|nil
function M.git(dir, diff)
	-- Collect branch and requested diff in parallel; avoid fighting the user's git.
	local branch = vim.system({ "git", "--no-optional-locks", "-C", dir, "rev-parse", "--abbrev-ref", "HEAD" })
	local stat = diff ~= false and vim.system({ "git", "--no-optional-locks", "-C", dir, "diff", "--shortstat", "HEAD" })
	local b = branch:wait(2000)
	local s = stat and stat:wait(2000)
	if b.code ~= 0 then
		return nil
	end
	local name = vim.trim(b.stdout or "")
	if name == "HEAD" then
		local sha = vim.system({ "git", "--no-optional-locks", "-C", dir, "rev-parse", "--short", "HEAD" }):wait(2000)
		name = sha.code == 0 and vim.trim(sha.stdout or "") or name
	end
	local out = s and s.code == 0 and s.stdout or ""
	return {
		branch = name,
		added = tonumber(out:match("(%d+) insertion")) or 0,
		deleted = tonumber(out:match("(%d+) deletion")) or 0,
	}
end

--- Running subagents of the session, from `<transcript>/subagents/agent-*.jsonl`.
--- An agent is finished when its last assistant turn has stop_reason end_turn or calls the SubagentHandback tool.
---@param transcript string?
---@return { type: string, model: string? }[]
function M.agents(transcript)
	local res = {}
	if type(transcript) ~= "string" or transcript == "" then
		return res
	end
	local sub_dir = transcript:gsub("%.jsonl$", "") .. "/subagents"
	local cutoff = os.time() - 120 * 60
	for name, kind in vim.fs.dir(sub_dir) do
		local path = sub_dir .. "/" .. name
		local st = kind == "file" and name:match("^agent%-.*%.jsonl$") and vim.uv.fs_stat(path)
		local body = st and st.mtime.sec > cutoff and read(path)
		if body then
			-- Finished = the last assistant turn is end_turn or a SubagentHandback tool_use; other line types are skipped.
			-- ponytail: a killed agent never finishes, so it shows until its file is 2h old.
			local done = false
			local lines = vim.split(body, "\n", { plain = true })
			for i = #lines, 1, -1 do
				local obj = lines[i] ~= "" and decode(lines[i])
				local msg = obj and obj.type == "assistant" and type(obj.message) == "table" and obj.message
				if msg then
					done = msg.stop_reason == "end_turn"
					for _, c in ipairs(type(msg.content) == "table" and msg.content or {}) do
						done = done or (type(c) == "table" and c.type == "tool_use" and c.name == "SubagentHandback")
					end
					break
				end
			end
			if not done then
				local model
				for m in body:gmatch('"model":"(claude%-[^"]*)"') do
					model = m
				end
				local meta = decode(read(path:gsub("%.jsonl$", ".meta.json")))
				res[#res + 1] =
					{ type = meta and type(meta.agentType) == "string" and meta.agentType or "agent", model = model }
			end
		end
	end
	return res
end

--- Overwrite ctx.git / ctx.agents with real data.
---@param ctx table
---@param opts? claude_statusline.Config collect only selected segments
---@return table ctx
function M.run(ctx, opts)
	local selected = opts and opts.segments or require("claude_statusline.render").order
	local git_needed = vim.tbl_contains(selected, "branch") or vim.tbl_contains(selected, "diff")
	local ws = type(ctx.workspace) == "table" and ctx.workspace or {}
	local dir = type(ws.current_dir) == "string" and ws.current_dir ~= "" and ws.current_dir or vim.uv.cwd()
	local ok, git = true, nil
	if git_needed then
		ok, git = pcall(M.git, dir, vim.tbl_contains(selected, "diff"))
	end
	ctx.git = ok and git or nil
	local ok2, agents = true, {}
	if vim.tbl_contains(selected, "agents") then
		ok2, agents = pcall(M.agents, ctx.transcript_path)
	end
	ctx.agents = ok2 and agents or {}
	return ctx
end

return M
