local M = {}

---@alias CodeCompanionToolresults.Renderer fun(reference: table, content: string, opts: table, context: table): string[]

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

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[]
local function render_fallback(reference, content, opts, context)
  return vim.split(content, "\n", { plain = true })
end

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
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

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
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

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
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

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
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

---@param reference table Tool reference.
---@param content string Normalized result content.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[]
local function render_get_diagnostics(reference, content, opts, context)
  return split_lines(content)
end

---@type table<string, CodeCompanionToolresults.Renderer>
local registry = {
  run_command = render_run_command,
  file_search = render_file_search,
  grep_search = render_grep_search,
  read_file = render_read_file,
  get_diagnostics = render_get_diagnostics,
}

---Render one tool result using a tool-specific renderer or fallback behavior.
---@param reference table Tool reference.
---@param result table Current tool result.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[] lines Rendered result split into buffer lines.
function M.render(reference, result, opts, context)
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
