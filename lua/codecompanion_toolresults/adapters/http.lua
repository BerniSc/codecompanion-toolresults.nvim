local messages = require("codecompanion_toolresults.adapters.messages")
local positions = require("codecompanion_toolresults.adapters.positions")

local M = { id = "http" }

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@return CodeCompanionToolresults.ToolReference[]
function M.list_references(chat)
  return messages.tool_references(chat and chat.messages)
end

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@param bufnr integer Chat buffer.
---@param references CodeCompanionToolresults.ToolReference[]
---@return table<string, integer> positions
---@return table diagnostics
function M.find_lines(chat, bufnr, references)
  return positions.find_tool_lines(bufnr, references, chat)
end

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@param call_id string
function M.find_call(chat, call_id)
  return messages.find_tool_call(chat and chat.messages, call_id)
end

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@param call_id string
function M.find_result(chat, call_id)
  return messages.find_tool_result(chat and chat.messages, call_id)
end

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@param summarise CodeCompanionToolresults.OverviewSummariser
function M.overview_items(chat, summarise)
  return messages.overview_items(chat and chat.messages, summarise)
end

---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@param call_id string
---@return table? operation
---@return string? error
function M.prepare_tool_result_clear(chat, call_id)
  return messages.prepare_tool_result_clear(chat, call_id)
end

M.remove_run_command_prefix = messages.remove_run_command_prefix
M.normalize_result = messages.normalize_result

---Return live messages only for an explicit diagnostic snapshot.
---@param chat CodeCompanionToolresults.CodeCompanionChat CodeCompanion chat instance.
---@return table
function M.diagnostic_snapshot(chat)
  return chat and chat.messages or {}
end

return M
