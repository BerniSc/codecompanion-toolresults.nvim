local M = {}

---Extract CodeCompanion metadata used to identify a message.
---@param message table CodeCompanion message.
---@return table identity containing message ID and index.
local function get_message_identity(message)
  local metadata = message._meta or {}

  return {
    message_id = metadata.id,
    message_index = metadata.index,
  }
end

---Build an index of original toolcallcommands by ID.
---
---Tool-result messages can appear separately from the assistant message that contains their calls. Build
---the index first so references do not depend on message order. Rebuilding it during reconciliation also
---follows CodeCompanion when context management replaces or removes messages.
---@param messages table[] Current CodeCompanion message stack.
---@return table<string, string> Commands keyed by call ID.
local function index_tool_commands(messages)
  local cmds_by_id = {}

  for _, message in ipairs(messages or {}) do
    for _, call in ipairs((message.tools and message.tools.calls) or {}) do
      local function_call = call["function"] or {}
      local arguments = function_call.arguments

      if call.id and function_call.name == "run_command" and type(arguments) == "string" then
        local ok, decoded = pcall(vim.json.decode, arguments)
        arguments = ok and decoded or nil
      end

      if call.id and function_call.name == "run_command" and type(arguments) == "table" and type(arguments.cmd) == "string" then
        cmds_by_id[call.id] = arguments.cmd
      end
    end
  end

  return cmds_by_id
end

---Extract tool message references from a CodeCompanion message stack.
---@param messages table[] Current CodeCompanion message stack.
---@return table[] Tool references without tool output content.
function M.tool_references(messages)
  local references = {}
  local commands_by_id = index_tool_commands(messages)

  for _, message in ipairs(messages or {}) do
    if message.role == "tool" and message.tools then
      local identity = get_message_identity(message)

      references[#references + 1] = {
        call_id = message.tools.call_id,
        name = message.tools.name,
        command = commands_by_id[message.tools.call_id],
        message_id = identity.message_id,
        message_index = identity.message_index,
        status = "available",
      }
    end
  end

  return references
end

---Remove CodeCompanion's inline command prefix from a `run_command` result.
---
---CodeCompanion currently stores the command before its formatted output.
---Remove only that exact prefix; preserve all remaining output.
---@param content string Tool result content.
---@param command string Command stored before the output.
---@return string Content without the duplicated command prefix.
function M.remove_run_command_prefix(content, command)
  -- TODO Is matching greedy? Check this!
  local prefix = string.format("`%s`\n", command)
  if content:sub(1, #prefix) == prefix then
    -- remove prefix by returning string "starting after it"
    return content:sub(#prefix + 1)
  end

  return content
end

---Find the current tool result for a call ID.
---@param messages table[] Current CodeCompanion message stack.
---@param call_id string Tool-call identifier.
---@return table? Current result data, including transient content.
function M.find_tool_result(messages, call_id)
  if not call_id then
    return nil
  end

  for _, message in ipairs(messages or {}) do
    if message.role == "tool" and message.tools and message.tools.call_id == call_id then
      local identity = get_message_identity(message)

      return {
        call_id = message.tools.call_id,
        name = message.tools.name,
        message_id = identity.message_id,
        message_index = identity.message_index,
        content = message.content,
        status = "available",
      }
    end
  end
end

return M

