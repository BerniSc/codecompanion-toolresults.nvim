---Pure presentation model for the tool overview.
---
---This module builds rows and groups from plain data. It does not open windows, read chat state, or
---store anything. Callers supply outcomes and arguments looked up from current CodeCompanion messages.
local M = {}

M.groupings = { "none", "outcome", "tool" }

M.grouping_labels = {
  none = "No grouping",
  outcome = "Outcome",
  tool = "Tool type",
}

M.outcome_labels = {
  completed = "Completed",
  failed = "Failed",
  rejected = "Rejected",
  cancelled = "Cancelled",
  unavailable = "Unavailable",
}

-- Display order for outcome groups. Only groups with calls appear.
local outcome_order = { "completed", "failed", "rejected", "cancelled", "unavailable" }

local outcome_glyphs = {
  completed = "✓",
  failed = "!",
  rejected = "×",
  cancelled = "-",
  unavailable = "?",
}

-- Argument keys tried in order when a tool has no run_command. The first string value wins, so earlier keys
-- take priority if a tool passes several.
local summary_keys = { "filepath", "path", "query", "search_term", "pattern", "file" }
local max_summary_chars = 54

---Flatten text to one line and truncate it by characters, not bytes.
---@param text string
---@return string
local function compact(text)
  local flat = vim.trim((text:gsub("\r?\n", " ")))
  if vim.fn.strchars(flat) > max_summary_chars then
    return vim.fn.strcharpart(flat, 0, max_summary_chars) .. "…"
  end
  return flat
end

---Summarise a tool call for one overview row.
---
---The command is used when present. Otherwise the first known string argument is used. The summary is
---display-only and does not assume an execution shell.
---@param command? string Parsed run_command input.
---@param arguments? table Decoded tool arguments.
---@return string
function M.summary(command, arguments)
  if type(command) == "string" and command ~= "" then
    return compact(command)
  end
  if type(arguments) ~= "table" then
    return ""
  end
  for _, key in ipairs(summary_keys) do
    if type(arguments[key]) == "string" then
      return compact(arguments[key])
    end
  end
  return ""
end

---Format one overview row.
---@param item CodeCompanionToolresults.OverviewItem
---@return string
function M.format_row(item)
  return string.format(" %02d  %s  %-17s %s", item.index, outcome_glyphs[item.outcome] or "?",
    item.name or "unknown", item.summary)
end

---Return the group key and label for one item under a grouping.
---@param item CodeCompanionToolresults.OverviewItem Overview item.
---@param grouping CodeCompanionToolresults.OverviewGrouping
---@return string key
---@return string? label
local function group_of(item, grouping)
  if grouping == "outcome" then
    return item.outcome, M.outcome_labels[item.outcome] or item.outcome
  end
  if grouping == "tool" then
    local name = item.name or "unknown"
    return name, name
  end
  return "all", nil
end

---Group items for display, preserving message order inside each group.
---
---Outcome groups follow a fixed order. Tool groups follow first appearance in the chat.
---@param items CodeCompanionToolresults.OverviewItem[] Items in message order.
---@param grouping CodeCompanionToolresults.OverviewGrouping One of `M.groupings`.
---@return CodeCompanionToolresults.OverviewGroup[]? groups
---@return string? error
function M.group(items, grouping)
  if not vim.tbl_contains(M.groupings, grouping) then
    return nil, string.format("unknown overview grouping: %s", tostring(grouping))
  end
  if #items == 0 then
    return {}
  end

  local groups = {}
  local by_key = {}
  for _, item in ipairs(items) do
    local key, label = group_of(item, grouping)
    local group = by_key[key]
    if not group then
      group = { key = key, label = label, items = {} }
      by_key[key] = group
      groups[#groups + 1] = group
    end
    group.items[#group.items + 1] = item
  end

  if grouping == "outcome" then
    local ordered = {}
    for _, outcome in ipairs(outcome_order) do
      if by_key[outcome] then
        ordered[#ordered + 1] = by_key[outcome]
      end
    end
    groups = ordered
  end

  return groups
end

return M
