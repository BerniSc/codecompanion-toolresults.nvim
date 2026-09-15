# CodeCompanion Toolresults

CodeCompanion extension for viewing tool results on demand, without adding full tool output to the chat buffer.

Based on the discussion in [CodeCompanion discussion #3360](https://github.com/olimorris/codecompanion.nvim/discussions/3360).

## Status

Early development. Current implementation supports:

- CodeCompanion extension loading.
- Per-chat tool-call observation.
- Partial lookup in batched calls.
- Cursor-based lookup with `gT`.
- Configurable cursor navigation with `gtn` and `gtp`.
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
      next_keymap = "gtn",
      previous_keymap = "gtp",
    },
  },
},
````

`gT` displays result under cursor. `gtn` moves to next rendered tool-call line; `gtp` moves to previous. Set either navigation option to `false` to disable it.

## Usage

1. Open a CodeCompanion chat.
2. Allow one or more tools to run.
3. Move the cursor to a rendered tool-call line, such as `run_command: date`.
4. Press `gT` to display its result. Use `gtn` to move to the next tool-call line or `gtp` to move to the previous one.

The current result opens in a floating window. The result is looked up from CodeCompanion's current message stack when requested; this extension does not maintain a second output history.
This means it will match CodeCompanions context management.

For runtime issues, call `codecompanion.extensions.toolresults.dump()` from inside Neovim. It writes a focused, on-demand diagnostic snapshot to a unique temporary directory and returns the directory path. Each tracked chat gets separate `messages.json`, `references.json`, `tools.json`, `buffer-metadata.json`, and human-readable `buffer.txt` files. Message content may contain sensitive data; inspect the files before sharing them.
For purposes of copying:
`
:lua print(require("codecompanion").extensions.toolresults.dump())
`

## Options

| Option | Default | Description |
| --- | --- | --- |
| `keymap` | `"gT"` | Chat-buffer keymap for displaying a result. Set to `false` to disable. |
| `next_keymap` | `"gtn"` | Chat-buffer keymap for moving to next tool result. Set to `false` to disable. |
| `previous_keymap` | `"gtp"` | Chat-buffer keymap for moving to previous tool result. Set to `false` to disable. |
| `run_command_language` | `"bash"` | Language label for displayed `run_command` commands. Set to another shell or `false`; default is only a display label, not a shell assumption. |
| `debug` | `false` | Enable lifecycle and reference logging. |
| `debug_buffer` | `false` | Log rendered chat-buffer lines and calculated positions. |

The diagnostic dump does not require `debug` or `debug_buffer` to be enabled.

## Behavior after context management

CodeCompanion may edit or compact older tool results. If a result is still present, `gT` displays its current content. If CodeCompanion has replaced or removed it, the extension reports that the result is unavailable.

The extension does not preserve removed output.

## Architecture

See [`docs/concept.md`](docs/concept.md) for detailed design, data flow, boundaries, and planned work.

## Compatibility

The extension uses CodeCompanion's chat callbacks and message structure. It also uses the internal `codecompanion.utils.ui.create_float` helper to match CodeCompanion's floating-window behavior. That dependency is isolated in `lua/codecompanion_toolresults/adapters/ui.lua`.

CodeCompanion changes may require adapter updates.

`run_command` formatting uses a local display-only code-fence formatter and does not assume a shell for execution.

## Testing

Tests use `mini.test` from `mini.nvim` as a development-only dependency. `make test` fetches it automatically into ignored `deps/mini.nvim`; it is not a runtime dependency.

Run the full test suite:

```sh
make test
```

Show detailed test groups:

```sh
make test VERBOSE=1
```

Run one test file:

```sh
make test_file FILE=tests/test_messages.lua
```

Message adapter tests use both a more realistic CodeCompanion message-batch fixture and smaller atomic fixtures. The full fixture checks compatibility with real message structure; atomic fixtures keep individual behaviors easy to diagnose.

