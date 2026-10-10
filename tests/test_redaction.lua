local MiniTest = require("mini.test")
local redaction = require("codecompanion_toolresults.redaction")
local messages = require("codecompanion_toolresults.adapters.messages")

local T = MiniTest.new_set()

local function start(state, call_id, deps, on_done)
  redaction.start(state, call_id, messages, deps, on_done)
end

local function make_context(content)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false,
    vim.list_extend({ "grep_search" }, vim.split(content, "\n", { plain = true, trimempty = false })))
  local message = {
    role = "tool",
    content = content,
    tools = { call_id = "call-1", name = "grep_search" },
    _meta = { id = "keep-this-id", index = 3, estimated_tokens = 500, cycle = 2 },
  }
  local chat = { bufnr = bufnr, messages = { message } }
  local state = {
    chat = chat,
    messages = chat.messages,
    tools = { ["call-1"] = { line = 1 } },
    references = { { call_id = "call-1", line = 1 } },
  }
  return state, message, bufnr
end

local function prompts()
  local queued = {}
  local deps = {}
  deps.notifications = {}
  deps.notify = function(text, level)
    table.insert(deps.notifications, { text, level })
  end
  deps.select = function(items, opts, callback)
    table.insert(queued, { items = items, opts = opts, callback = callback })
  end
  deps.input = function(opts, callback)
    deps.input_prompt = opts.prompt
    deps.input_callback = callback
  end
  return queued, deps
end

T["adapter operation"] = MiniTest.new_set()

T["adapter operation"]["finds exact unique call ID in current chat messages"] = function()
  local chat = { messages = {
    { role = "tool", tools = { call_id = "one", name = "first" }, content = "first" },
    { role = "tool", tools = { call_id = "two", name = "second" }, content = "second" },
  } }
  local operation, err = messages.prepare_tool_result_clear(chat, "two")
  assert(operation, err)
  MiniTest.expect.equality(operation.name, "second")
  MiniTest.expect.equality(err, nil)
end

T["adapter operation"]["rejects missing and ambiguous call IDs"] = function()
  local missing, missing_error = messages.prepare_tool_result_clear({ messages = {} }, "none")
  MiniTest.expect.equality(missing, nil)
  assert(missing_error)
  MiniTest.expect.equality(missing_error:find("no longer available", 1, true) ~= nil, true)

  local duplicate, duplicate_error = messages.prepare_tool_result_clear({ messages = {
    { role = "tool", tools = { call_id = "same" }, content = "first" },
    { role = "tool", tools = { call_id = "same" }, content = "second" },
  } }, "same")
  MiniTest.expect.equality(duplicate, nil)
  assert(duplicate_error)
  MiniTest.expect.equality(duplicate_error:find("More than one", 1, true) ~= nil, true)
end

T["adapter operation"]["does not mistake literal marker-prefixed output for a clear"] = function()
  local content = "User cleared this tool result. this is actual output"
  local operation, err = messages.prepare_tool_result_clear({ messages = {
    { role = "tool", tools = { call_id = "literal" }, content = content },
  } }, "literal")
  MiniTest.expect.equality(operation ~= nil, true)
  MiniTest.expect.equality(err, nil)
end

T["adapter operation"]["refuses chat activity and rechecks after prompts"] = function()
  local chat = { messages = {}, current_request = {} }
  local operation, err = messages.prepare_tool_result_clear(chat, "call-1")
  MiniTest.expect.equality(operation, nil)
  assert(err)
  MiniTest.expect.equality(err:find("Wait for the current request", 1, true) ~= nil, true)

  chat.current_request = nil
  local original = { role = "tool", tools = { call_id = "call-1", name = "grep_search" }, content = "original" }
  chat.messages = { original }
  operation = messages.prepare_tool_result_clear(chat, "call-1")
  assert(operation)
  chat.messages = { { role = "tool", tools = { call_id = "call-1" }, content = "replacement message" } }
  local changed, _, commit_error = operation.commit("cleared")
  MiniTest.expect.equality(changed, false)
  assert(commit_error)
  MiniTest.expect.equality(commit_error:find("changed during confirmation", 1, true) ~= nil, true)
  MiniTest.expect.equality(original.content, "original")
end

T["workflow"] = MiniTest.new_set()

T["workflow"]["mutates tool history only and leaves rendered transcript unchanged"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  local done
  start(state, "call-1", deps, function(changed) done = changed end)

  MiniTest.expect.equality(message.content, "large result")
  MiniTest.expect.equality(#queued, 1)
  MiniTest.expect.equality(queued[1].opts.prompt:find("<Esc>", 1, true) ~= nil, true)
  queued[1].callback("Wrong language or path")
  MiniTest.expect.equality(message.content, "large result")
  MiniTest.expect.equality(#queued, 2)
  MiniTest.expect.equality(queued[2].opts.prompt:find("<Esc>", 1, true) ~= nil, true)
  queued[2].callback("Clear result")

  MiniTest.expect.equality(message.content, "User cleared this tool result. Reason: Wrong language or path")
  MiniTest.expect.equality(message._meta.id, "keep-this-id")
  MiniTest.expect.equality(message._meta.index, 3)
  MiniTest.expect.equality(message._meta.cycle, 2)
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "grep_search", "large result" })
  MiniTest.expect.equality(state.messages, state.chat.messages)
  MiniTest.expect.equality(done, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["does not treat literal marker-prefixed output as already cleared"] = function()
  local state, message, bufnr = make_context("User cleared this tool result. legitimate result")
  local queued, deps = prompts()
  start(state, "call-1", deps)
  queued[1].callback("Clear without reason")
  queued[2].callback("Clear result")
  MiniTest.expect.equality(message.content, "User cleared this tool result.")
  MiniTest.expect.equality(message._meta.codecompanion_toolresults_cleared, true)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["cancel from reason chooser leaves everything unchanged"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  local done
  start(state, "call-1", deps, function(changed) done = changed end)
  queued[1].callback(nil)
  MiniTest.expect.equality(message.content, "large result")
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "grep_search", "large result" })
  MiniTest.expect.equality(done, false)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["declined final confirmation leaves everything unchanged"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  local done
  start(state, "call-1", deps, function(changed) done = changed end)
  queued[1].callback("Too much output")
  queued[2].callback("Cancel")
  MiniTest.expect.equality(message.content, "large result")
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "grep_search", "large result" })
  MiniTest.expect.equality(done, false)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["empty or cancelled custom reason is a no-op"] = function()
  for _, value in ipairs({ "<cancel>", "" }) do
    local state, message, bufnr = make_context("large result")
    local queued, deps = prompts()
    local done
    start(state, "call-1", deps, function(changed) done = changed end)
    queued[1].callback("Other…")
    if value == "<cancel>" then
      deps.input_callback(nil)
    else
      deps.input_callback(value)
      MiniTest.expect.equality(#queued, 1)
    end
    MiniTest.expect.equality(message.content, "large result")
    MiniTest.expect.equality(done, false)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

T["workflow"]["leaves transformed user-facing output untouched"] = function()
  local state, message, bufnr = make_context("hidden from rendered buffer")
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "grep_search", "transformed user-facing result" })
  local queued, deps = prompts()
  local done
  start(state, "call-1", deps, function(changed) done = changed end)
  queued[1].callback("Redundant result")
  queued[2].callback("Clear result")
  MiniTest.expect.equality(message.content, "User cleared this tool result. Reason: Redundant result")
  MiniTest.expect.equality(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), { "grep_search", "transformed user-facing result" })
  MiniTest.expect.equality(done, true)
  MiniTest.expect.equality(deps.notifications[#deps.notifications][1],
    "Tool result cleared from future local context. Other chat messages may still contain its output.")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["normalizes custom reason to one line"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  start(state, "call-1", deps)
  queued[1].callback("Other…")
  MiniTest.expect.equality(deps.input_prompt:find("<Esc>", 1, true) ~= nil, true)
  MiniTest.expect.equality(deps.input_prompt:find("empty input", 1, true) ~= nil, true)
  deps.input_callback("Task is C++\nnot Python")
  queued[2].callback("Clear result")
  MiniTest.expect.equality(message.content, "User cleared this tool result. Reason: Task is C++ not Python")
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["accepts a 160-byte custom reason"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  local reason = string.rep("x", 160)
  start(state, "call-1", deps)
  queued[1].callback("Other…")
  deps.input_callback(reason)

  MiniTest.expect.equality(#queued, 2)
  queued[2].callback("Clear result")
  MiniTest.expect.equality(message.content, "User cleared this tool result. Reason: " .. reason)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

T["workflow"]["rejects a custom reason over 160 bytes"] = function()
  local state, message, bufnr = make_context("large result")
  local queued, deps = prompts()
  local done
  start(state, "call-1", deps, function(changed) done = changed end)
  queued[1].callback("Other…")
  deps.input_callback(string.rep("x", 161))

  MiniTest.expect.equality(#queued, 1)
  MiniTest.expect.equality(deps.notifications[#deps.notifications][1],
    "Reason must be 160 characters or fewer; nothing was changed.")
  MiniTest.expect.equality(message.content, "large result")
  MiniTest.expect.equality(done, false)
  vim.api.nvim_buf_delete(bufnr, { force = true })
end

return T
