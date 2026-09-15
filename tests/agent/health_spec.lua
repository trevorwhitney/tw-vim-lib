require("tests.agent.spec_helpers")

-- Tests for tw.agent.health.check(). It composes a :checkhealth report by
-- calling vim.health.{start,ok,warn,error} based on the agent's
-- default mode. We inject a recording vim.health and a stub agent module,
-- and stub vim.env, then assert the report entries per scenario.

describe("agent.health.check", function()
	local report
	local saved

	-- Build a fresh health module wired to our stubs. `cfg` controls the
	-- scenario knobs (env table, default_mode).
	local function load_health(cfg)
		cfg = cfg or {}
		report = { ok = {}, warn = {}, error = {}, info = {}, start = {} }

		package.loaded["vim.health"] = {
			start = function(m)
				table.insert(report.start, m)
			end,
			ok = function(m)
				table.insert(report.ok, m)
			end,
			warn = function(m, _adv)
				table.insert(report.warn, m)
			end,
			error = function(m, _adv)
				table.insert(report.error, m)
			end,
			info = function(m)
				table.insert(report.info, m)
			end,
		}

		package.loaded["tw.agent"] = {
			default_mode = cfg.default_mode or "claude",
		}

		package.loaded["tw.agent.health"] = nil
		return require("tw.agent.health")
	end

	before_each(function()
		saved = { env = vim.env }
	end)

	after_each(function()
		vim.env = saved.env
		package.loaded["vim.health"] = nil
		package.loaded["tw.agent"] = nil
		package.loaded["tw.agent.health"] = nil
	end)

	local function has(list, needle)
		for _, m in ipairs(list) do
			if m:find(needle, 1, true) then
				return true
			end
		end
		return false
	end

	it("does not require an API key for terminal integration", function()
		local health = load_health({})
		vim.env = {}
		health.check()
		assert.equals(0, #report.error)
		assert.equals(0, #report.warn)
		assert.is_true(has(report.start, "AI Agent Mode Settings"))
	end)

	it("reports the configured default mode", function()
		local health = load_health({ default_mode = "opencode" })
		vim.env = {}
		health.check()
		assert.is_true(has(report.ok, "Default mode: opencode"))
	end)
end)
