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

## Current limitations

- Rendering detection depends on visible tool-label lines.
- Tool result message structure is CodeCompanion-version-sensitive.
- `on_tool_output` runs before CodeCompanion inserts the result. Scheduled reconciliation reduces this gap but is not an exact post-insert event.
- Exact per-tool post-insert observation would require a public CodeCompanion callback exposing the completed call ID or message.
- The floating-window helper is an internal CodeCompanion API, but mapped via adapter.
- Mouse hover is not implemented.
- Result window lifecycle refinement is pending.
- Result content is currently displayed as plain buffer lines.

## Development stages

### Completed

- Extension skeleton and thin CodeCompanion bridge.
- Per-chat lifecycle tracking.
- Scheduled partial-result reconciliation without output storage.
- Adapter extraction and `call_id` result lookup.
- Rendered line tracking and configurable `gT` lookup.
- Configurable next/previous navigation with `gtn` and `gtp`.
- CodeCompanion-styled result float.

### Next

1. Test long output, repeated tools, multiple chats, cancellation, and unavailable results.
2. Improve UI of resultdisplay.
3. Add option to display params for the toolcall.
4. Add adapter tests for reference extraction and result lookup.
5. Add position tests for repeated tool names and missing rendered labels.
6. Refresh positions after relevant buffer changes, not only checkpoints.
7. Improve float lifecycle, including replacing or closing an existing result window.
8. Add `<Esc>` close behavior and configurable UI options.
9. Add native UI fallback if the CodeCompanion helper changes or disappears.
10. Document supported CodeCompanion versions.
11. Add mouse or hover interaction if cursor behavior remains stable.
