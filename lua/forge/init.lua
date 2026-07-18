--- forge.nvim - Minimal Neovim plugin to run Foundry commands in a split terminal
-- Supports Forge, Cast, Chisel, and persistent Anvil terminal.
-- Ephemeral buffers (Forge/Cast/Chisel) wipe on close; Anvil is persistent.
local M = {}

--- Plugin configuration table
-- @field allow_standalone boolean Whether to allow running commands in folders without foundry.toml
-- @field split_direction string Where terminal splits open: "top", "bottom", "left" or "right"
-- @field match_verbosity integer Verbosity for ForgeTestMatch/ForgeTestSelection, 0-5 (0 = no flag, 4 = -vvvv)
M.config = {
  allow_standalone = false,
  split_direction = "top",
  match_verbosity = 4,
}

--- Modifier commands for each split direction
local split_mods = {
  top = "topleft",
  bottom = "botright",
  left = "vertical topleft",
  right = "vertical botright",
}

--- Build the split command prefix (modifiers + size) from config
-- @return string e.g. "topleft 20" or "vertical botright 80"
local function split_prefix()
  local dir = M.config.split_direction
  local mods = split_mods[dir] or split_mods.top
  local size
  if dir == "left" or dir == "right" then
    size = math.floor(vim.o.columns / 2)
  else
    size = math.floor(vim.o.lines / 2)
  end
  return mods .. " " .. size
end

--- Stores the buffer number of the persistent Anvil terminal
-- @type integer|nil
M.anvil_buf = nil

--- Stores the buffer number of the last ephemeral terminal (Forge/Cast/Chisel)
-- @type integer|nil
M.term_buf = nil

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

  -- Reuse existing persistent buffer (Anvil) if it exists
  if persistent and M.anvil_buf and vim.api.nvim_buf_is_valid(M.anvil_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == M.anvil_buf then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    -- Buffer exists but not displayed; open a split and attach it
    vim.cmd(split_prefix() .. "split")
    vim.api.nvim_win_set_buf(0, M.anvil_buf)
    return
  end

  -- If a previous ephemeral terminal is still open, reuse its window
  local old_buf = M.term_buf
  local reuse_win
  if not persistent and old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == old_buf then
        reuse_win = win
        break
      end
    end
  else
    old_buf = nil
  end

  if reuse_win then
    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_win_set_buf(reuse_win, buf)
    vim.api.nvim_set_current_win(reuse_win)
  else
    -- Create a new terminal split
    vim.cmd(split_prefix() .. "new")
    buf = vim.api.nvim_get_current_buf()
  end

  -- Kill the previous terminal (stops its job and frees the buffer name)
  if old_buf and vim.api.nvim_buf_is_valid(old_buf) then
    vim.api.nvim_buf_delete(old_buf, { force = true })
  end

  vim.api.nvim_buf_set_name(buf, name)

  -- Ephemeral buffers wipe when closed
  if not persistent then
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
  end

  vim.fn.termopen(args, { cwd = root })

  -- Save buffer number so the split can be reused later
  if persistent then
    M.anvil_buf = buf
  else
    M.term_buf = buf
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

--- Run `forge test --mt <name>` for a given test function name,
--- with the configured match_verbosity flag
-- @param name string|nil Name of the test function to match
local function run_match_test(name)
  if not name or name == "" then
    vim.notify("No test function name provided", vim.log.levels.WARN)
    return
  end
  local args = { "forge", "test" }
  local v = tonumber(M.config.match_verbosity) or 0
  if v > 0 then
    table.insert(args, "-" .. string.rep("v", math.min(v, 5)))
  end
  vim.list_extend(args, { "--mt", name })
  open_terminal(args, false, "Terminal Output")
end

--- Get the text of the last visual selection (marks '< and '>)
-- @return string The selected text, joined without newlines
local function get_visual_selection()
  local s = vim.fn.getpos("'<")
  local e = vim.fn.getpos("'>")
  local start_row, start_col = s[2], s[3]
  local end_row, end_col = e[2], e[3]
  -- Clamp end column (linewise/`$` selections report a huge column)
  local end_line = vim.api.nvim_buf_get_lines(0, end_row - 1, end_row, true)[1] or ""
  if end_col > #end_line then
    end_col = #end_line
  end
  local lines = vim.api.nvim_buf_get_text(0, start_row - 1, start_col - 1, end_row - 1, end_col, {})
  return vim.trim(table.concat(lines, ""))
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
      local args = vim.list_extend({}, base_args)
      vim.list_extend(args, options.fargs)
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

  -- Run a single test function: `:ForgeTestMatch testFoo`, or no args to be prompted
  vim.api.nvim_create_user_command("ForgeTestMatch", function(options)
    if options.args ~= "" then
      run_match_test(options.args)
    else
      vim.ui.input({ prompt = "Test function name: " }, function(input)
        if input then run_match_test(input) end
      end)
    end
  end, { nargs = "?", desc = "Run forge test --mt <test function name>" })

  -- Visual mode: run the selected word as a test match (`:'<,'>ForgeTestSelection`)
  vim.api.nvim_create_user_command("ForgeTestSelection", function()
    run_match_test(get_visual_selection())
  end, { range = true, desc = "Run forge test --mt on the visually selected text" })
  create_cmd("ForgeFmt", {"forge", "fmt"}, false, "Terminal Output")
  create_cmd("ForgeClean", {"forge", "clean"}, false, "Terminal Output")
  create_cmd("ForgeInstall", {"forge", "install"}, false, "Terminal Output")
  create_cmd("ForgeUpdate", {"forge", "update"}, false, "Terminal Output")
end

return M
