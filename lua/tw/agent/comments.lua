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

return M
