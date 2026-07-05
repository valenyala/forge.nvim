# forge.nvim (fork)

This is a fork of [mmsaki/forge.nvim](https://github.com/mmsaki/forge.nvim) with additional commands (`:AnvilKill` and shortcuts for common `forge` subcommands).

A minimal Neovim plugin to run Foundry commands. Supports `Forge`, `Cast`, `Chisel`, and a persistent `Anvil` terminal.

<https://github.com/user-attachments/assets/98bcf9ac-99e9-44f3-8787-51467ef2a7a7>

## Features

* Opens Foundry commands in a **top-half split terminal**.
* Ephemeral buffers (`Forge`, `Cast`, `Chisel`) **wipe on close**.
* Persistent buffer (`Anvil`) **reuses the same split**.
* Automatically detects project root via `foundry.toml`.
* Optional `allow_standalone` config to run commands in folders without `foundry.toml`.

## Installation

```lua
-- ~/.config/nvim/lua/forge.lua
return {
  "valenyala/forge.nvim",
  config = function()
    require("forge").setup({
      allow_standalone = false, -- optional
    })
  end,
}
```

## Commands

| Command                   | Description                          | Buffer Persistence                 |
| -------------------------- | ------------------------------------- | ---------------------------------- |
| `:Forge <args...>`        | Run commands (e.g., `:Forge test`)   | Wipe on close                      |
| `:Cast <args...>`         | Run `cast` commands                   | Wipe on close                      |
| `:Chisel <args...>`       | Run `chisel` commands                 | Wipe on close                      |
| `:Anvil`                  | Start a persistent `anvil` terminal   | Persistent, reused if already open |
| `:AnvilKill`              | Kill the running `anvil` instance     | -                                   |
| `:ForgeBuild <args...>`   | Run `forge build`                     | Wipe on close                      |
| `:ForgeTest <args...>`    | Run `forge test`                      | Wipe on close                      |
| `:ForgeFmt <args...>`     | Run `forge fmt`                       | Wipe on close                      |
| `:ForgeClean <args...>`   | Run `forge clean`                     | Wipe on close                      |
| `:ForgeInstall <args...>` | Run `forge install`                   | Wipe on close                      |
| `:ForgeUpdate <args...>`  | Run `forge update`                    | Wipe on close                      |

## Configuration

Only one optional configuration:

```lua
require("forge").setup({
  allow_standalone = true, -- allows running commands outside of a foundry project
})
```

## Notes

* `Anvil` is persistent; running `:Anvil` again will **reuse the same buffer**.
