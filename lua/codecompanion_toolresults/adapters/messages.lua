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

---Extract tool message references from a CodeCompanion message stack.
---@param messages table[] Current CodeCompanion message stack.
---@return table[] Tool references without tool output content.
function M.tool_references(messages)
  local references = {}

  for _, message in ipairs(messages or {}) do
    if message.role == "tool" and message.tools then
      local identity = get_message_identity(message)

      references[#references + 1] = {
        call_id = message.tools.call_id,
        name = message.tools.name,
        message_id = identity.message_id,
        message_index = identity.message_index,
        status = "available",
      }
    end
  end

  return references
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


