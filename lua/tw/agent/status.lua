local M = {}

-- Process liveness only: terminal output is not a reliable turn-status API.
function M.detect(instance)
	if not instance or not instance.buf or not vim.api.nvim_buf_is_valid(instance.buf) or not instance.job_id then
		return "dead"
	end
	local ok, result = pcall(vim.fn.jobwait, { instance.job_id }, 0)
	if ok and result and result[1] == -1 then
		return "running"
	end
	return "dead"
end

return M
