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

## Data ownership

CodeCompanion owns message content.

The extension keeps per-chat state containing:

- chat buffer number
- chat object
- current message table reference
- tool references
- current rendered line positions
- transient hover preview handles and debounce timer, while preview is active

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
  Buffer-local mouse mapping, hover debounce, transient preview windows, and cleanup

lua/codecompanion_toolresults/diagnostics.lua
  On-demand runtime state and buffer diagnostic dump

lua/codecompanion_toolresults/renderers.lua
  Renderer registry, fallback rendering, and tool-specific result presentation

lua/codecompanion_toolresults/types.lua
  Shared state and tool-reference type annotations

### ADAPTERS - directly reference codecompanion core logic that is not necessary set in stone

lua/codecompanion_toolresults/adapters/messages.lua
  CodeCompanion message extraction, result lookup, and guarded tool-result mutation

lua/codecompanion_toolresults/adapters/ui.lua
  CodeCompanion UI integration and floating-window configuration

```

The `init.lua` orchestrator resolves a hovered label to its current result by `call_id`, invokes the renderer, and passes the resulting lines to `hover.lua`.
The hover module owns mouse handling and transient preview windows; it does not retain tool output as plugin history.
Renderers only convert result data to display lines and do not manage hover state or floats.

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
- On-demand tool-call argument view with `K`, resolved by `call_id` and retained across navigation.
- Runtime diagnostic dumps are available through `codecompanion.extensions.toolresults.dump()` and include current messages, references, tool indexes, and rendered chat-buffer content per tracked chat.


### Next: tool-specific renderers

1. Add renderers for `read_file`, `grep_search`, `search_grep`, and `insert_edit_into_file`.
2. Preserve current output while adding each renderer.
3. Investigate CodeCompanion's diff UI for edit tools.

### Later work

1. Test long output, repeated tools, multiple chats, cancellation, and unavailable results.
2. Add adapter tests for reference extraction and result lookup.
3. Add position tests for repeated tool names and missing rendered labels.
4. Refresh positions after relevant buffer changes, not only checkpoints.
5. Switch to better tool detection and extmark-based referencing for automatic tracking in the buffer.
6. Improve float sizing and window options.
7. Document supported CodeCompanion versions.
8. Harden the opt-in mouse hover preview: verify behaviour across terminal UIs, scrolling, narrow windows, mouse focus transitions, and configured keymaps.

### Optional later work

- Add an experimental, explicitly confirmed recovery command for a tool call whose message exists but whose result is missing. Insert only a clearly marked synthetic placeholder, never fabricated output; preserve original state or provide rollback. Ensure deterministic detection and diagnostics first.
