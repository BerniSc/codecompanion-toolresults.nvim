local M = {}

---@alias CodeCompanionToolresults.Renderer fun(reference: table, result: table, opts: table, context: table): string[]

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
  local suffix = content:sub(-1) == "\n" and "" or "\n"
  return string.format("%s%s\n%s%s%s", fence, language, content, suffix, fence)
end

---@param result table Current tool result.
---@return string
local function content_as_string(result)
  if type(result.content) == "string" then
    return result.content
  end

  return vim.inspect(result.content)
end

---@param reference table Tool reference.
---@param result table Current tool result.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[]
local function render_fallback(reference, result, opts, context)
  return vim.split(content_as_string(result), "\n", { plain = true })
end

---@param reference table Tool reference.
---@param result table Current tool result.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[]
local function render_run_command(reference, result, opts, context)
  local content = content_as_string(result)
  local language = opts.run_command_language

  if type(reference.command) ~= "string" or not language then
    return vim.split(content, "\n", { plain = true })
  end

  local output = context.remove_run_command_prefix(content, reference.command)
  local rendered = string.format("%s\n%s", format_codeblock(reference.command, language), output)
  return vim.split(rendered, "\n", { plain = true })
end

---@type table<string, CodeCompanionToolresults.Renderer>
local registry = {
  run_command = render_run_command,
}

---Render one tool result using a tool-specific renderer or fallback behavior.
---@param reference table Tool reference.
---@param result table Current tool result.
---@param opts table Extension options.
---@param context table Renderer dependencies.
---@return string[] lines Rendered result split into buffer lines.
function M.render(reference, result, opts, context)
  local renderer = registry[reference.name] or render_fallback
  return renderer(reference, result, opts, context)
end

-- Test seam for the pure formatter.
M._format_codeblock = format_codeblock

return M
