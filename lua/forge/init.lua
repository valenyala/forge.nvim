--- forge.nvim - Minimal Neovim plugin to run Foundry commands in a split terminal
-- Supports Forge, Cast, Chisel, and persistent Anvil terminal.
-- Ephemeral buffers (Forge/Cast/Chisel) wipe on close; Anvil is persistent.
local M = {}

--- Plugin configuration table
-- @field allow_standalone boolean Whether to allow running commands in folders without foundry.toml
M.config = {
  allow_standalone = false,
}

--- Stores the buffer number of the persistent Anvil terminal
-- @type integer|nil
M.anvil_buf = nil

--- Find the project root by searching for `foundry.toml` upwards from current directory
-- @return string|nil The path to the directory containing foundry.toml, or nil if not found
local function find_root()
  local found = vim.fs.find("foundry.toml", { upward = true })[1]
  if not found then return nil end
  return vim.fs.dirname(found)
end

--- Open a terminal split for running a command
-- @param args table List of strings: the command and its arguments
-- @param persistent boolean If true, reuse the same buffer (for Anvil)
-- @param name string Name of the buffer to display in the split
local function open_terminal(args, persistent, name)
  local root = find_root()
  if not root then
    if M.config.allow_standalone then
      root = vim.loop.cwd()
    else
      vim.notify("No foundry.toml found", vim.log.levels.WARN)
      return
    end
  end

  local buf
  local height = math.floor(vim.o.lines / 2)

  -- Reuse existing persistent buffer (Anvil) if it exists
  if persistent and M.anvil_buf and vim.api.nvim_buf_is_valid(M.anvil_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == M.anvil_buf then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    -- Buffer exists but not displayed; open top split and attach it
    vim.cmd("topleft " .. height .. "split")
    vim.api.nvim_win_set_buf(0, M.anvil_buf)
    return
  end

  -- Create a new terminal in top-half split
  vim.cmd("topleft " .. height .. "new")
  buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(buf, name)

  -- Ephemeral buffers wipe when closed
  if not persistent then
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
  end

  vim.fn.termopen(args, { cwd = root })

  -- Save buffer number for persistent terminal
  if persistent then
    M.anvil_buf = buf
  end
end

--- Kill the persistent Anvil terminal, if one is running
-- Force-deletes the buffer, which stops the underlying terminal job
local function kill_anvil()
  if M.anvil_buf and vim.api.nvim_buf_is_valid(M.anvil_buf) then
    vim.api.nvim_buf_delete(M.anvil_buf, { force = true })
    M.anvil_buf = nil
    vim.notify("Anvil instance killed", vim.log.levels.INFO)
  else
    vim.notify("No running Anvil instance", vim.log.levels.WARN)
  end
end

--- Setup the plugin and register user commands
-- @param opts table Optional configuration table (currently supports allow_standalone)
function M.setup(opts)
  M.config = vim.tbl_extend("force", M.config, opts or {})

  --- Helper to create a Neovim user command
  -- @param name string Name of the command (e.g., "ForgeBuild")
  -- @param base_args table List of strings: the command and fixed leading args (e.g., {"forge", "build"})
  -- @param persistent boolean Whether the buffer should be persistent
  -- @param buf_name string Name of the buffer to display in the split
  local function create_cmd(name, base_args, persistent, buf_name)
    vim.api.nvim_create_user_command(name, function(options)
      local args = base_args
      if #options.fargs > 0 then
        args = vim.tbl_flatten({base_args, options.fargs})
      end
      open_terminal(args, persistent, buf_name)
    end, { nargs = "*", complete = function() return {} end })
  end

  -- Register commands
  create_cmd("Forge", {"forge"}, false, "Terminal Output")
  create_cmd("Cast", {"cast"}, false, "Terminal Output")
  create_cmd("Chisel", {"chisel"}, false, "Terminal Output")
  create_cmd("Anvil", {"anvil"}, true, "Anvil")

  vim.api.nvim_create_user_command("AnvilKill", kill_anvil, {
    desc = "Kill the persistent Anvil terminal instance",
  })

  -- Common forge subcommands
  create_cmd("ForgeBuild", {"forge", "build"}, false, "Terminal Output")
  create_cmd("ForgeTest", {"forge", "test"}, false, "Terminal Output")
  create_cmd("ForgeFmt", {"forge", "fmt"}, false, "Terminal Output")
  create_cmd("ForgeClean", {"forge", "clean"}, false, "Terminal Output")
  create_cmd("ForgeInstall", {"forge", "install"}, false, "Terminal Output")
  create_cmd("ForgeUpdate", {"forge", "update"}, false, "Terminal Output")
end

return M
