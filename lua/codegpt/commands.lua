local CommandsList = require("codegpt.commands_list")
local Providers = require("codegpt.providers")
local Api = require("codegpt.api")
local History = require("codegpt.history")
local Utils = require("codegpt.utils")

local Commands = {}

function Commands.run_cmd(command, command_args, text_selection, bufnr, cmd_opts)
	if cmd_opts == nil then
		cmd_opts = CommandsList.get_cmd_opts(command)
	end

	if cmd_opts == nil then
		vim.notify("Command not found: " .. command, vim.log.levels.ERROR, {
			title = "CodeGPT.vim",
		})
		return
	end

  -- If bufnr is not provided, default to the current buffer.
  -- This buffer is the "History Owner" for the conversation.
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
  local new_callback = function(lines)
    cmd_opts.callback(lines, bufnr, start_row, start_col, end_row, end_col)
  end

  local provider = Providers.get_provider()
	local request, user_message_text = provider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
  provider.make_call(request, user_message_text, new_callback, bufnr)
end

function Commands.get_status(...)
	return Api.get_status(...)
end

return Commands
