local M = {}

---Format content as a fenced Markdown code block.
---
---Use at least four backticks and grow fence length when content contains
---longer backtick runs, so embedded Markdown remains literal.
---@param content any Content to format.
---@param language? string Optional fence language label.
---@return string Markdown code block.
local function format_codeblock(content, language)
  content = tostring(content)
  language = type(language) == "string" and language:match("^[^\r\n]*") or ""

  local longest_fence = 0
  for backticks in content:gmatch("`+") do
    longest_fence = math.max(longest_fence, #backticks)
  end

  local fence = string.rep("`", math.max(4, longest_fence + 1))
  -- ternary equivalent (a ? b : c).
  local suffix = content:sub(-1) == "\n" and "" or "\n"
  return string.format("%s%s\n%s%s%s", fence, language, content, suffix, fence)
end

---@param content any Content to convert to a string.
---@return string
local function content_as_string(content)
  if type(content) == "string" then
    return content
  end

  return vim.inspect(content)
end

---@param content string
---@return string[]
local function split_lines(content)
  return vim.split(content, "\n", { plain = true })
end

---Format arbitrary tool-call arguments for the managed float.
---Structured arguments display as JSON; scalar or malformed arguments display as text.
---@param arguments any Tool-call arguments.
---@return string[]
local function render_call_arguments(arguments)
  local content
  local language

  if type(arguments) == "table" then
    local ok, encoded = pcall(vim.json.encode, arguments, { indent = "  ", sort_keys = true })
    if ok then
      content = encoded
      language = "json"
    else
      content = vim.inspect(arguments)
      language = "text"
    end
  elseif type(arguments) == "string" then
    content = arguments
    language = "text"
  else
    content = vim.inspect(arguments)
    language = "text"
  end

  return split_lines(format_codeblock(content, language))
end

---Render a tool call as display lines without assuming how tool executes.
---@param call table Current tool call.
---@return string[]
function M.render_call(call, opts)
  local name = call.name or "unknown"
  local arguments = call.arguments
  local content
  local language
  local heading

  if arguments == nil then
    content = "Unavailable"
    language = "text"
    heading = "Arguments"
  elseif name == "run_command" and type(arguments) == "table" and type(arguments.cmd) == "string" then
    content = arguments.cmd
    language = opts and opts.run_command_language or "text"
    heading = "Command"
  else
    local rendered = render_call_arguments(arguments)
    local lines = { "Tool: " .. tostring(name), "Arguments:" }
    vim.list_extend(lines, rendered)
    return lines
  end

  local lines = { "Tool: " .. tostring(name), heading .. ":" }
  vim.list_extend(lines, split_lines(format_codeblock(content, language)))

  -- TODO Refactor behind interface? Kind of clunky to have this "if cascade" here!
  if name == "run_command" and type(arguments) == "table" then
    local other_arguments = vim.deepcopy(arguments)
    other_arguments.cmd = nil

    -- Keep the common command-only view compact, but do not hide any additional input fields.
    if next(other_arguments) then
      vim.list_extend(lines, { "Other arguments:" })
      vim.list_extend(lines, render_call_arguments(other_arguments))
    end
  end

  return lines
end

---@param content string
---@param tag string
---@return string
local function remove_tag(content, tag)
  content = content:gsub("^<" .. tag .. ">", "")
  content = content:gsub("</" .. tag .. ">$", "")
  return content
end

-- TODO Doc, also search for tool truncated output warning, if so set var and then let this display on top
local function fenced_block(content)
  local fence, language, body = content:match("(```+)([^\n]*)\n(.-)\n%1%s*$")
  if not body then
    return nil
  end

  return {
    fence = fence,
    language = language,
    body = body,
  }
end

-- TODO Doc
local function fenced_text(content)
  return format_codeblock(content, "text")
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_fallback(reference, content, opts, context)
  return vim.split(content, "\n", { plain = true })
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_run_command(reference, content, opts, context)
  local language = opts.run_command_language

  if type(reference.command) ~= "string" or not language then
    return vim.split(content, "\n", { plain = true })
  end

  local output = context.remove_run_command_prefix(content, reference.command)
  local rendered = string.format("%s\n%s", format_codeblock(reference.command, language), output)
  return vim.split(rendered, "\n", { plain = true })
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_file_search(reference, content, opts, context)
  content = remove_tag(content, "fileSearchTool")
  local block = fenced_block(content)
  if not block then
    return split_lines(content)
  end
  local summary = content:match("^[^\n]+") or ""
  return split_lines(summary .. "\n" .. fenced_text(block.body))
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_grep_search(reference, content, opts, context)
  content = remove_tag(content, "grepSearchTool")
  content = content:match("^(.-)\n\nNOTE:") or content
  local block = fenced_block(content)
  if not block then
    return split_lines(content)
  end
  local summary = content:match("^[^\n]+") or ""
  return split_lines(summary .. "\n" .. fenced_text(block.body))
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_read_file(reference, content, opts, context)
  local block = fenced_block(content)
  if not block then
    return split_lines(content)
  end
  local header = content:match("^[^\n]+") or ""
  local rendered = header .. "\n" .. block.fence .. block.language .. "\n" .. block.body .. "\n" .. block.fence
  return split_lines(rendered)
end

---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_get_diagnostics(reference, content, opts, context)
  return split_lines(content)
end

---Render insert_edit_into_file's summary followed by unified diffs of supplied edit snippets.
---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[]
local function render_insert_edit_into_file(reference, content, opts, context)
  local lines = split_lines(content)
  local call = context.find_tool_call and context.find_tool_call(reference.call_id)
  local arguments = call and call.arguments
  local edits = type(arguments) == "table" and arguments.edits or nil
  -- Could not look up required data, return to fallback.
  if type(edits) ~= "table" then
    return lines
  end

  local filepath = type(arguments.filepath) == "string" and arguments.filepath or "file"
  local old_path = filepath:sub(1, 1) == "/" and ("a" .. filepath) or ("a/" .. filepath)
  local new_path = filepath:sub(1, 1) == "/" and ("b" .. filepath) or ("b/" .. filepath)
  local patches = {}
  for _, edit in ipairs(edits) do
    if type(edit) == "table" and type(edit.oldText) == "string" and type(edit.newText) == "string" then
      -- Tool arguments contain changed snippets, not full file contents; label each snippet patch accordingly.
      local old_text = edit.oldText
      local new_text = edit.newText
      if old_text ~= "" and old_text:sub(-1) ~= "\n" then
        old_text = old_text .. "\n"
      end
      if new_text ~= "" and new_text:sub(-1) ~= "\n" then
        new_text = new_text .. "\n"
      end
      local diff = vim.text.diff(old_text, new_text, { result_type = "unified", ctxlen = 3 })
      if diff ~= "" then
        patches[#patches + 1] = diff
      end
    end
  end

  if #patches == 0 then
    return lines
  end

  local patch_lines = {}
  for _, patch in ipairs(patches) do
    patch_lines[#patch_lines + 1] = "--- " .. old_path
    patch_lines[#patch_lines + 1] = "+++ " .. new_path
    -- vim.diff supplies hunk ranges and +/-/context lines. Keep those, with file headers above.
    local diff_lines = split_lines(patch)
    if diff_lines[#diff_lines] == "" then
      table.remove(diff_lines)
    end
    vim.list_extend(patch_lines, diff_lines)
  end
  lines[#lines + 1] = ""
  vim.list_extend(lines, split_lines(format_codeblock(table.concat(patch_lines, "\n"), "diff")))
  return lines
end

---@type table<string, CodeCompanionToolresults.Renderer>
local registry = {
  run_command = render_run_command,
  file_search = render_file_search,
  grep_search = render_grep_search,
  read_file = render_read_file,
  get_diagnostics = render_get_diagnostics,
  insert_edit_into_file = render_insert_edit_into_file,
}

---Render one tool result using a tool-specific renderer or fallback behavior.
---@param reference CodeCompanionToolresults.ToolReference Tool reference.
---@param result CodeCompanionToolresults.ToolResult Current tool result.
---@param opts table Extension options.
---@param context CodeCompanionToolresults.RendererContext Renderer dependencies.
---@return string[] lines Rendered result split into buffer lines.
function M.render(reference, result, opts, context)
  -- Cleared content is a plugin-authored marker, not tool output; preserve it verbatim instead of applying the tool renderer.
  if result.cleared then
    return split_lines(result.content)
  end

  local renderer = registry[reference.name] or render_fallback
  local content = content_as_string(result.content)
  local normalized_content, metadata = context.normalize_result(content)
  local lines = renderer(reference, normalized_content, opts, context)

  -- Render cleaned content first, then prepend the adapter-owned notice once.
  -- Keeping this policy here prevents individual renderers from duplicating it.
  if metadata and metadata.truncation_notice then
    table.insert(lines, 1, "⚠ " .. metadata.truncation_notice)
  end

  return lines
end

-- Test seam for the pure formatter.
M._format_codeblock = format_codeblock

return M
