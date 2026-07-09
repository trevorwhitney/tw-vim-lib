local M = {}

local registry = require("tw.agent.registry")

local function now()
	return os.time()
end

function M._workmux_status(status)
	if status == "working" then
		return "working"
	elseif status == "waiting" then
		return "waiting"
	end
	return nil
end

function M.record(entry)
	local description = entry.description
	if description == "loading" or description == "error" or description == "" then
		description = nil
	end
	pcall(registry.upsert, entry.root, entry.mode, entry.idx, {
		cwd = entry.cwd,
		last_status = entry.status or "working",
		description = description,
		session_id = entry.session_id,
		updated_ts = now(),
	})
end

function M.record_exit(entry)
	pcall(registry.upsert, entry.root, entry.mode, entry.idx, {
		cwd = entry.cwd,
		last_status = "restorable",
		updated_ts = now(),
	})
end

local last_pushed = {}

local function default_workmux_runner(status)
	if vim.fn.executable("workmux") ~= 1 then
		return
	end
	vim.system({ "workmux", "set-window-status", status }, { text = true })
end

local workmux_runner = default_workmux_runner

function M._set_workmux_runner(fn)
	workmux_runner = fn
end

function M._reset_pushed()
	last_pushed = {}
end

function M.push_status(mode, idx, status)
	local key = string.format("%s#%d", mode, idx)
	local name = M._workmux_status(status)
	if not name then
		return
	end
	if last_pushed[key] == name then
		return
	end
	last_pushed[key] = name
	pcall(workmux_runner, name)
end

local poll_timer = nil

local function default_timer_factory()
	return vim.uv.new_timer()
end

local timer_factory = default_timer_factory

function M._set_timer_factory(fn)
	timer_factory = fn
end

local capture_hook = nil

function M._set_capture_hook(fn)
	capture_hook = fn
end

function M.start_timer(tick, interval_ms)
	if poll_timer then
		return
	end
	interval_ms = interval_ms or 1000
	poll_timer = timer_factory()
	if not poll_timer then
		return
	end
	poll_timer:start(
		interval_ms,
		interval_ms,
		vim.schedule_wrap(function()
			pcall(function()
				local status = require("tw.agent.status")
				for _, inst in ipairs(tick() or {}) do
					local s = status.detect(inst)
					M.push_status(inst.mode, inst.idx, s)
					if capture_hook then
						pcall(capture_hook, inst.mode, inst.idx)
					end
				end
			end)
		end)
	)
end

function M.stop_timer()
	if poll_timer then
		pcall(function()
			poll_timer:stop()
		end)
		pcall(function()
			poll_timer:close()
		end)
		poll_timer = nil
	end
end

return M
