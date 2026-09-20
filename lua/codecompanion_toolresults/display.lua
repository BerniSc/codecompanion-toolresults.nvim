local M = {}

local navigation = require("codecompanion_toolresults.navigation")

---Format content as a fenced Markdown code block.
---
---Use at least four backticks and grow fence length when content contains
---longer backtick runs, so embedded Markdown remains literal.
---@param content any Content to format.
---@param language? string Optional fence language label.
---@return string Markdown code block.
local function format_codeblock(content, language)
  content = tostring(content)
  language = type(language) == "string" and language:match("^[^\r\n]*") or ""

  local longest_fence = 0
  for backticks in content:gmatch("`+") do
    longest_fence = math.max(longest_fence, #backticks)
  end

  local fence = string.rep("`", math.max(4, longest_fence + 1))
  -- ternary equivalent (a ? b : c).
  local suffix = content:sub(-1) == "\n" and "" or "\n"
  return string.format("%s%s\n%s%s%s", fence, language, content, suffix, fence)
end

---@param adapter table Message adapter used for run_command prefix removal.
---@param result table Current tool result.
---@param command string? Command extracted during message reconciliation.
---@param language string|false Language used for the command code fence.
---@return string
local function format_run_command_result(adapter, result, command, language)
  local content = result.content
  if type(content) ~= "string" then
    content = vim.inspect(content)
  end

  if type(command) ~= "string" or not language then
    return content
  end

  local output = adapter.remove_run_command_prefix(content, command)
  return string.format("%s\n%s", format_codeblock(command, language), output)
end

---Render one tool result into lines suitable for the managed result buffer.
---@param adapter table Message adapter used for run_command prefix removal.
---@param reference table Tool reference containing tool name and command metadata.
---@param result table Current tool result containing content.
---@param opts table Extension options, including run_command_language.
---@return string[] lines Rendered result split into buffer lines.
local function render_result(adapter, reference, result, opts)
  local content
  if reference.name == "run_command" then
    -- Keep command formatting isolated to run_command; read/write tools remain unchanged.
    -- Reserve handling them for example using CodeCompanions Diff later on.
    content = format_run_command_result(adapter, result, reference.command, opts.run_command_language)
  else
    content = result.content
    if type(content) ~= "string" then
      content = vim.inspect(content)
    end
  end

  return vim.split(content, "\n", { plain = true })
end

---@param chat_state table Per-chat extension state.
---@param reference table Tool reference.
---@param index integer Reference index.
---@param opts table Extension options.
---@param adapter table Message adapter.
---@param ui table UI adapter.
---@param reconcile fun(chat_state: table) Reconcile current chat messages.
---@return boolean displayed Whether the result was displayed.
function M.show(chat_state, reference, index, opts, adapter, ui, reconcile)
  local result = adapter.find_tool_result(chat_state.messages, reference.call_id)
  if not result then
    vim.notify(string.format("Tool result unavailable: %s (%s)", reference.name or "?", tostring(reference.call_id or "?")), vim.log.levels.WARN)
    return false
  end

  local lines = render_result(adapter, reference, result, opts)
  local title = string.format("Tool Result: %s [%d/%d]", result.name or "unknown", index, #chat_state.references)
  local float = chat_state.float

  if float and ui.update_float(float.bufnr, float.winnr, lines, { title = title }) then
    float.index = index
    if reference.name == "run_command" and reference.command and opts.run_command_language then
      vim.api.nvim_win_set_cursor(float.winnr, { math.min(2, #lines), 0 })
    end
    return true
  end

  if float then
    ui.close_float(float.bufnr, float.winnr)
  end

  local bufnr, winnr = ui.create_float(lines, { title = title })
  float = { bufnr = bufnr, winnr = winnr, index = index }
  chat_state.float = float

  local function close()
    if chat_state.float == float then
      chat_state.float = nil
    end
    ui.close_float(bufnr, winnr)
  end

  local function move(direction)
    if chat_state.float ~= float then
      return
    end

    reconcile(chat_state)
    local next_index = navigation.next_index(chat_state.references, float.index, direction)
    if next_index then
      M.show(chat_state, chat_state.references[next_index], next_index, opts, adapter, ui, reconcile)
    end
  end

  local mappings = {
    { "n", opts.float_next_keymap, function() move(1) end, "Next tool result" },
    { "n", opts.float_previous_keymap, function() move(-1) end, "Previous tool result" },
    { "n", opts.float_close_keymap, close, "Close tool result" },
    { "n", opts.float_escape_keymap, close, "Close tool result" },
  }
  for _, mapping in ipairs(mappings) do
    if mapping[2] then
      vim.keymap.set(mapping[1], mapping[2], mapping[3], { buffer = bufnr, silent = true, desc = mapping[4] })
    end
  end

  -- Avoid placing cursor in fence, this feels annoying in render-markdown as it disables hiding the fences.
  if reference.name == "run_command" and reference.command and opts.run_command_language then
    vim.api.nvim_win_set_cursor(winnr, { math.min(2, #lines), 0 })
  end

  return true
end

return M
