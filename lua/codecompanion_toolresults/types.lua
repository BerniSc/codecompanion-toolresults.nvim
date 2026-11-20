---@meta

---Availability state for a tool-result reference.
---@alias CodeCompanionToolresults.Status "available"|"invalidated"

---Display classification for a tool call in overview.
---@alias CodeCompanionToolresults.ToolOutcome
---| "completed"
---| "failed"
---| "rejected"
---| "cancelled"
---| "unavailable"

---@class CodeCompanionToolresults.ToolReference
---@field call_id string? Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field command string? Original run_command input, when available.
---@field invalidated_line string? Display label for a rejected or cancelled tool.
---@field message_id number? CodeCompanion message identifier; secondary to call_id.
---@field message_index integer? Current message index; not stable across context management.
---@field line integer? Current rendered chat-buffer line; presentation state only.
---@field status CodeCompanionToolresults.Status Whether the tool result is available or was invalidated by rejection/cancellation.

---@class CodeCompanionToolresults.ToolResult
---@field call_id string Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field message_id number? CodeCompanion message identifier; secondary to call_id.
---@field message_index integer? Current message index; not stable across context management.
---@field content any Current CodeCompanion result content, returned transiently.
---@field status "available" Kept to mirror ToolReference.status.
---@field estimated_tokens number? CodeCompanion's approximate per-message token estimate.
---@field cleared boolean? Whether this plugin marked the result as cleared in current session.

---@class CodeCompanionToolresults.ToolCall
---@field call_id string Stable CodeCompanion tool-call identifier.
---@field name string? Tool name.
---@field arguments any Current CodeCompanion call arguments, returned transiently.

-- TODO: Give other ad-hoc test dependency tables similarly focused types when their contracts need clarification.

---@class CodeCompanionToolresults.ToolResultClearOperation
---@field name string Display name for confirmation prompt.
---@field commit fun(content: string): boolean, CodeCompanion.Chat.Messages?, string? Commit the clear; return success, current raw messages, or error.

---@class CodeCompanionToolresults.RedactionAdapter
---@field prepare_tool_result_clear fun(chat: table, call_id: string): CodeCompanionToolresults.ToolResultClearOperation?, string? Prepare a validated clear operation against the live chat.

---@class CodeCompanionToolresults.RedactionDeps
---@field select fun(items: string[], opts: table, callback: fun(choice: string?))? Override vim.ui.select for the clear workflow.
---@field input fun(opts: table, callback: fun(value: string?))? Override vim.ui.input for the custom reason prompt.
---@field notify fun(message: string, level: integer)? Override vim.notify for clear-workflow feedback.

---@class CodeCompanionToolresults.RendererContext
---@field remove_run_command_prefix fun(content: string, command: string): string Strip the duplicated "command" line CodeCompanion prepends to run_command output.
---@field normalize_result fun(content: any): string, table Clean tool result content for display; the table holds metadata such as "truncation_notice".
---@field find_tool_call? fun(call_id: string): CodeCompanionToolresults.ToolCall? Resolve current tool-call arguments by call ID.

---@alias CodeCompanionToolresults.Renderer fun(reference: CodeCompanionToolresults.ToolReference, content: string, opts: table, context: CodeCompanionToolresults.RendererContext): string[]

---@class CodeCompanionToolresults.FloatState
---@field bufnr integer
---@field winnr integer
---@field call_id string Tool-call identifier for returning to the chat location.
---@field view? "call"|"result"
---@field return_to_overview? boolean Whether closing the float reopens the originating overview.

---Screen position in editor-grid coordinates, used to place transient previews.
---@class CodeCompanionToolresults.Anchor
---@field screenrow integer
---@field screencol integer

---Mouse position from "vim.fn.getmousepos()". Aliased to the builtin return type so callers pass it through unchanged.
---Fields used: "screenrow", "screencol", "winid", and "line" (1-based buffer line under the pointer).
---@alias CodeCompanionToolresults.MousePosition vim.fn.getmousepos.ret

---Last chat line and window under the hover pointer.
---@class CodeCompanionToolresults.HoverTarget
---@field line integer
---@field winid integer

---@class CodeCompanionToolresults.HoverOptions
---@field enabled boolean
---@field delay integer Milliseconds the pointer must rest before a preview opens.
---@field max_lines integer
---@field max_width integer

---@class CodeCompanionToolresults.PreviewOptions
---@field max_lines integer Maximum body lines before scrolling.
---@field max_width integer Maximum preview width in columns.
---@field title? string Border title; truncated to fit.
---@field keybind string|false|nil Key that runs "on_view_more"; false or nil disables the key and its hint.
---@field on_view_more? fun() Callback for "keybind".
---@field focusable? boolean Whether the preview window can receive focus.
---@field zindex? integer Base stacking order; footer uses the next value.

---Windows and buffers owned by one transient preview. Footer fields exist only when a hint footer is shown.
---@class CodeCompanionToolresults.PreviewHandle
---@field bufnr integer
---@field winnr integer
---@field footer_bufnr? integer
---@field footer_winnr? integer

---Subset of CodeCompanion UI helpers used by the managed float and overview.
---@class CodeCompanionToolresults.UiAdapter
---@field create_float fun(lines: string[], opts?: table): integer, integer
---@field update_float fun(bufnr: integer, winnr: integer, lines: string[], opts?: table): boolean
---@field close_float fun(bufnr?: integer, winnr?: integer)

---@alias CodeCompanionToolresults.OverviewGrouping "none"|"outcome"|"tool"

---@class CodeCompanionToolresults.OverviewItem
---@field call_id string Tool-call identifier; the only identity stored for selection.
---@field index integer Ordinal position in the chat.
---@field name? string Tool name.
---@field outcome CodeCompanionToolresults.ToolOutcome Outcome from the current tool result.
---@field summary string Display-only argument summary.

---Build a display summary from a run_command input or decoded tool arguments.
---@alias CodeCompanionToolresults.OverviewSummariser fun(command: string?, arguments: table?): string

---A display group of overview items, as returned by "overview_model.group".
---@class CodeCompanionToolresults.OverviewGroup
---@field key string Plain group identity used for folds.
---@field label? string Header label; nil when the grouping has no headers.
---@field items CodeCompanionToolresults.OverviewItem[]

---@alias CodeCompanionToolresults.GroupPicker
---| fun(choices: { grouping: CodeCompanionToolresults.OverviewGrouping, label: string }[], on_choice: fun(grouping: CodeCompanionToolresults.OverviewGrouping?))

---@class CodeCompanionToolresults.OverviewState
---@field grouping? CodeCompanionToolresults.OverviewGrouping Current grouping; defaults to "none".
---@field selected_call_id? string Last selected call; restored on reopen when still present.
---@field collapsed? table<string, boolean> Collapsed group keys, scoped by grouping.

---@class CodeCompanionToolresults.OverviewCallbacks
---@field inspect fun(call_id: string) Inspect selected tool result.
---@field preview fun(call_id: string, anchor: CodeCompanionToolresults.Anchor) Preview selected tool result.
---@field close_preview fun() Close active overview preview.
---@field return_to_chat fun(call_id: string) Return to selected tool call in chat.

---@class CodeCompanionToolresults.OverviewContext
---@field items CodeCompanionToolresults.OverviewItem[] Calls in message order.
---@field state CodeCompanionToolresults.OverviewState Overview presentation state owned by the caller's chat state.
---@field ui CodeCompanionToolresults.UiAdapter
---@field keymaps table<string, string|false> Overview mappings keyed by action; "false" disables an action.
---@field filetype string Filetype for the overview buffer.
---@field group_picker? CodeCompanionToolresults.GroupPicker Picker for grouping choices; defaults to "vim.ui.select".
---@field callbacks CodeCompanionToolresults.OverviewCallbacks

---@class CodeCompanionToolresults.OverviewLayoutRow
---@field outcome CodeCompanionToolresults.ToolOutcome
---@field name string Tool name used for highlighting; "unknown" when absent.

---@class CodeCompanionToolresults.OverviewLayoutHeader
---@field line integer 1-based buffer line of the group header.
---@field key string Group identity.

---Rendered overview lines with lookups from buffer line to call or row.
---@class CodeCompanionToolresults.OverviewLayout
---@field lines string[]
---@field call_ids table<integer, string> Call ID by 1-based buffer line.
---@field rows table<integer, CodeCompanionToolresults.OverviewLayoutRow> Row styling by 1-based buffer line.
---@field headers CodeCompanionToolresults.OverviewLayoutHeader[]

---Open overview returned by "overview.open". Holds window handles and layout, not chat data.
---@class CodeCompanionToolresults.OverviewHandle
---@field bufnr integer
---@field winnr integer
---@field context CodeCompanionToolresults.OverviewContext
---@field grouping CodeCompanionToolresults.OverviewGrouping Grouping currently shown in this float. Folds and rows follow it.
---@field layout CodeCompanionToolresults.OverviewLayout
---@field closed? boolean

---@class CodeCompanionToolresults.ChatState
---@field bufnr integer
---@field chat table CodeCompanion chat instance.
---@field references CodeCompanionToolresults.ToolReference[] Lightweight tool references.
---@field messages CodeCompanion.Chat.Messages Current CodeCompanion message table.
---@field tools table<string, CodeCompanionToolresults.ToolReference> References indexed by call_id.
---@field float CodeCompanionToolresults.FloatState?
---@field view? "call"|"result" Last successfully displayed view; defaults to result and survives float closure for this chat.
---@field hover_preview? CodeCompanionToolresults.PreviewHandle Transient hover preview windows.
---@field hover_timer? any Transient mouse-hover debounce timer.
---@field hover_mouse? CodeCompanionToolresults.HoverTarget Last chat line and window under the pointer.
---@field hovered_call_id? string Tool selected by the active hover preview.
---@field overview? CodeCompanionToolresults.OverviewHandle Open overview.
---@field overview_preview? CodeCompanionToolresults.PreviewHandle Transient preview opened from the overview.
---@field overview_state CodeCompanionToolresults.OverviewState Grouping, selection, and folds kept across overview opens.

return {}
