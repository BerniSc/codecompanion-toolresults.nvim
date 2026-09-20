# Architecture and Development Plan

## Goal

CodeCompanion hides tool output from the normal chat view. It used to display the results in folds, but this could clutter the UI and dampen the UX.
This extension provides an explicit way to inspect a current tool result without restoring all tool output to the chat buffer.

The extension is separate from CodeCompanion. CodeCompanion remains responsible for message history, context editing, compaction, and rendering.
This plugin stores references and presentation metadata only.

## Current interaction

1. CodeCompanion creates chat buffer.
2. The extension attaches callbacks to that chat.
3. `on_tool_output` updates the message reference and schedules reconciliation.
4. Scheduled reconciliation can see results that have finished before the whole tool batch is complete.
5. `on_checkpoint` reconciles the complete current message stack.
6. Tool messages are identified by `tools.call_id`.
7. The rendered chat buffer is scanned for current tool-label lines.
8. The user places the cursor on a tool-label line and presses `gT`.
9. The extension resolves the current result by `call_id`.
10. The result opens in a CodeCompanion-styled floating window.

## Data ownership

CodeCompanion owns message content.

The extension keeps per-chat state containing:

- chat buffer number
- chat object
- current message table reference
- tool references
- current rendered line positions

A tool reference contains metadata such as `call_id`, tool name, message ID, rendered line, and status.

Tool output is not copied into extension state. The adapter returns content transiently when `gT` requests it.

## Module boundaries

```text
lua/codecompanion/_extensions/toolresults/init.lua
  CodeCompanion extension entrypoint

lua/codecompanion_toolresults/init.lua
  Lifecycle wiring, state, keymap, orchestration

lua/codecompanion_toolresults/position.lua
  Rendered line detection and cursor lookup

### ADAPTERS - directly reference codecompanion core logic that is not necessary set in stone

lua/codecompanion_toolresults/adapters/messages.lua
  CodeCompanion message extraction and result lookup

lua/codecompanion_toolresults/adapters/ui.lua
  CodeCompanion UI integration and floating-window configuration

```

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

The position module reads the current buffer lines and matches references in message order. This supports repeated tool names as long as rendered order matches message order. Line numbers are recalculated instead of cached as identity. A full buffer scan is intentional: chat buffers are normally small, and it avoids stale positions after edits, new messages, or context management.

## UI integration

`adapters/ui.lua` reads `config.display.chat.floating_window` and merges tool-result-specific values before calling CodeCompanion's `utils.ui.create_float`.

This reuses configured width, height, relative position, and window options. The helper is an internal CodeCompanion API, not a documented public extension API. Coupling is isolated to one adapter module so future changes remain localized.

## Context management

The extension follows CodeCompanion's current message state:

- Current tool result: display current content.
- Result replaced by a placeholder: display current placeholder content.
- Result compacted away: report unavailable.
- Chat closed: discard extension state.

The extension does not create persistent tool-output history.

## Result float behavior

The extension maintains one managed result float per chat. `gT` creates it when needed; later displays update the existing float. If the user closes the float manually, the next display or float-local navigation detects the invalid window and recreates it.

The float title includes the ordered result position, such as `Tool Result: read_file [2/5]`. Float-local mappings are configurable:

- `]t`: next result
- `[t`: previous result
- `q`: close
- `<Esc>`: close
- `gT`: close the float and return to its originating tool-call line in the chat

Next and previous navigation wraps around the ordered references. It does not depend on chat-buffer line positions. `gT` uses the float's stored `call_id`, reconciles current positions, closes the float, and returns to the corresponding visible chat line. `<Esc>` remains a separate close-only mapping. Closing the parent CodeCompanion chat closes its managed result float.

The display module currently owns result rendering, float lifecycle, cursor placement, and float-local mappings. Stage 2 will separate rendering behind a small renderer interface while keeping lifecycle behavior unchanged.

## Current limitations

- Rendering detection depends on visible tool-label lines.
- Tool result message structure is CodeCompanion-version-sensitive.
- `on_tool_output` runs before CodeCompanion inserts the result. Scheduled reconciliation reduces this gap but is not an exact post-insert event.
- Exact per-tool post-insert observation would require a public CodeCompanion callback exposing the completed call ID or message.
- The floating-window helper is an internal CodeCompanion API, but mapped via adapter.
- Mouse hover is not implemented.
- Rendering remains inside `display.lua` until a renderer registry is introduced.
- `run_command` display formatting currently defaults to a `bash` command label, configurable via `run_command_language`; output uses a separate `text` block and other tools retain current string/non-string handling.

## Development stages

### Completed

- Extension skeleton and thin CodeCompanion bridge.
- Per-chat lifecycle tracking.
- Scheduled partial-result reconciliation without output storage.
- Adapter extraction and `call_id` result lookup.
- Rendered line tracking and configurable `gT` lookup.
- Configurable next/previous navigation with `gtn` and `gtp`.
- CodeCompanion-styled result float.

### Next: renderer separation

1. Move result rendering behind a small renderer interface while preserving current output.
2. Add fallback rendering for tools without a specific renderer.
3. Preserve `run_command` command-fence behavior and configurable `run_command_language`.
4. Add tool-specific renderers later for `read_file`, `grep_search`, `search_grep`, and `insert_edit_into_file`.
5. Investigate CodeCompanion's diff UI for edit tools.
6. Add optional tool-call parameter display.

### Later work

1. Test long output, repeated tools, multiple chats, cancellation, and unavailable results.
2. Add adapter tests for reference extraction and result lookup.
3. Add position tests for repeated tool names and missing rendered labels.
4. Refresh positions after relevant buffer changes, not only checkpoints.
5. Switch to better tool detection and extmark-based referencing for automatic tracking in the buffer.
6. Improve float sizing and window options.
7. Document supported CodeCompanion versions.
8. Add mouse or hover interaction if cursor behavior remains stable.

### Optional later work

- Add an experimental, explicitly confirmed recovery command for a tool call whose message exists but whose result is missing. Insert only a clearly marked synthetic placeholder, never fabricated output; preserve original state or provide rollback. Ensure deterministic detection and diagnostics first.
