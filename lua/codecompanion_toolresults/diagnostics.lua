local M = {}

local function encode(value)
  local ok, encoded = pcall(vim.json.encode, value)
  if ok then
    return encoded
  end

  return vim.inspect(value)
end

local function write_file(directory, filename, content)
  local path = directory .. "/" .. filename
  local file, error_message = io.open(path, "w")
  if not file then
    return false, error_message or path
  end

  file:write(content, "\n")
  file:close()
  return true
end

local function write_json(directory, filename, value)
  return write_file(directory, filename, encode(value))
end

local function write_text(directory, filename, lines)
  return write_file(directory, filename, table.concat(lines, "\n"))
end

local function create_directory(path)
  local ok, result = pcall(vim.fn.mkdir, path, "p")
  if not ok or result == 0 then
    return false, ok and "could not create " .. path or tostring(result)
  end

  return true
end

---Capture buffer metadata and rendered lines for ondemand diagnostic dump.
---
---The metadata stays separate from the lines because they answer different debugging questions: metadata
---describes which buffer was inspected, while the lines show what the user actually saw. Reading happens
---only during a dump, so normal plugin operation does not retain a second copy of the chat buffer.
---
---Invalid buffers are expected when chat was closed between state tracking and dump creation. Return a diagnostic
---marker instead of calling buffer APIs on an invalid handle; this preserves evidence that the buffer disappeared.
---
---@param bufnr integer Chat buffer handle.
---@return table metadata Buffer validity, name, filetype, and line count.
---@return string[] lines Current rendered buffer lines, or an invalid-buffer marker.
local function buffer_snapshot(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return { valid = false, name = nil, filetype = nil, line_count = nil, },
           { "[buffer invalid]" }
  end

  return {
    valid = true,
    name = vim.api.nvim_buf_get_name(bufnr),
    filetype = vim.bo[bufnr].filetype,
    line_count = vim.api.nvim_buf_line_count(bufnr),
  }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Write current tracked runtime state for diagnosing issues without restarting Neovim.
---@param state_by_bufnr table<integer, table> Tracked chat state.
---@param opts? table Dump options.
---@return string? directory Created dump directory, or nil on failure.
---@return string? error Error message on failure.
function M.dump(state_by_bufnr, opts)
  opts = opts or {}

  local directory = opts.directory or vim.fn.tempname()
  local created, error_message = create_directory(directory)
  if not created then
    return nil, error_message
  end

  local chat_buffers = {}
  for bufnr, chat_state in pairs(state_by_bufnr) do
    local chat_directory = directory .. "/chat-" .. bufnr
    created, error_message = create_directory(chat_directory)
    if not created then
      return nil, error_message
    end

    local buffer_metadata, buffer_lines = buffer_snapshot(bufnr)
    local files = {
      { "messages.json", chat_state.messages },
      { "references.json", chat_state.references },
      { "tools.json", chat_state.tools },
      { "buffer-metadata.json", buffer_metadata },
    }

    for _, file in ipairs(files) do
      local written, write_error = write_json(chat_directory, file[1], file[2])
      if not written then
        return nil, "could not write " .. file[1] .. ": " .. write_error
      end
    end

    local written, write_error = write_text(chat_directory, "buffer.txt", buffer_lines)
    if not written then
      return nil, "could not write buffer.txt: " .. write_error
    end

    chat_buffers[#chat_buffers + 1] = bufnr
  end

  local written, write_error = write_json(directory, "metadata.json", {
    created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    chats = chat_buffers,
    chat_count = #chat_buffers,
  })

  if not written then
    return nil, "could not write metadata.json: " .. write_error
  end

  return directory
end

return M
