local M = {}

local adapter = require("codecompanion_toolresults.adapters.messages")
local ui = require("codecompanion_toolresults.adapters.ui")

local position = require("codecompanion_toolresults.position")

local state_by_bufnr = {}
local configured = false

local defaults = {
  debug = false,
  debug_buffer = false,
  keymap = "gT",
}

--- --------------------
--- Logging
--- --------------------

---Notify a debug message when debugging is enabled or severity is high enough.
---@param message string Message to prefix and display.
---@param level? integer Neovim log level. Defaults to Info.
local function notify(message, level)
  level = level or vim.log.levels.INFO

  local important = level == vim.log.levels.ERROR or level == vim.log.levels.WARN
  -- exit early in case we dont want to log
  if not configured or (not M._opts.debug and not important) then
    return
  end

  vim.notify("codecompanion-toolresults: " .. message, level)
end

---Shorten a value for readable debug output.
---@param value any Value to convert and shorten.
---@param limit? integer Maximum output length. Defaults to 48.
---@return string
local function short(value, limit)
  if value == nil then
    return "?"
  end

  value = tostring(value)
  limit = limit or 48

  if #value <= limit then
    return value
  end

  -- keep first and last "half", replace chars in middle with "..."
  local prefix_length = math.floor((limit - 3) / 2)
  local suffix_length = limit - prefix_length - 3
  return value:sub(1, prefix_length) .. "..." .. value:sub(-suffix_length)
end

--- --------------------
--- /Logging
--- --------------------

--- --------------------
--- utils
--- --------------------

---Refresh rendered line positions for all current tool references.
---Should ensure that even if a user manually alters the chat by - for example - adding
---a new line before an existing toolout put can correctly be referenced.
---@param chat_state table Per-chat extension state.
---@return nil
local function refresh_positions(chat_state)
  local lines_by_call_id = position.find_tool_lines(chat_state.bufnr, chat_state.references)

  for call_id, reference in pairs(chat_state.tools) do
    reference.line = lines_by_call_id[call_id]
  end
end

---Reconcile current CodeCompanion messages into lightweight tool references.
---
---This reads the current message stack, but does not copy tool output into extension state.
---It can run after partial tool completion or a checkpoint.
---@param chat_state table Per-chat extension state.
---@return nil
local function reconcile_messages(chat_state)
  local references = adapter.tool_references(chat_state.messages)
  local tools_by_call_id = {}

  for _, reference in ipairs(references) do
    if reference.call_id then
      tools_by_call_id[reference.call_id] = reference
    end
  end

  chat_state.references = references
  chat_state.tools = tools_by_call_id
  refresh_positions(chat_state)
end

--- --------------------
--- /utils
--- --------------------

--- --------------------
--- Debugging
--- --------------------

---Format tool references for compact debug output.
---@param references table[] Tool references.
---@return string
local function serialize_references(references)
  local description = {}

  for _, reference in ipairs(references) do
    description[#description + 1] = string.format("%s:%s (message=%s, index=%s, line=%s)",
        reference.name or "?",
        short(reference.call_id),

        short(reference.message_id),
        short(reference.message_index),
        short(reference.line))
  end

  return table.concat(description, ", ")
end

---Format all lines in a buffer for compact debug output.
---@param bufnr integer Buffer to inspect.
---@return string
local function serialize_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return "buffer invalid"
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local description = {}

  for line_number, line in ipairs(lines) do
    description[#description + 1] = string.format("%d:%s", line_number, short(line, 80))
  end

  return table.concat(description, " | ")
end

---Log the rendered chat buffer after CodeCompanion updates it. Conditionbound on Buffer-
---Debbuging as well as regular debugging.
---@param chat_state table Per-chat extension state.
---@return nil
local function dump_buffer(chat_state)
  if not M._opts.debug_buffer then
    return
  end

  if state_by_bufnr[chat_state.bufnr] ~= chat_state then
    return
  end

  -- ensure state is up to date before dumping it
  refresh_positions(chat_state)
  notify(string.format("buffer: bufnr=%d %s", chat_state.bufnr, serialize_buffer(chat_state.bufnr)))
  notify(string.format("positions: bufnr=%d [%s]", chat_state.bufnr, serialize_references(chat_state.references)))
end

--- --------------------
--- /Debugging
--- --------------------

--- --------------------
--- Display
--- --------------------

---Display the current tool result under the cursor.
---@param chat_state table Per-chat extension state.
---@return nil
local function display_tool_reference(chat_state)
  -- it is possible that the chat has changed since last "scan". For example a newline could have been added
  -- or a line deleted which moves the toolresults. We therefore should refresh the chatstate on tryin to
  -- display at a certain line to ensure there is in fact a toolcall there.
  refresh_positions(chat_state)

  -- 1-based line coordinate of cursor in current window
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]

  -- TODO Think about maybe sorting/persisting state. Maybe bad for refreshes, but sorting and persisting could improve
  -- O(n) lookup time on average. We are most likely to lookup tools that are close the the end of the chat and order is
  -- unlikely to change anyhow
  local reference = position.find_reference_at_line(chat_state.tools, cursor_line)
  if not reference then
    -- Always display -> No "notify" but direct vim.notify
    vim.notify("No tool call on current line", vim.log.levels.INFO)
    return
  end

  -- Map result
  local result = adapter.find_tool_result(chat_state.messages, reference.call_id)
  if not result then
    -- Always display -> No "notify" but direct vim.notify
    vim.notify(string.format("Tool result unavailable: %s (%s)", reference.name or "?", short(reference.call_id)), vim.log.levels.WARN)
    return
  end

  local content = result.content
  if type(content) ~= "string" then
    content = vim.inspect(content)
  end

  -- TODO Add "bash" or something cooler for TS to the backticks
  -- Also think about option adding the parameters of the call there as well (might be cool/interesting)
  local lines = vim.split(content, "\n", { plain = true })
  ui.create_float(lines, {
    title = string.format("Tool Result: %s", result.name or "unknown"),
  })
end

--- --------------------
--- /Display
--- --------------------

--- --------------------
--- Callbacks
--- --------------------

---Attach lifecycle callbacks and state tracking to a CodeCompanion chat.
---@param chat table CodeCompanion chat instance.
---@param bufnr integer Chat buffer number.
---@return nil
local function attach_to_chat(chat, bufnr)
  if not chat or state_by_bufnr[bufnr] then
    return
  end

  local chat_state = {
    bufnr = bufnr,
    chat = chat,
    references = {},
    messages = {},
    tools = {},
  }

  state_by_bufnr[bufnr] = chat_state

  -- Record lightweight observation metadata before tool output enters the chat.
  -- This however does not include the toolresult yet, we get this via "on_checkpoint"
  chat:add_callback("on_tool_output", function(current_chat)
    chat_state.messages = current_chat.messages

    -- on_tool_output runs before CodeCompanion inserts the result of the call. Schedule reconciliation 
    -- so partial results become visible before the full batch finishes and triggers on_checkpoint.
    -- This allows inspecting for example the first toolcall of three.
    --
    -- This however is not an exact post-insert event boundary. If CodeCompanion would complete several tools in one
    -- synchronous turn, scheduled callbacks may observe several new results together. Exact per-tool post-insert
    -- observation would require a public CodeCompanion callback that exposes the completed call ID or message.
    vim.schedule(function()
      if state_by_bufnr[bufnr] ~= chat_state then
        return
      end

      reconcile_messages(chat_state)
      dump_buffer(chat_state)
    end)
  end)

  -- Reconcile tool references with CodeCompanion's current message stack.
  -- on_checkpoint is public API and hooks on save points in message cycle, for example after batch of tools is
  -- finished (thats the important one for us) and before and after msgs with/without tools are sent.
  -- This ensures we always have a clean representation of the current buffer at one of those checkpoints.
  chat:add_callback("on_checkpoint", function(_, data)
    chat_state.messages = data.messages
    reconcile_messages(chat_state)
    dump_buffer(chat_state)

    notify(string.format("checkpoint: bufnr=%d messages=%d estimated_tokens=%s tools=%d [%s]", bufnr, #(data.messages or {}), data.estimated_tokens or "?",
      #chat_state.references, serialize_references(chat_state.references)))
  end)

  -- Discard per-chat state when CodeCompanion permanently closes the chat.
  chat:add_callback("on_closed", function()
    state_by_bufnr[bufnr] = nil
    notify(string.format("chat closed: bufnr=%d", bufnr))
  end)

  notify(string.format("chat attached: bufnr=%d", bufnr))
end

---Resolve and attach to a newly created CodeCompanion chat.
---@param event table User autocmd event data.
---@return nil
local function on_chat_created(event)
  local bufnr = event.data and event.data.bufnr
  if not bufnr then
    notify("chat creation event has no buffer number", vim.log.levels.WARN)
    return
  end

  local ok, codecompanion = pcall(require, "codecompanion")
  if not ok then
    notify("could not load CodeCompanion", vim.log.levels.ERROR)
    return
  end

  ---already ensured cc is loaded correctly and "buf_get_chat" is documented public api
  ---@diagnostic disable-next-line: undefined-field
  local chat = codecompanion.buf_get_chat(bufnr)
  if not chat then
    notify(string.format("could not resolve chat for bufnr=%d", bufnr), vim.log.levels.WARN)
    return
  end

  attach_to_chat(chat, bufnr)
end

--- --------------------
--- /Callbacks
--- --------------------

---
---

---Configure the extension and register its CodeCompanion integrations.
---@param opts? table Extension options.
---@return nil
function M.setup(opts)
  -- merge with default options
  M._opts = vim.tbl_deep_extend("force", defaults, opts or {})
  configured = true

  -- Should attach keymap?
  if M._opts.keymap then
    local chat_keymaps = require("codecompanion.config").interactions.chat.keymaps
    chat_keymaps.display_toolresults = {
      modes = { n = M._opts.keymap, },
      description = "Display tool result under cursor",

      -- Resolve and display the tool result at the current cursor line.
      callback = function()
        local current_state = state_by_bufnr[vim.api.nvim_get_current_buf()]

        if current_state then
          -- Handles non-tc locations itsself gracefully
          display_tool_reference(current_state)
        else
          vim.notify("No tracked CodeCompanion chat", vim.log.levels.INFO)
        end
      end,
    }
  end

  -- Attach monitoring to new chat instances
  local group = vim.api.nvim_create_augroup("CodeCompanionToolresults", { clear = true })
  vim.api.nvim_create_autocmd("User", {
    pattern = "CodeCompanionChatCreated", callback = on_chat_created,
    desc = "Observe CodeCompanion chats for tool result references", group = group })
end

---Return current per-chat extension state.
---@return table<integer, table>
function M.state()
  return state_by_bufnr
end

return M
