local CommandsList = require("codegpt.commands_list")
local Providers = require("codegpt.providers")
local Api = require("codegpt.api")
local History = require("codegpt.history")
local Utils = require("codegpt.utils")

local Commands = {}

function Commands.run_cmd(command, command_args, text_selection, bufnr, cmd_opts, overrides)
	if cmd_opts == nil then
		cmd_opts = CommandsList.get_cmd_opts(command, overrides)
	end

	if cmd_opts == nil then
		vim.notify("Command not found: " .. command, vim.log.levels.ERROR, {
			title = "CodeGPT.vim",
		})
		return
	end

	Api.set_status(command, cmd_opts.model)

	if vim.g.codegpt_print_model then
		vim.notify("LLM Model - " .. cmd_opts.model, vim.log.levels.INFO, { title = "CodeGPT.vim" })
	end

  -- If bufnr is not provided, default to the current buffer.
  -- This buffer is the "History Owner" for the conversation.
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local start_row, start_col, end_row, end_col = Utils.get_visual_selection()

  -- Resolve Provider using overrides
  local effective_overrides = overrides
  if cmd_opts.is_search_command and not (effective_overrides and effective_overrides.search_provider) then
      effective_overrides = vim.tbl_extend("force", effective_overrides or {}, {
          search_provider = vim.g.codegpt_search_provider or "gemini"
      })
  end
  local provider = Providers.get_provider(effective_overrides)

  local request, user_message_text = provider.make_request(command, cmd_opts, command_args, text_selection, bufnr)

  if provider.has_streaming then
      -- Initialize UI
      local Ui = require("codegpt.ui")
      local ui_elem = Ui.create_window("markdown", bufnr, start_row, start_col, end_row, end_col)
      local ui_bufnr = ui_elem.bufnr

      -- Start spinner
      local loading_message = cmd_opts.loading_message or "Generating..."
      local stop_spinner = Ui.start_spinner(ui_bufnr, loading_message)
      local is_first_chunk = true
      
      -- Throttling: Buffer for incoming chunks and a timer to flush them
      local pending_text = ""
      local render_timer = vim.loop.new_timer()
      
      local function flush_buffer()
          if pending_text ~= "" then
              if is_first_chunk then
                  stop_spinner()
                  -- Clear the buffer completely before adding the first text
                  vim.api.nvim_buf_set_lines(ui_bufnr, 0, -1, false, {})
                  is_first_chunk = false
              end
              local chunk = pending_text
              pending_text = ""
              Ui.append_to_buf(ui_bufnr, chunk)
          end
      end
      
      -- Start the render timer (fires every 100ms)
      render_timer:start(0, 100, vim.schedule_wrap(flush_buffer))

      -- Define Stream Handlers
      local stream_handlers = {
          on_chunk = function(text_chunk)
              -- Append to pending buffer instead of direct UI call
              pending_text = pending_text .. text_chunk
          end,
          on_complete = function(full_text)
              -- Stop and cleanup the timer
              if render_timer then
                  render_timer:stop()
                  if not render_timer:is_closing() then
                      render_timer:close()
                  end
                  render_timer = nil
              end

              if is_first_chunk then
                  stop_spinner()
                  -- Clear the spinner if no text was received
                  vim.api.nvim_buf_set_lines(ui_bufnr, 0, -1, false, {})
              end
              
              -- Final flush to ensure all text is rendered
              vim.schedule(function()
                  flush_buffer()
                  
                  -- Add to history only if we have content
                  if full_text and full_text ~= "" then
                      History.add_message(bufnr, "user", user_message_text)
                      History.add_message(bufnr, "assistant", full_text)
                  end
    
                  if vim.g["codegpt_clear_visual_selection"] and vim.api.nvim_buf_is_valid(bufnr) then
                      vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                      vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                  end
              end)
          end,
          on_error = function(err)
              -- Stop and cleanup the timer
              if render_timer then
                  render_timer:stop()
                  if not render_timer:is_closing() then
                      render_timer:close()
                  end
                  render_timer = nil
              end
              
              vim.schedule(function()
                  flush_buffer()
                  stop_spinner()
                  vim.notify("Stream Error: " .. tostring(err), vim.log.levels.ERROR)
              end)
          end
      }

      -- Call Provider with Stream Handlers
      provider.make_call(request, user_message_text, stream_handlers, bufnr)
  else
      -- Legacy / Non-Streaming Mode
      local new_callback = function(lines)
          cmd_opts.callback(lines, bufnr, start_row, start_col, end_row, end_col)
      end
      provider.make_call(request, user_message_text, new_callback, bufnr)
  end
end

function Commands.get_status(...)
	return Api.get_status(...)
end

return Commands
