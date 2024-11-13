---@class Freeze
local M = {}

---@param ... table
local function is_array(...)
  if vim.fn.has("nvim-0.10") == 1 then
    return vim.isarray(...)
  else
    return vim.tbl_islist(...)
  end
end

-- We require command to give, this also allows us to have a custom command
M.required_options = {
  command = "freeze",
}

-- We allow the user to provide custom options, if none are provided the command will use its default args
M.allowed_opts = {
  command = "string",
  open = "boolean",
  config = "string",
  output = { "string", "function" },
  window = "boolean",
  padding = { "string", "table" },
  margin = { "string", "table" },
  background = "string",
  theme = "string",
  show_line_numbers = "boolean",
  line_height = "number",
  language = "string",
  font = {
    size = "number",
    family = "string",
    ligatures = "boolean",
  },
  shadow = {
    blur = "number",
    x = "number",
    y = "number",
  },
  border = {
    radius = "number",
    width = "number",
    color = "string",
  },
}

-- Parse the options provided by the user and ensure they are valid
M.parse_options = function(opts)
  local options

  -- Ensure the input is a table
  vim.validate({
    opts = { opts, "table" },
  })

  -- Ensure that the user has provided the required options
  options = vim.tbl_deep_extend("force", M.required_options, opts or {})

  -- Ensure that the user has not provided any options that are not allowed
  if M.allowed_opts then
    for k, v in pairs(opts) do
      local k_type = M.allowed_opts[k]

      -- Check if the key is allowed
      -- We need to handle the tables which are not arrays diffrently
      if type(k_type) == "table" and not is_array(k_type) then
        vim.validate({ [k] = { v, "table" } })
        for _k, _v in pairs(v) do
          vim.validate({
            [_k] = { _v, k_type[_k] },
          })
        end
      else
        vim.validate({
          [k] = { v, k_type },
        })
      end
    end
  end

  return options
end

-- Open the generated image based on the OS
---@param args FreezeOptions
---@return string
local function open_by_os(args)
  local is_win = vim.loop.os_uname().sysname:match("Windows")
  local is_linux = vim.loop.os_uname().sysname:match("Linux")
  local output
  if type(args.output) == "function" then
    output = vim.fn.expand(args.output())
  else
    output = vim.fn.expand(args.output)
  end
  local cmd = {}
  if is_win then
    table.insert(cmd, "explorer")
  elseif is_linux then
    table.insert(cmd, "xdg-open")
  else
    table.insert(cmd, "open")
  end
  table.insert(cmd, output)
  return vim.fn.system(cmd)
end

-- Open the generated image
---@param args FreezeOptions
M.open = function(args)
  open_by_os(args)
end

-- Populate the command line arguments
local function populate_cmd(cmd, args, tbl, prefix)
  for k, v in pairs(tbl) do
    -- Handle margin and padding separately as tables
    if k == "margin" or k == "padding" then
      if type(v) == "table" then
        table.insert(cmd, "--" .. prefix .. k)
        table.insert(cmd, table.concat(v, ","))
      end
    -- Table options ('border', 'font', 'shadow')
    elseif type(v) == "table" and not is_array(v) then
      populate_cmd(cmd, args, v, prefix .. k .. ".")
    -- Handle anything that is not the command or language option
    elseif k ~= "command" and k ~= "language" and k ~= "open" then
      table.insert(cmd, "--" .. prefix .. string.gsub(k, "_", "-"))

      -- If the value is a function, call it with the args, otherwise just use the value
      local value = nil
      if type(v) == "function" then
        value = v(args)
      else
        value = v
      end

      -- Don't append the value if it's a boolean option.
      if type(v) ~= "boolean" then
        table.insert(cmd, value)
      end
    end
  end
end

-- Generate the command line arguments
M.get_arguments = function(args, options)
  local cmd = {}

  table.insert(cmd, options.command)
  populate_cmd(cmd, args, options, "")

  return cmd
end

-- Get lines and format them for the command
M.format_lines = function(cmdline, args)
  local begin_line = args.line1 - 1
  local finish_line = args.line2

  if args.range == 0 then
    begin_line = 0
    finish_line = -1
  end

  local marks = vim.api.nvim_buf_get_mark(vim.api.nvim_win_get_buf(0), "h")[1]
  if marks > 0 then
    local hl
    if args.range == 0 or (args.line1 and marks >= begin_line and marks <= finish_line) then
      hl = marks - begin_line
      table.insert(cmdline, "--lines ")
      table.insert(cmdline, hl)
    end
  end

  local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(0), begin_line, finish_line, false)

  return lines, cmdline
end

-- Start freeze.nvim with the given arguments and options
M.start = function(args, options)
  local lines = nil

  -- Start building the base of the command from the options
  local base_cmdline = M.get_arguments(args, options)
  -- Parse buffer into lines, based on arguments from neovim, reshapes cmdline
  lines, base_cmdline = M.format_lines(base_cmdline, args)

  local cmd = vim.tbl_extend("error", base_cmdline, {})

  args = args.fargs or {}
  local args_list = {}
  -- Parse the arguments into a table
  for _, v in ipairs(args) do
    local key = vim.split(v, "=")[1]
    local value = vim.split(v, "=")[2]
    args_list[key] = value
  end

  -- If the user gave us a language lets use it
  -- Else try to get the language from neovim's buffer filetype
  table.insert(cmd, "--language")
  if args_list.language then
    table.insert(cmd, args_list.language)
  elseif options.language then
    table.insert(cmd, options.language)
  else
    table.insert(cmd, vim.bo.filetype)
  end

  -- Run the command and get the output
  local ret = vim.fn.system(cmd, lines)
  if string.find(ret, "WROTE") then
    return vim.notify("File saved to" .. string.sub(ret, 8), vim.log.levels.INFO, { title = "freeze.nvim" })
  else
    return vim.notify("freeze returned: " .. ret, vim.log.levels.WARN, { title = "freeze.nvim" })
  end
end

-- Define commands for neovim
M.setup = function(opts)
  local options = M.parse_options(opts)

  vim.api.nvim_create_user_command("Freeze", function(args)
    M.start(args, options)
    -- If the user wants to open the file, open it
    if args.args == "open" or options.open then
      if not options.output then
        options.output = vim.fn.expand("freeze.png")
      end
      M.open(options)
    end
  end, {
    desc = "convert range to code image representation",
    force = false,
    range = true,
    nargs = "*",
    complete = function(_, line)
      local opts_list = vim.tbl_keys(M.allowed_opts)
      local l = vim.split(line, "%s+")
      -- Remove `command` from the list of options
      for i, v in ipairs(opts_list) do
        if v == "command" then
          table.remove(opts_list, i)
        end
      end
      table.sort(opts_list)
      return vim.tbl_filter(function(opt)
        return vim.startswith(opt, l[#l])
      end, opts_list)
    end,
  })
end

return M
