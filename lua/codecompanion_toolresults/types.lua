---@meta

---@alias CodeCompanionToolresults.Status "available"|"invalidated"

---@class CodeCompanionToolresults.ToolReference
---@field call_id string? Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field command string? Original run_command input, when available.
---@field invalidated_line string? Display label for a rejected or cancelled tool.
---@field message_id number? CodeCompanion message identifier; secondary to call_id.
---@field message_index integer? Current message index; not stable across context management.
---@field line integer? Current rendered chat-buffer line; presentation state only.
---@field status CodeCompanionToolresults.Status

---@class CodeCompanionToolresults.ToolResult
---@field call_id string Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field message_id number? CodeCompanion message identifier; secondary to call_id.
---@field message_index integer? Current message index; not stable across context management.
---@field content any Current CodeCompanion result content, returned transiently.
---@field status "available"

---@class CodeCompanionToolresults.ToolCall
---@field call_id string Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field arguments any Current CodeCompanion call arguments, returned transiently.

---@class CodeCompanionToolresults.RendererContext
---@field remove_run_command_prefix fun(content: string, command: string): string
---@field normalize_result fun(content: string): string, table

---@alias CodeCompanionToolresults.Renderer fun(reference: CodeCompanionToolresults.ToolReference, content: string, opts: table, context: CodeCompanionToolresults.RendererContext): string[]

---@class CodeCompanionToolresults.FloatState
---@field bufnr integer
---@field winnr integer
---@field call_id string Tool-call identifier for returning to the chat location.
---@field view? "call"|"result"

---@class CodeCompanionToolresults.ChatState
---@field bufnr integer
---@field chat table CodeCompanion chat instance.
---@field references CodeCompanionToolresults.ToolReference[] Lightweight tool references.
---@field messages CodeCompanion.Chat.Messages Current CodeCompanion message table.
---@field tools table<string, CodeCompanionToolresults.ToolReference> References indexed by call_id.
---@field float CodeCompanionToolresults.FloatState?

return {}
