local M = {}

-- TODO Think about making this configurable, but for now that would be too much noise for too little benefit.
local reasons = {
  "Too much output",
  "Redundant result",
  "Wrong language or path",
  "Irrelevant to current task",
  "Clear without reason",
  "Other…",
  "Cancel",
}

local function default_select(items, opts, callback)
  vim.ui.select(items, opts, callback)
end

local function default_input(opts, callback)
  vim.ui.input(opts, callback)
end

local function default_notify(message, level)
  vim.notify(message, level)
end

local function single_line(text)
  return vim.trim((text:gsub("[%s\r\n]+", " ")))
end

--- The CodeCompanion adapter resolves the unique original tool message by call_id and owns its in-place mutation.
--- This workflow keeps only the adapter operation across asynchronous prompts, never a copied result.
---
---Start a cancellable result-clearing workflow. No mutation occurs until final confirmation.
---@param chat_state CodeCompanionToolresults.ChatState
---@param call_id string
---@param adapter CodeCompanionToolresults.RedactionAdapter CodeCompanion message adapter capability used by this workflow.
---@param deps? CodeCompanionToolresults.RedactionDeps Optional overrides for this workflow's UI.
---@param on_done? fun(changed: boolean)
function M.start(chat_state, call_id, adapter, deps, on_done)
  deps = deps or {}
  local choose = deps.select or default_select
  local ask = deps.input or default_input
  local report = deps.notify or default_notify
  local complete = on_done or function() end

  local operation, prepare_error = adapter.prepare_tool_result_clear(chat_state.chat, call_id)
  if not operation then
    report(prepare_error, vim.log.levels.WARN)
    complete(false)
    return
  end

  ---@param reason string? Optional reason appended to replacement content.
  local function confirm(reason)
    local replacement = "User cleared this tool result."
    if reason and reason ~= "" then
      replacement = replacement .. " Reason: " .. reason
    end

    choose({ "Clear result", "Cancel" }, {
      prompt = string.format("Replace %s result permanently? Future local requests use marker; prior/provider context unchanged. <Esc> cancels", operation.name),
    }, function(choice)
      if choice ~= "Clear result" then
        complete(false)
        return
      end

      -- Prompts are asynchronous. The adapter rechecks chat activity and the selected message before mutating.
      local changed, current_messages, commit_error = operation.commit(replacement)
      if not changed then
        report(commit_error, vim.log.levels.WARN)
        complete(false)
        return
      end

      assert(current_messages, "successful clear operation must return current messages")
      chat_state.messages = current_messages
      report("Tool result cleared from future local context. Other chat messages may still contain its output.", vim.log.levels.WARN)
      complete(true)
    end)
  end

  choose(reasons, {
    prompt = "Why clear this result? Choose Cancel or press <Esc> to leave it unchanged",
  }, function(choice)
    if not choice or choice == "Cancel" then
      complete(false)
      return
    end

    if choice == "Other…" then
      ask({ prompt = "Short reason (optional; empty input or <Esc> cancels): " }, function(text)
        if text == nil then
          complete(false)
          return
        end
        text = single_line(text)
        if text == "" then
          complete(false)
          return
        end
        -- Lua's # counts bytes; the current 160-byte limit assumes single-byte reason text.
        if #text > 160 then
          report("Reason must be 160 characters or fewer; nothing was changed.", vim.log.levels.WARN)
          complete(false)
          return
        end
        confirm(text)
      end)
      return
    end

    if choice == "Clear without reason" then
      confirm(nil)
    else
      confirm(choice)
    end
  end)
end

M._reasons = reasons

return M
