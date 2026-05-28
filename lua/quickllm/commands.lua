local CommandsList = require("quickllm.commands_list")
local Providers = require("quickllm.providers")
local Api = require("quickllm.api")
local History = require("quickllm.history")
local Utils = require("quickllm.utils")

local Commands = {}

function Commands.run_cmd(command, command_args, text_selection, bufnr, cmd_opts, overrides)
	if cmd_opts == nil then
		cmd_opts = CommandsList.get_cmd_opts(command, overrides)
	end

	if cmd_opts == nil then
		vim.notify("Command not found: " .. command, vim.log.levels.ERROR, {
			title = "QuickLLM",
		})
		return
	end

    -- Tag the buffer with current metadata for status reporting and history
    vim.b[bufnr or vim.api.nvim_get_current_buf()].quickllm_metadata = {
        model = cmd_opts.model,
        command = command
    }

	if vim.g.quickllm_print_model then
		vim.notify("LLM Model - " .. cmd_opts.model, vim.log.levels.INFO, { title = "QuickLLM" })
	end

  -- If bufnr is not provided, default to the current buffer.
  -- This buffer is the "History Owner" for the conversation.
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local start_row, start_col, end_row, end_col = Utils.get_visual_selection()

  -- Resolve Provider using overrides
  local effective_overrides = overrides
  if cmd_opts.is_search_command and not (effective_overrides and effective_overrides.search_provider) then
      effective_overrides = vim.tbl_extend("force", effective_overrides or {}, {
          search_provider = vim.g.quickllm_search_provider or "gemini"
      })
  end
  local provider = Providers.get_provider(effective_overrides)

  local request, user_message_text = provider.make_request(command, cmd_opts, command_args, text_selection, bufnr)

  local use_streaming = provider.has_streaming and cmd_opts.callback_type ~= "replace_lines"

  if use_streaming then
      -- Initialize UI
      local Ui = require("quickllm.ui")

      local ui_elem = Ui.create_window("markdown", bufnr, start_row, start_col, end_row, end_col)
      local ui_bufnr = ui_elem.bufnr

      -- Start spinner
      local loading_message = cmd_opts.loading_message or "Generating..."
      local stop_spinner = Ui.start_spinner(ui_bufnr, loading_message)
        local is_first_chunk = true
        local thinking_state = false

        -- Throttling: Buffer for incoming chunks and a timer to flush them
        local pending_chunks = {}
        local render_timer = vim.loop.new_timer()
        local show_thinking = vim.g.quickllm_show_thinking ~= false

        local function flush_buffer()
            -- BUFFER GUARD: If the window was closed, stop processing and cleanup
            if not vim.api.nvim_buf_is_valid(ui_bufnr) then
                if render_timer then
                    render_timer:stop()
                    if not render_timer:is_closing() then render_timer:close() end
                    render_timer = nil
                end
                return
            end

            if #pending_chunks > 0 then
                local current_chunks = pending_chunks
                pending_chunks = {} -- Clear for next batch

                for _, chunk_data in ipairs(current_chunks) do
                    -- 1. Handle Spinner State Changes (Main thread safe)
                    -- Update spinner if the provider signals a state change (Thinking vs Generating)
                    -- We only do this if we haven't started rendering text yet.
                    if is_first_chunk and chunk_data.is_thinking ~= thinking_state then
                        local new_msg = chunk_data.is_thinking and "Thinking..." or (cmd_opts.loading_message or "Generating...")
                        if stop_spinner then stop_spinner() end
                        stop_spinner = Ui.start_spinner(ui_bufnr, new_msg)
                        thinking_state = chunk_data.is_thinking
                    end

                    -- 2. Handle State Transitions (Separator & Style Reset)
                    -- This detects the switch from thinking to answer and returns a separator
                    local transition_prefix = Ui.update_thinking_state(ui_bufnr, chunk_data.is_thinking, show_thinking)
                    local final_chunk_text = transition_prefix .. chunk_data.text

                    -- 3. Handle Text Rendering
                    -- Only append to UI if show_thinking is enabled OR it's a regular answer
                    if show_thinking or not chunk_data.is_thinking then
                        -- We only stop the spinner if we are actually going to show text
                        if is_first_chunk then
                            stop_spinner()
                            -- Clear the buffer completely before adding the first text
                            vim.api.nvim_buf_set_lines(ui_bufnr, 0, -1, false, {})
                            is_first_chunk = false
                        end
                        Ui.append_to_buf(ui_bufnr, final_chunk_text, chunk_data.is_thinking)
                    end
                end
            end
        end
      
      -- Start the render timer (fires every 100ms)
      render_timer:start(0, 100, vim.schedule_wrap(flush_buffer))

      -- Define Stream Handlers
      local stream_handlers = {
          on_chunk = function(text_chunk, is_thinking)
              -- IMPORTANT: We only perform table insertion here.
              -- No Neovim API calls (like Ui.start_spinner) should be made from this background thread.
              table.insert(pending_chunks, { text = text_chunk, is_thinking = is_thinking })
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
    
                  if vim.g.quickllm_clear_visual_selection and vim.api.nvim_buf_is_valid(bufnr) then
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
