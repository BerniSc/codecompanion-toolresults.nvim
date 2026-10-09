local M = {}

local function rejection_base(line)
  return line:gsub(', with the reason: ".*"$', "")
end

---Find recognized cancellation or rejection text in a tool result.
---@param content any Tool output content.
---@param name? string Tool name.
---@param command? string Parsed run_command command.
---@return string? line Rejection text, or nil for ordinary output.
local function invalidated_line(content, name, command)
  if type(content) ~= "string" then
    return nil
  end

  -- Multiline commands make the rejection span several lines. Match the exact
  -- command text, then retain an optional reason attached to its closing line.
  if name == "run_command" and type(command) == "string" and command:find("\n", 1, true) then
    local rejection = string.format("The user rejected the execution of the `%s` command", command)
    local _, rejection_end = content:find(rejection, 1, true)
    if rejection_end then
      local reason = content:sub(rejection_end + 1):match('^(, with the reason: "[^"]*")')
      return rejection .. (reason or "")
    end
  end

  for raw_line in content:gmatch("[^\r\n]+") do
    local line = vim.trim(raw_line)
    local base_line = rejection_base(line)

    -- cancellation.
    local is_cancelled = type(name) == "string"
      and line == string.format("The user cancelled the execution of the %s tool", name)

    if is_cancelled then
      return string.format("Cancelled `%s`", name)
    end

    -- rejection.
    local is_rejection = name == "run_command" and type(command) == "string"
      and base_line == string.format("The user rejected the execution of the `%s` command", command)

    if is_rejection
      or base_line == "The user rejected the grep search tool"
      or base_line == "The user rejected the search help tool"
      or base_line == "The user rejected the file search tool"
      or base_line == "The user rejected the read file tool"
      or base_line == "The user rejected the creation of the file"
      or base_line == "The user rejected the deletion of the file"
      or base_line == "The user rejected the get diagnostics tool"
      or base_line == "The user rejected the get changed files tool"
      or base_line == "The user rejected the memory operation"
      -- TODO Monitor, codecompanion uses once with `` in cmd_tool and once without in orchestrator
      or base_line:match("^The user rejected the execution of the [^ ]+ tool$")
      or line:match('^User rejected the changes for .-`, with the reason ".-"$')    -- insert edit into file
    then
      return line
    end
  end

  -- basecase - not invalidated.
  return nil
end

---Extract CodeCompanion metadata used to identify a message.
---@param message table CodeCompanion message.
---@return { message_id: number?, message_index: integer? } identity containing message ID and index.
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
---@param messages CodeCompanion.Chat.Messages Current CodeCompanion message stack.
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

      if function_call.name == "run_command" and type(arguments) == "table" and type(arguments.cmd) == "string" then
        local call_id = call.call_id or call.id
        if call_id then
          cmds_by_id[call_id] = arguments.cmd
        end
      end
    end
  end

  return cmds_by_id
end

---Extract tool message references from a CodeCompanion message stack.
---@param messages CodeCompanion.Chat.Messages Current CodeCompanion message stack.
---@return CodeCompanionToolresults.ToolReference[] Tool references without tool output content.
function M.tool_references(messages)
  local references = {}
  local commands_by_id = index_tool_commands(messages)

  for _, message in ipairs(messages or {}) do
    if message.role == "tool" and message.tools then
      local identity = get_message_identity(message)

      local command = commands_by_id[message.tools.call_id]
      local invalidated = invalidated_line(message.content, message.tools.name, command)

      references[#references + 1] = {
        call_id = message.tools.call_id,
        name = message.tools.name,
        command = command,
        invalidated_line = invalidated,
        message_id = identity.message_id,
        message_index = identity.message_index,
        -- a ? b : c equivalent
        status = invalidated and "invalidated" or "available",
      }
    end
  end

  return references
end

-- TODO Consolidate call scanning and argument decoding with index_tool_commands.
---Find the current tool call for a call ID.
---@param messages CodeCompanion.Chat.Messages Current CodeCompanion message stack.
---@param call_id string Tool-call identifier.
---@return CodeCompanionToolresults.ToolCall? Current tool-call data, including transient arguments.
function M.find_tool_call(messages, call_id)
  if not call_id then
    return nil
  end

  for _, message in ipairs(messages or {}) do
    for _, call in ipairs((message.tools and message.tools.calls) or {}) do
      local call_identity = call.call_id or call.id
      if call_identity == call_id then
        local function_call = call["function"] or {}
        local arguments = function_call.arguments

        if type(arguments) == "string" then
          local ok, decoded = pcall(vim.json.decode, arguments)
          if ok then
            arguments = decoded
          end
        end

        return {
          call_id = call_identity,
          name = function_call.name or call.name,
          arguments = arguments,
        }
      end
    end
  end
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

---Remove CodeCompanion truncation notices from result content for display.
---
---The exact markers belong to the CodeCompanion adapter boundary rather than renderers.
---@param content string Tool result content.
---@return string clean_content
---@return string? notice The final truncation notice, if present.
local function remove_truncation_notice(content)
  local patterns = {
    "^(.-)\n\n(%[Tool output truncated:.-%])%s*$",
    "^(.-)\n\n(%[Truncated at .-%])%s*$",
    "^(.-)\n\n(%.%.%.%[truncated%])%s*$",
  }

  for _, pattern in ipairs(patterns) do
    -- will return the captures.
    local clean_content, notice = content:match(pattern)
    if notice then
      return clean_content, notice
    end
  end

  return content, nil
end

--- TODO Consider moving result normalization into a dedicated `adapters/results.lua` module.
--- `messages.lua` currently owns it because the formats are CodeCompanion-specific.
---Normalize result content for renderer presentation.
---@param content any Tool result content.
---@return string clean_content
---@return table metadata
function M.normalize_result(content)
  if type(content) ~= "string" then
    return vim.inspect(content), { truncation_notice = nil }
  end

  local clean_content, notice = remove_truncation_notice(content)
  return clean_content, { truncation_notice = notice }
end

---Find the current tool result for a call ID.
---@param messages CodeCompanion.Chat.Messages Current CodeCompanion message stack.
---@param call_id string Tool-call identifier.
---@return CodeCompanionToolresults.ToolResult? Current result data, including transient content.
function M.find_tool_result(messages, call_id)
  if not call_id then
    return nil
  end

  for _, message in ipairs(messages or {}) do
    if message.role == "tool" and message.tools and message.tools.call_id == call_id then
      local identity = get_message_identity(message)

      ---@type CodeCompanionToolresults.ToolResult
      local result = {
        call_id = message.tools.call_id,
        name = message.tools.name,
        message_id = identity.message_id,
        message_index = identity.message_index,
        content = message.content,
        status = "available",
      }
      if message._meta and message._meta.estimated_tokens ~= nil then
        result.estimated_tokens = message._meta.estimated_tokens
      end
      -- Attribute saved by us. Not yet persistent over restored sessions.
      if message._meta and message._meta.codecompanion_toolresults_cleared == true then
        result.cleared = true
      end
      return result
    end
  end
end

---Prepare a tool-result clear operation against CodeCompanion's live chat for the unique original
---CodeCompanion message identified by tool call ID for clearing.
---The operation retains the original message for in-place mutation; it does not copy result content.
---Its commit method rechecks chat activity and message identity after asynchronous prompts.
---On success, commit returns the chat's current messages table.
---@param chat table CodeCompanion chat instance.
---@param call_id string Tool-call identifier.
---@return CodeCompanionToolresults.ToolResultClearOperation? operation
---@return string? error
function M.prepare_tool_result_clear(chat, call_id)
  -- Keep live CodeCompanion reference; async prompts require rechecking current messages before mutation.
  if not chat then
    return nil, "Chat is no longer available; nothing was changed."
  end
  if chat.current_request or chat.tool_orchestrator then
    return nil, "Wait for the current request and tool batch to finish before clearing a result."
  end

  local function find_unique_tool_result_message()
    local found
    for _, message in ipairs(chat.messages or {}) do
      if message.role == "tool" and message.tools and message.tools.call_id == call_id then
        if found then
          return nil, "More than one tool result has this call ID; nothing was changed."
        end
        found = message
      end
    end

    if not found then
      return nil, "Tool result is no longer available; nothing was changed."
    end
    if type(found.content) ~= "string" then
      return nil, "Tool result content is not editable; nothing was changed."
    end
    if found._meta and found._meta.codecompanion_toolresults_cleared == true then
      return nil, "Tool result was already cleared."
    end

    return found
  end

  local selected, err = find_unique_tool_result_message()
  if not selected then
    return nil, err
  end

  local function commit(content)
    -- Prompts are asynchronous. Refuse stale selection or a chat that became active meanwhile.
    if chat.current_request or chat.tool_orchestrator then
      return false, nil, "Chat activity started during confirmation; nothing was changed."
    end

    local current, find_error = find_unique_tool_result_message()
    if not current or current ~= selected then
      return false, nil, find_error or "Tool result changed during confirmation; nothing was changed."
    end

    -- Checkpoints report a chat-wide estimate; they do not refresh each message's estimate after this mutation.
    -- Recalculate for the replacement content so the old tool-output estimate is not left stale.
    local estimated_tokens
    local ok, tokens = pcall(require, "codecompanion.utils.tokens")
    if ok and type(tokens) == "table" and type(tokens.calculate) == "function" then
      local calculated, value = pcall(tokens.calculate, content)
      if calculated and type(value) == "number" then
        estimated_tokens = value
      end
    end

    current.content = content
    current._meta = current._meta or {}
    current._meta.estimated_tokens = estimated_tokens
    -- Keep plugin state in CodeCompanion's metadata, not inferred from result text. The current
    -- session serialiser preserves only `_meta.tag`, so this flag is lost when a session is restored.
    -- TODO: Ask Oli Morris for a supported way to persist namespaced plugin metadata.
    current._meta.codecompanion_toolresults_cleared = true
    return true, chat.messages
  end

  return {
    name = selected.tools.name or "tool",
    commit = commit,
  }
end

return M

