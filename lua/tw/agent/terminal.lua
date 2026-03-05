local M = {}

local function open_vsplit_window()
	vim.api.nvim_command("vert botright new")
end

local function open_hsplit_window()
	vim.api.nvim_command("new")
end

local function open_editor_relative_window()
	local buf = vim.api.nvim_create_buf(false, true)
	local width = vim.api.nvim_get_option("columns")
	local height = vim.api.nvim_get_option("lines")
	local win = vim.api.nvim_open_win(
		buf,
		true,
		{ relative = "editor", width = width - 10, height = height - 10, row = 2, col = 2 }
	)
	vim.api.nvim_set_current_win(win)
end

function M.open_window(window_type)
	if window_type == "vsplit" then
		open_vsplit_window()
	elseif window_type == "hsplit" then
		open_hsplit_window()
	else
		open_editor_relative_window()
	end
end

function M.open_buffer_in_new_window(window_type, claude_buf)
	if window_type == "vsplit" then
		vim.api.nvim_command("vert botright split | buffer " .. claude_buf)
	elseif window_type == "hsplit" then
		vim.api.nvim_command("split | buffer " .. claude_buf)
	else
		vim.api.nvim_command("buffer " .. claude_buf)
	end
end

-- Helper function to cleanly close a terminal buffer and its job
function M.close_terminal_buffer(buf, job_id)
	-- Stop the job if it's running
	if job_id and vim.fn.jobwait({ job_id }, 0)[1] == -1 then
		vim.fn.jobstop(job_id)
	end

	-- Close any windows showing the buffer
	if buf and vim.api.nvim_buf_is_valid(buf) then
		local windows = vim.api.nvim_list_wins()
		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_win_close(win, true)
			end
		end
		-- Delete the buffer
		vim.api.nvim_buf_delete(buf, { force = true })
	end

	return nil, nil -- Return nil for both buf and job_id to clear state
end

-- Helper function to open or reuse an existing terminal buffer
function M.open_or_reuse_terminal_buffer(buf, window_type)
	if buf and vim.api.nvim_buf_is_valid(buf) then
		-- Check if buffer is visible in any window
		local windows = vim.api.nvim_list_wins()
		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
				vim.api.nvim_set_current_win(win)
				vim.cmd("startinsert")
				return true, buf
			end
		end
		-- Buffer exists but not visible, show it
		M.open_buffer_in_new_window(window_type or "vsplit", buf)
		vim.cmd("startinsert")
		return true, buf
	end
	return false, nil
end

return M
