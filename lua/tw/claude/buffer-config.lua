local M = {}

local log = require("tw.log")

-- Configuration defaults
M.config = {
	scrollback = 5000, -- Default scrollback limit
	follow_output = true, -- Auto-scroll to bottom on new output
	prevent_resize_scroll = true, -- Prevent scrolling when resizing
}

-- Buffer-local state management
M.buffer_states = {} -- Store all buffer-specific state
M.cursor_positions = {} -- Track cursor positions for each buffer
M.buffer_autocmds = {} -- Track buffer-local autocommand IDs

-- Setup buffer-specific configuration for Claude terminal buffers
function M.setup_buffer(buf, opts)
	opts = opts or {}
	local config = vim.tbl_extend("force", M.config, opts)

	-- Initialize buffer state
	M.buffer_states[buf] = {
		config = config,
		session_id = vim.fn.sha256(tostring(buf) .. tostring(os.time())),
		created_at = os.time(),
		conversation_history = {},
		active = true,
	}

	-- Initialize tracking tables for this buffer
	M.buffer_autocmds[buf] = {}

	-- Set buffer options
	vim.api.nvim_buf_set_option(buf, "scrollback", config.scrollback)
	vim.api.nvim_buf_set_option(buf, "filetype", "ClaudeConsole")

	-- Create buffer-local autocmds for this specific buffer
	local augroup = vim.api.nvim_create_augroup("ClaudeBuffer_" .. buf, { clear = true })

	-- Setup automatic cleanup when buffer is deleted
	local cleanup_autocmd = vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
		group = augroup,
		buffer = buf,
		once = true, -- Ensure it only runs once
		callback = function()
			M.cleanup(buf)
		end,
		desc = "Cleanup Claude buffer resources on deletion",
	})
	table.insert(M.buffer_autocmds[buf], cleanup_autocmd)

	-- Prevent scrolloff from affecting terminal buffers
	local scrolloff_autocmd = vim.api.nvim_create_autocmd({ "BufEnter", "TermEnter" }, {
		group = augroup,
		buffer = buf,
		callback = function()
			vim.wo.scrolloff = 0
		end,
		desc = "Disable scrolloff in Claude terminal buffer",
	})
	table.insert(M.buffer_autocmds[buf], scrolloff_autocmd)

	-- Save cursor position before resize events
	if config.prevent_resize_scroll then
		local resize_autocmd = vim.api.nvim_create_autocmd({ "WinScrolled", "VimResized" }, {
			group = augroup,
			buffer = buf,
			callback = function()
				local win = vim.fn.bufwinid(buf)
				if win == -1 then
					return
				end

				-- Check if this is actually a resize event
				if vim.v.event and vim.v.event[tostring(win)] then
					local event_data = vim.v.event[tostring(win)]
					if event_data.width or event_data.height then
						-- This is a resize event
						M.handle_resize(buf, win)
					end
				end
			end,
			desc = "Handle Claude terminal buffer resize",
		})
		table.insert(M.buffer_autocmds[buf], resize_autocmd)
	end

	-- Auto-scroll to bottom on new output if follow mode is enabled
	if config.follow_output then
		local follow_autocmd = vim.api.nvim_create_autocmd({ "TermEnter" }, {
			group = augroup,
			buffer = buf,
			callback = function()
				local win = vim.fn.bufwinid(buf)
				if win ~= -1 then
					-- Jump to the end of the buffer
					vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
				end
			end,
			desc = "Auto-scroll Claude terminal to bottom on enter",
		})
		table.insert(M.buffer_autocmds[buf], follow_autocmd)
	end

	log.debug("Claude buffer " .. buf .. " configured with scrollback=" .. config.scrollback)
end

-- Handle buffer resize to prevent unwanted scrolling
function M.handle_resize(buf, win)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
		return
	end

	-- Get current mode
	local mode = vim.api.nvim_get_mode().mode

	-- Only preserve position if in normal mode
	if mode == "n" or mode == "nt" then
		local cursor_pos = M.cursor_positions[buf]
		if cursor_pos and cursor_pos[1] <= vim.api.nvim_buf_line_count(buf) then
			-- Restore the saved cursor position
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(buf) then
					pcall(vim.api.nvim_win_set_cursor, win, cursor_pos)
				end
			end)
		end
	end
end

-- Save cursor position for a buffer
function M.save_cursor_position(buf)
	local win = vim.fn.bufwinid(buf)
	if win ~= -1 then
		M.cursor_positions[buf] = vim.api.nvim_win_get_cursor(win)
	end
end

-- Clear scrollback for a buffer
function M.clear_scrollback(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		log.warn("Invalid buffer for clearing scrollback")
		return
	end

	local original_scrollback = vim.api.nvim_buf_get_option(buf, "scrollback")

	-- Temporarily set scrollback to 1 to clear
	vim.api.nvim_buf_set_option(buf, "scrollback", 1)

	-- Wait a bit for the change to take effect
	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(buf) then
			-- Restore original scrollback setting
			vim.api.nvim_buf_set_option(buf, "scrollback", original_scrollback)
			log.info("Cleared scrollback for Claude buffer")
		end
	end, 100)
end

-- Toggle follow mode for a buffer
function M.toggle_follow_mode(buf)
	if not M.config.follow_output then
		M.config.follow_output = true
		log.info("Claude follow mode enabled")
	else
		M.config.follow_output = false
		log.info("Claude follow mode disabled")
	end
end

-- Update configuration
function M.setup(opts)
	M.config = vim.tbl_extend("force", M.config, opts or {})
end

-- Clean up when buffer is deleted
function M.cleanup(buf)
	log.debug("Starting cleanup for Claude buffer " .. buf)

	-- Mark buffer as inactive in state
	if M.buffer_states[buf] then
		M.buffer_states[buf].active = false
	end

	-- Clean up all buffer-local autocmds
	if M.buffer_autocmds[buf] then
		for _, autocmd_id in ipairs(M.buffer_autocmds[buf]) do
			pcall(vim.api.nvim_del_autocmd, autocmd_id)
		end
		M.buffer_autocmds[buf] = nil
	end

	-- Clear the autogroup for this buffer
	pcall(vim.api.nvim_del_augroup_by_name, "ClaudeBuffer_" .. buf)

	-- Clean up cursor positions
	M.cursor_positions[buf] = nil

	-- Clean up buffer state (keep history for a short time in case of quick re-open)
	vim.defer_fn(function()
		if M.buffer_states[buf] and not M.buffer_states[buf].active then
			M.buffer_states[buf] = nil
			log.debug("Fully cleaned up state for Claude buffer " .. buf)
		end
	end, 5000) -- Keep state for 5 seconds

	log.info("Cleaned up resources for Claude buffer " .. buf)
end

-- Get buffer state
function M.get_buffer_state(buf)
	return M.buffer_states[buf]
end

-- Update conversation history for a buffer
function M.add_to_history(buf, entry)
	if M.buffer_states[buf] then
		table.insert(M.buffer_states[buf].conversation_history, {
			timestamp = os.time(),
			entry = entry,
		})
	end
end

-- Check if buffer has been setup
function M.is_managed(buf)
	return M.buffer_states[buf] ~= nil
end

return M
