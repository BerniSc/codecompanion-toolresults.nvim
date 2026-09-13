# CodeCompanion Toolresults

CodeCompanion extension for viewing tool results on demand, without adding full tool output to the chat buffer.

Based on the discussion in [CodeCompanion discussion #3360](https://github.com/olimorris/codecompanion.nvim/discussions/3360).

## Status

Early development. Current implementation supports:

- CodeCompanion extension loading.
- Per-chat tool-call observation.
- Partial lookup in batched calls.
- Cursor-based lookup with `gT`.
- Result display in a floating window.
- Inheriting CodeCompanions floating-window dimensions and options.

## Installation

Install with your Neovim plugin manager alongside CodeCompanion. Configure the extension inside `require("codecompanion").setup`:

````lua
extensions = {
  toolresults = {
    enabled = true,
    opts = {
      keymap = "gT",
    },
  },
},
````

`gT` is enabled by default. Disable it with `keymap = false`.

## Usage

1. Open a CodeCompanion chat.
2. Allow one or more tools to run.
3. Move the cursor to a rendered tool-call line, such as `run_command: date`.
4. Press `gT`.

The current result opens in a floating window. The result is looked up from CodeCompanion's current message stack when requested; this extension does not maintain a second output history.
This means it will match CodeCompanions context management.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `keymap` | `"gT"` | Chat-buffer keymap for displaying a result. Set to `false` to disable. |
| `debug` | `false` | Enable lifecycle and reference logging. |
| `debug_buffer` | `false` | Log rendered chat-buffer lines and calculated positions. |

## Behavior after context management

CodeCompanion may edit or compact older tool results. If a result is still present, `gT` displays its current content. If CodeCompanion has replaced or removed it, the extension reports that the result is unavailable.

The extension does not preserve removed output.

## Architecture

See [`docs/concept.md`](docs/concept.md) for detailed design, data flow, boundaries, and planned work.

## Compatibility

The extension uses CodeCompanion's chat callbacks and message structure. It also uses the internal `codecompanion.utils.ui.create_float` helper to match CodeCompanion's floating-window behavior. That dependency is isolated in `lua/codecompanion_toolresults/adapters/ui.lua`.

CodeCompanion changes may require adapter updates.

