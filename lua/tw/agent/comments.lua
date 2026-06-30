local M = {}

local NS_NAME = "tw_agent_comments"
local ns = vim.api.nvim_create_namespace(NS_NAME)

-- Entry shape: { bufnr, extmark_id, file, body, start_line, end_line }.
-- start_line/end_line (1-based) are only a fallback for when the live extmark
-- range can no longer be read, e.g. after the buffer was closed.
M._batch = {}

M._marked_bufs = {}

-- Seam: production wraps vim.api; the standalone suite swaps in a Lua fake.
M._extmark_ops = {
	set = function(buf, start_row, end_row, opts)
		opts.end_row = end_row
		return vim.api.nvim_buf_set_extmark(buf, ns, start_row, 0, opts)
	end,
	get = function(buf, id)
		local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, { details = true })
		if not pos or not pos[1] then
			return nil
		end
		local start_line = pos[1] + 1
		local details = pos[3] or {}
		local end_line = details.end_row and (details.end_row + 1) or start_line
		return { start_line = start_line, end_line = end_line }
	end,
	del = function(buf, id)
		pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
	end,
	clear = function(buf)
		pcall(vim.api.nvim_buf_clear_namespace, buf, ns, 0, -1)
	end,
	buf_valid = function(buf)
		return vim.api.nvim_buf_is_valid(buf)
	end,
}

function M.clear()
	for buf in pairs(M._marked_bufs) do
		if M._extmark_ops.buf_valid(buf) then
			M._extmark_ops.clear(buf)
		end
	end
	M._batch = {}
	M._marked_bufs = {}
end

-- True only when the buffer's line numbers reliably match the on-disk file.
-- diffview opens the working-tree side as a normal file buffer (plain path);
-- every other side (base commit, any stage incl. :0: the index, custom, null)
-- is a synthetic diffview:// buffer whose lines may diverge from disk.
function M._is_commentable_buffer(bufname, bufnr)
	if not bufname or bufname == "" then
		return false
	end
	if bufname:match("^diffview://") then
		return false
	end
	if bufnr and vim.bo[bufnr].buftype ~= "" then
		return false
	end
	return vim.fn.filereadable(bufname) == 1
end

function M._render_range(file, start_line, end_line)
	if start_line == end_line then
		return file .. ":" .. start_line
	end
	return file .. ":" .. start_line .. "-" .. end_line
end

function M._format_block(entry)
	return "@" .. M._render_range(entry.file, entry.start_line, entry.end_line) .. "\n" .. entry.body
end

function M._build_blob(entries)
	local blocks = {}
	for _, entry in ipairs(entries) do
		blocks[#blocks + 1] = M._format_block(entry)
	end
	return "Review comments:\n\n" .. table.concat(blocks, "\n\n")
end

function M._resolve_entry_range(entry)
	if entry.bufnr and M._extmark_ops.buf_valid(entry.bufnr) then
		local r = M._extmark_ops.get(entry.bufnr, entry.extmark_id)
		if r then
			return r.start_line, r.end_line
		end
	end
	require("tw.log").warn(
		string.format("comments: extmark unreadable for %s, using stored range", entry.file)
	)
	return entry.start_line, entry.end_line
end

-- Seam: the real path routes through _send_with_count, which also opens/focuses
-- the agent window and leaves the prompt unsubmitted for the user to send.
M._send = function(count, blob)
	require("tw.agent")._send_with_count("SendText", count, blob, false)
end

function M.flush(count)
	if #M._batch == 0 then
		vim.notify("No pending agent comments", vim.log.levels.INFO)
		return
	end
	local entries = {}
	for _, entry in ipairs(M._batch) do
		local start_line, end_line = M._resolve_entry_range(entry)
		entries[#entries + 1] = {
			file = entry.file,
			start_line = start_line,
			end_line = end_line,
			body = entry.body,
		}
	end
	M._send(count, M._build_blob(entries))
	M.clear()
end

local SIGN_TEXT = "▌"
local SIGN_HL = "Comment"
local VIRT_HL = "Comment"

local function preview_text(body)
	local first = body:gsub("\n.*$", "")
	if #first > 40 then
		first = first:sub(1, 39) .. "…"
	end
	return SIGN_TEXT .. " " .. first
end

function M._commit_comment(bufnr, file, start_line, end_line, body)
	local opts = {
		sign_text = SIGN_TEXT,
		sign_hl_group = SIGN_HL,
		virt_text = { { preview_text(body), VIRT_HL } },
		virt_text_pos = "right_align",
	}
	local id = M._extmark_ops.set(bufnr, start_line - 1, end_line - 1, opts)
	M._batch[#M._batch + 1] = {
		bufnr = bufnr,
		extmark_id = id,
		file = file,
		body = body,
		start_line = start_line,
		end_line = end_line,
	}
	M._marked_bufs[bufnr] = true
	return id
end

local function open_capture_window(title, on_confirm)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	local width = 60
	local height = 8
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		border = "rounded",
		title = title,
	})

	local function close()
		if vim.api.nvim_win_is_valid(win) then
			vim.api.nvim_win_close(win, true)
		end
	end

	local function confirm()
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local body = vim.trim(table.concat(lines, "\n"))
		close()
		if body == "" then
			vim.notify("Empty comment discarded", vim.log.levels.INFO)
			return
		end
		on_confirm(body)
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", confirm, { buffer = buf })
	vim.keymap.set("n", "q", close, { buffer = buf })
	vim.keymap.set("n", "<Esc>", close, { buffer = buf })
	vim.cmd("startinsert")
end

function M.add()
	local mode = vim.fn.mode()
	local is_visual = mode == "v" or mode == "V" or mode == "\22"
	local start_line, end_line
	if is_visual then
		vim.cmd("normal! \027")
		start_line = vim.fn.line("'<")
		end_line = vim.fn.line("'>")
	else
		start_line = vim.fn.line(".")
		end_line = start_line
	end

	local bufnr = vim.api.nvim_get_current_buf()
	local bufname = vim.api.nvim_buf_get_name(bufnr)
	if not M._is_commentable_buffer(bufname, bufnr) then
		vim.notify("Comment on the working-tree side of the diff (not the base/index)", vim.log.levels.WARN)
		return
	end

	local util = require("tw.agent.util")
	local Path = require("plenary.path")
	local resolved, repo_root = util.resolve_file_path(bufname)
	if not resolved then
		vim.notify("Cannot resolve file path in this buffer", vim.log.levels.WARN)
		return
	end
	local git_root = repo_root or util.get_git_root()
	local file = Path:new(resolved):make_relative(git_root)

	local title = " Comment @" .. M._render_range(file, start_line, end_line) .. " "
	open_capture_window(title, function(body)
		M._commit_comment(bufnr, file, start_line, end_line, body)
	end)
end

function M.list()
	local items = {}
	for _, entry in ipairs(M._batch) do
		local start_line = M._resolve_entry_range(entry)
		local text = entry.body:gsub("\n.*$", "")
		local item = { lnum = start_line, text = text }
		if entry.bufnr and M._extmark_ops.buf_valid(entry.bufnr) then
			item.bufnr = entry.bufnr
		else
			item.filename = entry.file
		end
		items[#items + 1] = item
	end
	vim.fn.setqflist({}, " ", { items = items, title = "Agent Comments" })
	vim.cmd("copen")
end

function M.remove_under_cursor()
	local bufnr = vim.api.nvim_get_current_buf()
	local cursor = vim.fn.line(".")
	for i, entry in ipairs(M._batch) do
		if entry.bufnr == bufnr then
			local start_line, end_line = M._resolve_entry_range(entry)
			if cursor >= start_line and cursor <= end_line then
				M._extmark_ops.del(bufnr, entry.extmark_id)
				table.remove(M._batch, i)
				vim.notify("Comment removed", vim.log.levels.INFO)
				return
			end
		end
	end
	vim.notify("No agent comment under cursor", vim.log.levels.INFO)
end

function M.setup(_)
	M.clear()
	local ok, wk = pcall(require, "which-key")
	if not ok then
		return
	end
	wk.add({
		mode = { "n", "v" },
		{ "<leader>cc", function() M.add() end, desc = "Add agent comment (line/selection)" },
	})
	wk.add({
		mode = { "n" },
		{ "<leader>cC", function()
			local count = vim.v.count
			M.flush(count)
		end, desc = "Flush agent comments (count = instance idx)" },
		{ "<leader>cq", function() M.list() end, desc = "List pending agent comments" },
		{ "<leader>cr", function() M.remove_under_cursor() end, desc = "Remove agent comment under cursor" },
		{ "<leader>cX", function() M.clear() end, desc = "Clear agent comment batch" },
	})
end

return M
