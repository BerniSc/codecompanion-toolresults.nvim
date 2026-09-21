local M = {}

local function rejection_base(line)
  return line:gsub(', with the reason: ".*"$', "")
end

---Return the first rendered line of a declined-tool message.
---@param content any Tool output content.
---@param name? string Tool name.
---@param command? string Parsed run_command command.
---@return string? line Rendered rejection line, or nil for ordinary output.
local function invalidated_line(content, name, command)
  if type(content) ~= "string" then
    return nil
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
---@param messages table[] Current CodeCompanion message stack.
---@return table[] Tool references without tool output content.
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

