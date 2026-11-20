# Architecture and Development Plan

## Goal

CodeCompanion hides tool output from the normal chat view.
It used to display the results in folds, but this could clutter the UI and dampen the UX.
This extension provides an explicit way to inspect a current tool result without restoring all tool output to the chat buffer.

The extension is separate from CodeCompanion.
CodeCompanion remains responsible for message history, context editing, compaction, and rendering.
This plugin stores references and presentation metadata only.

## Current interaction

1. CodeCompanion creates chat buffer.
2. The extension attaches callbacks to that chat.
3. `on_tool_output` updates the tracked message reference and schedules reconciliation.
4. Scheduled reconciliation can see results that have finished before the whole tool batch is complete.
5. `on_checkpoint` reconciles the complete current message stack.
6. Tool messages are identified by `tools.call_id`.
7. The rendered chat buffer is scanned for current tool-label lines.
8. The user presses `gT`; configured `cursor.mode` selects a reference from the current cursor line and refreshed rendered positions (`exact` by default, or opt-in `nearest`, `above`, or `below`).
9. The extension resolves the current result by `call_id` and opens it in a CodeCompanion-styled floating window.
10. `K` optionally switches that float to the matching current tool-call arguments, also looked up by `call_id`.

## Mouse hover interaction

When enabled, the user can pause the pointer over a rendered tool label to preview its available result without opening the managed result float.
The buffer-local `<MouseMove>` mapping debounces movement and rechecks the pointer after scrolling.
The extension resolves the current result by `call_id` and passes it through the existing renderer.
The preview is transient and contains rendered result lines; its top border shows the tool name, and its bottom hint shows the full-result key and indicates when more lines are available.
The preview closes when the user enters Insert mode or moves the pointer outside the chat, but moving the pointer over the preview itself leaves it open.
A pending or unavailable result does not open a preview or show a notification.

The window and buffer lifecycle for these previews lives in `transient_preview.lua`.
`hover.lua` keeps mouse handling, debounce, and per-chat preview state, and delegates window creation to the shared module.
The overview's `K` preview reuses the same module with an anchor beside the selected overview row.

## Tool overview

`gO` opens one chronological list of the current chat's tool calls.
Each row shows the ordinal, an outcome glyph, the tool name, and a short argument summary.
The overview stores displayed `call_id` values only; outcome, summary, and arguments are looked up from current messages when rows are built.

Outcome is classified on demand by `adapters/messages.lua` (`tool_outcome`) from the current result for a `call_id`:

- `cancelled` and `rejected`: recognised CodeCompanion invalidation text.
- `failed`: the first result line starts with `Failed ` or `Failed:` or `Error:`. This is a heuristic and can misclassify a successful result that starts with the same text.
- `completed`: any other available result.
- `unavailable`: no current result for the `call_id`.

Rejection and cancellation take precedence over the failure marker.
Nothing about outcome is stored in extension state.

`lua/codecompanion_toolresults/overview_model.lua` is a pure module following MVC fashion.
It builds row text, argument summaries, and groups from plain data, without windows or chat access.
Summaries are display-only; a `run_command` command is shown flattened to one line and truncated by character.

Grouping modes are flat (`none`), outcome (`outcome`, in fixed order), and tool type (`tool`, in first-appearance order).
Group keys are plain identities, so folds and collapse state can be keyed by them rather than by parsing rendered text.
Agent-turn grouping is not implemented because current references do not retain call-batch metadata.

The overview window is implemented in `overview.lua`.
It takes plain items, a state table owned by the chat, a UI adapter, keymaps, and callbacks.
It never reads CodeCompanion messages.

- `gO` (`keymaps.chat.overview`) opens one managed overview per chat.
- `<CR>` opens the selected result in the managed result float; `q` and `<Esc>` in that float reopen the overview.
- `K` previews the selected result through `transient_preview.lua`, anchored beside the row. Its full-result key is `keymaps.overview.inspect`.
- `gT` closes the overview and returns to the tool-call line.
- `<M-g>` opens the grouping picker. The picker is `overview.group_picker` when set, otherwise `vim.ui.select`. It receives `{ grouping, label }` choices and an `on_choice` callback; a nil choice cancels.
- Folds are manual, one per group. Collapse state is keyed `grouping:group_key`, so a fold collapsed under one grouping does not affect another.
- Selection, grouping, and collapse state are restored on reopen within the same chat.

The overview builds its items once per open and does not refresh while open.
Refreshing is planned; see Later work.

## Data ownership

CodeCompanion owns message content.

The extension keeps per-chat state containing:

- chat buffer number
- chat object
- current message table reference
- tool references
- current rendered line positions
- transient hover preview handles and debounce timer, while preview is active
- overview handle, overview preview handle, and overview state (selected call ID, grouping, collapsed groups)

A tool reference contains metadata such as `call_id`, tool name, message ID, rendered line, and status.

Tool output and call arguments are not copied into extension state. Adapters return them transiently when displaying the corresponding view.

## Module boundaries

```text
lua/codecompanion/_extensions/toolresults/init.lua
  CodeCompanion extension entrypoint

lua/codecompanion_toolresults/init.lua
  Lifecycle wiring, state, keymap, orchestration

lua/codecompanion_toolresults/display.lua
  Result/call lookup handoff, managed float lifecycle, cursor placement, view toggle, and float-local mappings

lua/codecompanion_toolresults/redaction.lua
  Cancellable clear workflow, reason input, confirmation, and completion handling

lua/codecompanion_toolresults/navigation.lua
  Ordered next/previous result index navigation

lua/codecompanion_toolresults/position.lua
  Rendered line detection and cursor lookup

lua/codecompanion_toolresults/hover.lua
  Buffer-local mouse mapping, hover debounce, and per-chat hover preview state

lua/codecompanion_toolresults/transient_preview.lua
  Transient scrollable preview windows: anchor placement, title and footer hints, optional full-result key, and close

lua/codecompanion_toolresults/overview.lua
  Overview window: rows, folds, grouping, selection, overview-local mappings, and callbacks; no CodeCompanion message access

lua/codecompanion_toolresults/overview_model.lua
  Pure overview row, argument summary, and grouping model; no windows or chat access

lua/codecompanion_toolresults/diagnostics.lua
  On-demand runtime state and buffer diagnostic dump

lua/codecompanion_toolresults/renderers.lua
  Renderer registry, fallback rendering, and tool-specific result presentation

lua/codecompanion_toolresults/types.lua
  Shared state and tool-reference type annotations

### ADAPTERS - directly reference codecompanion core logic that is not necessary set in stone

lua/codecompanion_toolresults/adapters/messages.lua
  CodeCompanion message extraction, result lookup, on-demand overview outcome classification, and guarded tool-result mutation

lua/codecompanion_toolresults/adapters/ui.lua
  CodeCompanion UI integration and floating-window configuration

```

The `init.lua` orchestrator resolves a hovered label to its current result by `call_id`, invokes the renderer, and passes the resulting lines to `hover.lua`.
The hover module owns mouse handling and transient preview windows; it does not retain tool output as plugin history.
Renderers only convert result data to display lines and do not manage hover state or floats.
The old `insert_edit_into_file` API takes `filepath` and an `edits` array of `oldText`/`newText` pairs, each with a `replaceAll` flag; it supports multiple edits per call and flexible matching.
The v20 `edit_file` API takes one `old_string`/`new_string` replacement per call, with `filepath` and `replace_all`, and uses exact-string matching with line-ending and curly-quote normalisation.
Both tools review full-file changes, but stored tool arguments do not include the review diff; renderers show patches derived from arguments instead.
The v20 `create_file` renderer displays supplied `content` as an added-file patch.
All renderers resolve arguments transiently by `call_id`; when unavailable, they show only the result summary.

The `_extensions` module stays thin. The plugin namespace contains feature logic. CodeCompanion-specific assumptions stay under `adapters/` where possible.

## Identity and positions

`call_id` is the primary tool identity because the tool-call message and tool-result message share it.

Message `_meta.id` is secondary metadata (fallback not yet automatical).
Message indexes are not stable because tool messages may not have an index and context management can change the message stack.

Rendered line numbers are presentation state only. They must be recalculated after rendering changes. They are never used as tool identity.

Current line detection matches rendered labels such as:

```text
run_command: date
run_command: ls
```

The position module reads the current buffer lines and matches references in message order.
This supports repeated tool names as long as rendered order matches message order.
Line numbers are recalculated instead of cached as identity.
A full buffer scan is intentional: chat buffers are normally small, and it avoids stale positions after edits, new messages, or context management.

After refreshing positions, `cursor.mode` resolves `gT` selection without changing label detection or tool identity.
`exact` requires a label on the cursor line and is the default.
`nearest` selects the closest visible label, preferring the one above on equal distance.
`above` and `below` select the closest label strictly in that direction.
Directional modes do not wrap; when no candidate exists, the extension reports a mode-specific message.
Selection remains transient presentation behavior: results are still resolved from current CodeCompanion messages using `call_id`.

## UI integration

`adapters/ui.lua` reads `config.display.chat.floating_window` and merges tool-result-specific values before calling CodeCompanion's `utils.ui.create_float`.

This reuses configured width, height, relative position, and window options.
The helper is an internal CodeCompanion API, not a documented public extension API.
Coupling is isolated to one adapter module so future changes remain localized.

## Context management

The extension follows CodeCompanion's current message state:

- Current tool result: display current content.
- Result replaced by a placeholder: display current placeholder content.
- Result compacted away: report unavailable.
- Chat closed: discard extension state.

The extension does not create persistent tool-output history.

Result-view titles show selected tool message's existing `_meta.estimated_tokens` as an approximate token count, and retain that estimate in the title while the float shows call arguments.
Each display and refresh resolves current message by `call_id`; no estimate or output copy is cached.
Scheduled post-tool reconciliation and `on_checkpoint` refresh open float, including after CodeCompanion context editing.
Missing estimate metadata appears as unavailable.
This is CodeCompanion's lightweight heuristic, not an exact provider count.

## Manual tool-result context curation

The result float supports clearing a selected tool result from future local chat context.
Intended use is context curation after seeing an irrelevant or oversized result—for example, a broad grep returns Python matches before the user realises the task concerns C++.

The float's `r` action clears result content from future local context.
Reason presets cover irrelevant results, wrong language or path, redundancy, and excessive output.
Optional custom explanations are limited to 160 UTF-8 bytes and normalised to one line.
`Clear without reason` is available.
Each `vim.ui.select`/`vim.ui.input` prompt states `<Esc>` cancellation; Cancel or empty custom input is no-op.
Final confirmation is required.
The original output is not saved for undo.

After confirmation, plugin resolves one tool result by `call_id` and replaces only its content with `User cleared this tool result.` plus optional reason.
Tool-call/result pairing and message identity remain intact.
The messages adapter loads CodeCompanion's token utility and refreshes `_meta.estimated_tokens` with its heuristic calculator when available; the redaction workflow has no token-estimation dependency.
If loading or calculation fails, stale estimate metadata is removed.
No savings estimate is displayed.
The replacement is written to the current tool message, but session save/restore behaviour has not been integration-tested.
CodeCompanion's current session serialiser preserves only `_meta.tag`, so the plugin's cleared-state flag is lost on restore and the action may be offered again.
TODO: Ask Oli Morris for a supported way to persist namespaced plugin metadata; do not overload unrelated message fields as a workaround.

The mutation boundary is the unique current tool message identified by `call_id`.
Use rendered chat-buffer text only to locate visible tool-call lines.
Identify and mutate tool results in CodeCompanion's current messages by `call_id`, not by matching rendered text.
CodeCompanion may render `for_user` content differently from stored tool content, and assistant messages may repeat output without a reliable per-result range.
Clearing changes only the selected tool message for future local requests; other transcript copies remain untouched.
It does not change past requests or guarantee deletion from provider-managed context, so it is context curation rather than transcript or security redaction.
The current request or tool batch blocks clearing.
Tests cover exact call-ID targeting, ambiguity and missing results, cancellation and confirmation, unchanged rendered transcript, reason normalisation, metadata refresh, and preserved message identity.
Manual integration verification is still needed for the next request payload, session save/restore, and automatic context editing or compaction.

Queued clearing during active orchestration could make this feature useful mid-run, but is not currently supported.
Investigate whether a queued mutation can safely apply at a defined orchestration boundary without changing messages consumed by the active request or tool batch.
Check whether CodeCompanion's `btw` feature offers a safe interaction point, and verify message-consumption timing before designing or documenting a queueing contract.

## Result float behavior

The extension maintains one managed result float per chat.
`gT` creates it when needed; later displays update the existing float.
If the user closes the float manually, the next display or float-local navigation detects the invalid window and recreates it.

The float title includes current view and ordered position, such as `Tool Result: read_file [2/5]` or `Tool Call: read_file [2/5]`.
`K` toggles between the current result and its matching call arguments; `<Tab>` and `<S-Tab>` preserve the selected view as the user browses calls/results.
Result view is the initial default, then the last selected view is retained per chat after the float closes and reopens.
Closing the chat discards this presentation preference.
Arguments are looked up by `call_id` from current messages only when requested and are not retained in extension state.
Structured arguments render as fenced, sorted JSON; `run_command` input renders in a neutral `text` fence to mark multiline command boundaries without implying an execution shell.
Any additional `run_command` arguments appear under `Other arguments` as fenced JSON; that section stays omitted when command is only input.
The renderer grows fence length if argument content contains backticks.
Float-local mappings are configurable under `keymaps.float`:

- `K`: toggle between call and result
- `<Tab>`: next result (or next call while call view selected)
- `<S-Tab>`: previous result (or previous call while call view selected)
- `q`: close
- `<Esc>`: close
- `gT`: close the float and return to its originating tool-call line in the chat

The chat mappings live under `keymaps.chat`. Set any mapping to `false` to disable it. `float.show_keymaps` controls whether float mappings appear in the winbar.

Next and previous navigation wraps around the ordered references.
It does not depend on chat-buffer line positions.
`gT` uses the float's stored `call_id`, reconciles current positions, closes the float, and returns to the corresponding visible chat line.
`<Esc>` remains a separate close-only mapping.
Closing the parent CodeCompanion chat closes its managed result float.

The display module owns transient call/result lookup handoff, float lifecycle, cursor placement, view selection, and float-local mappings.
The renderer module owns result and call-to-lines conversion only.
Renderers do not manage floats, keymaps, navigation, chat state, or CodeCompanion callbacks.


## Current limitations

- Rendering detection depends on visible tool-label lines.
- `nearest` cursor selection can choose an unintended result if cursor moves far from the intended tool label; exact selection remains the default.
- Tool result message structure is CodeCompanion-version-sensitive.
- `on_tool_output` runs before CodeCompanion inserts the result. Scheduled reconciliation reduces this gap but is not an exact post-insert event.
- Exact per-tool post-insert observation would require a public CodeCompanion callback exposing the completed call ID or message.
- The floating-window helper is an internal CodeCompanion API, but mapped via adapter.
- Mouse hover requires Neovim's global `mousemoveevent`; the plugin does not enable or change that option.
- Mouse-event delivery, focus transitions, and preview placement have not been manually verified across terminal UIs.
- `run_command` display formatting currently defaults to a `bash` command label, configurable via `run_command_language`. Still requires some unintuitive user interaction.
- The tool overview reads messages only when it opens and does not refresh while open.
- The overview's outcome glyph highlight shifts from index 100 onwards, because the glyph column is a fixed byte offset.

## Development stages

### Completed

- Extension skeleton and thin CodeCompanion bridge.
- Per-chat lifecycle tracking.
- Scheduled partial-result reconciliation without output storage.
- Adapter extraction and `call_id` result lookup.
- Rendered line tracking and configurable `gT` lookup, including opt-in exact/nearest/above/below cursor selection.
- Configurable next/previous navigation with `gtn` and `gtp`.
- CodeCompanion-styled result float.
- Renderer registry with fallback rendering and dedicated `run_command` rendering.
- Tool-specific renderers for common file, search, command, diagnostic, and edit results, including legacy `insert_edit_into_file` and v20 `edit_file`/`create_file`.
- On-demand tool-call argument view with `K`, resolved by `call_id` and retained across navigation.
- Runtime diagnostic dumps are available through `codecompanion.extensions.toolresults.dump()` and include current messages, references, tool indexes, and rendered chat-buffer content per tracked chat.
- Tool overview on `gO`, with outcome classification, grouping, manual folds, `K` preview, and a configurable grouping picker.

### Later work

1. Test long output, repeated tools, multiple chats, cancellation, and unavailable results.
2. Add adapter tests for reference extraction and result lookup.
3. Add position tests for repeated tool names and missing rendered labels.
4. Refresh positions after relevant buffer changes, not only checkpoints.
5. Switch to better tool detection and extmark-based referencing for automatic tracking in the buffer.
6. Improve float sizing and window options.
7. Harden the opt-in mouse hover preview: verify behaviour across terminal UIs, scrolling, narrow windows, mouse focus transitions, and configured keymaps.
8. Make the tests more robust. Current hover lifecycle tests replace `vim.fn`, `vim.uv`, and `vim.keymap` functions by hand and restore them manually; a shared stub helper with guaranteed restoration would reduce the risk of leaked state. The `transient_preview` open-failure test only checks for a `nil` result and does not verify that no scratch buffer leaked.
9. Refresh an open tool overview when results arrive or context management changes messages. Planned design: `overview.refresh(handle, items)` keeps selection, grouping, and folds, and closes the overview preview when data changes; `init.lua` calls it after scheduled reconciliation and checkpoints.
10. Address recovery of broken sessions, for example a tool call whose result was never written or a session restored with plugin metadata missing. Design and detection rules are not decided.
11. Show the hovered result in the mouse preview for tool outputs as well, not only for tool-call labels. Scope and mouse-event behaviour still need design.
12. Show pending tool calls through this plugin, so calls still waiting for a result appear in the overview and can be inspected as pending. Current overview lists them only as `unavailable`.
13. Improve stability in general. Cover error paths, stale windows and buffers, and invalid chat state with tests and diagnostics before adding new features.

### Optional later work

- Add an experimental, explicitly confirmed recovery command for a tool call whose message exists but whose result is missing. Insert only a clearly marked synthetic placeholder, never fabricated output; preserve original state or provide rollback. Ensure deterministic detection and diagnostics first.
