describe("agent process status", function()
	local status, jobwait, buf
	before_each(function()
		package.loaded["tw.agent.status"] = nil
		status = require("tw.agent.status")
		jobwait = vim.fn.jobwait
		buf = vim.api.nvim_create_buf(false, true)
	end)
	after_each(function()
		vim.fn.jobwait = jobwait
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end)
	it("reports running for every mode regardless of terminal output", function()
		vim.fn.jobwait = function()
			return { -1 }
		end
		for _, mode in ipairs({ "claude", "codex", "opencode", "pi" }) do
			assert.equals("running", status.detect({ mode = mode, buf = buf, job_id = 1 }))
		end
	end)
	it("immediately reflects exit without a stale status cache", function()
		local result = -1
		vim.fn.jobwait = function()
			return { result }
		end
		local inst = { buf = buf, job_id = 1 }
		assert.equals("running", status.detect(inst))
		result = 0
		assert.equals("dead", status.detect(inst))
	end)
	it("handles missing buffers, jobs, and failed process queries", function()
		assert.equals("dead", status.detect(nil))
		assert.equals("dead", status.detect({ buf = buf }))
		vim.fn.jobwait = function()
			error("invalid job")
		end
		assert.equals("dead", status.detect({ buf = buf, job_id = 1 }))
		vim.api.nvim_buf_delete(buf, { force = true })
		assert.equals("dead", status.detect({ buf = buf, job_id = 1 }))
	end)
end)
