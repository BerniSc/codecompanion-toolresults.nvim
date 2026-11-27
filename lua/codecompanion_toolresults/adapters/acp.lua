local positions = require("codecompanion_toolresults.adapters.acp_positions")

local M = { id = "acp" }

-- Per-chat ordering metadata only. Never retain ACP records or their payloads here.
local observed_orders = setmetatable({}, { __mode = "k" })

-- ACP exposes active, completed, and failed states. Rejected/cancelled are HTTP result classifications; do not infer them from ACP records.
local outcomes = {
  pending = "active",
  in_progress = "active",
  completed = "completed",
  failed = "failed",
}

local function calls_for(chat)
  local calls = chat and chat.tool_calls and chat.tool_calls.acp
  return type(calls) == "table" and calls or {}
end

---@param chat CodeCompanionToolresults.CodeCompanionChat
---@param calls table Current ACP store map; malformed entries are ignored.
---@return string[] call_ids
local function order_for(chat, calls)
  -- Weak chat keys let closed chats be collected instead of pinning their ordering metadata for the session.
  local order = observed_orders[chat]
  if not order then
    local ids = {}
    for call_id, call in pairs(calls) do
      if type(call_id) == "string" and type(call) == "table" and call.toolCallId == call_id then
        ids[#ids + 1] = call_id
      end
    end
    table.sort(ids)
    order = { ids = {}, seen = {} }
    for _, call_id in ipairs(ids) do
      order.ids[#order.ids + 1] = call_id
      order.seen[call_id] = true
    end
    -- Register once. Later changes mutate this same table through "order".
    observed_orders[chat] = order
  end

  -- Existing/restored calls have no recoverable chronology, so sort their initial IDs. Later, if "beta" appears after "alpha" and "zeta", append
  -- it rather than reshuffling visible rows. Sort each new batch because ACP-store is a map and "pairs()" order is unspecified.
  local new_ids = {}
  for call_id, call in pairs(calls) do
    if type(call_id) == "string" and type(call) == "table" and call.toolCallId == call_id and not order.seen[call_id] then
      new_ids[#new_ids + 1] = call_id
    end
  end
  table.sort(new_ids)
  for _, call_id in ipairs(new_ids) do
    order.ids[#order.ids + 1] = call_id
    -- Remember IDs across reads so an existing map entry is not appended a second time.
    order.seen[call_id] = true
  end
  return order.ids
end

local function call_name(call)
  return call and (call.title or call.kind) or nil
end

---List current root-chat ACP calls without retaining their payloads.
---@param chat CodeCompanionToolresults.CodeCompanionChat
---@return CodeCompanionToolresults.ToolReference[]
function M.list_references(chat)
  if type(chat) ~= "table" then
    return {}
  end
  local calls = calls_for(chat)
  local references = {}
  for _, call_id in ipairs(order_for(chat, calls)) do
    local call = calls[call_id]
    if type(call) == "table" and call.toolCallId == call_id then
      references[#references + 1] = {
        call_id = call_id,
        name = call_name(call),
        provider = "acp",
        status = "available",
        provider_status = call.status or "unavailable",
        outcome = outcomes[call.status] or "unavailable",
      }
    end
  end
  return references
end

---Find live ACP call record by its stable toolCallId.
---@param chat CodeCompanionToolresults.CodeCompanionChat
---@param call_id string
---@return CodeCompanionToolresults.AcpToolCall? Current CodeCompanion ACP call record.
function M.find_call(chat, call_id)
  if type(call_id) ~= "string" then
    return nil
  end
  local call = calls_for(chat)[call_id]
  return type(call) == "table" and call.toolCallId == call_id and call or nil
end

---Find the current ACP record when output exists or the call reached a terminal status.
---@param chat CodeCompanionToolresults.CodeCompanionChat
---@param call_id string
---@return CodeCompanionToolresults.AcpToolCall? Current CodeCompanion ACP call record, or nil until output is available.
function M.find_result(chat, call_id)
  local call = M.find_call(chat, call_id)
  if not call then
    return nil
  end
  local has_content = type(call.content) == "table" and #call.content > 0
  if call.rawOutput ~= nil or has_content or call.status == "completed" or call.status == "failed" then
    return call
  end
  return nil
end

---@param chat CodeCompanionToolresults.CodeCompanionChat
---@param bufnr integer
---@param references CodeCompanionToolresults.ToolReference[]
function M.find_lines(chat, bufnr, references)
  return positions.find_tool_lines(bufnr, references, chat)
end

---Build plain overview rows directly from current ACP state.
---@param chat CodeCompanionToolresults.CodeCompanionChat
---@param summarise CodeCompanionToolresults.OverviewSummariser
---@return CodeCompanionToolresults.OverviewItem[]
function M.overview_items(chat, summarise)
  local items = {}
  for _, reference in ipairs(M.list_references(chat)) do
    local call = M.find_call(chat, reference.call_id)
    items[#items + 1] = {
      call_id = reference.call_id,
      index = #items + 1,
      name = reference.name,
      outcome = reference.outcome,
      summary = summarise(nil, call and type(call.rawInput) == "table" and call.rawInput or nil),
    }
  end
  return items
end

return M
