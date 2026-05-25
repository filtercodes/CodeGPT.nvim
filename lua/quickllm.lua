local Commands = require("quickllm.commands")
local CommandsList = require("quickllm.commands_list")
local Utils = require("quickllm.utils")
local Ui = require("quickllm.ui")
local History = require("quickllm.history")
local QuickllmModule = {}

local function has_command_args(opts)
    local pattern = "%{%{command_args%}%}"
    return string.find(opts.user_message_template or "", pattern)
        or string.find(opts.system_message_template or "", pattern)
end

function QuickllmModule.get_status(...)
    return Commands.get_status(...)
end

function QuickllmModule.run_cmd(opts)
    local text_selection = Utils.get_selected_lines()
    local command_args = table.concat(opts.fargs, " ")
    local command = opts.fargs[1]
    local bufnr = nil
    local is_ui_window = false

    -- Determine Context and which buffer is History Owner
    local current_bufnr = vim.api.nvim_get_current_buf()
    local owner_bufnr = Ui.get_owner_bufnr(current_bufnr)

    if owner_bufnr then
        is_ui_window = true
        bufnr = owner_bufnr -- History is always the owner's
    else
        bufnr = current_bufnr -- History is the current buffer's
    end

    -- Handle `clear` as a special case that doesn't need validation
    if command == "clear" and #opts.fargs == 1 then
        History.clear_history(bufnr)
        vim.b[bufnr].quickllm_metadata = nil
        Ui.close_active_popup(current_bufnr)
        vim.notify("Chat history cleared for this buffer.", vim.log.levels.INFO, { title = "QuickLLM" })
        return -- Stop all further processing
    end

    local is_recall = command == "recall" or command == "last"
    local is_recall_action = false
    local recall_offset = 1
    
    if is_recall then
        if #opts.fargs == 1 then
            is_recall_action = true
        elseif #opts.fargs == 2 then
            local num = tonumber(opts.fargs[2])
            if num and num > 0 and math.floor(num) == num then
                is_recall_action = true
                recall_offset = num
            end
        end
    end

    if is_recall_action then
        local last_response, model, cmd = History.get_last_response(bufnr, recall_offset)
        if last_response then
            -- Set metadata on current buffer so create_window can inherit it
            vim.b[bufnr].quickllm_metadata = { model = model, command = cmd }
            local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
            Ui.popup(Utils.parse_lines(last_response), vim.g.quickllm_text_popup_filetype, bufnr, start_row, start_col, end_row, end_col)
        else
            vim.notify("No assistant response found at history index " .. recall_offset .. " for this buffer.", vim.log.levels.WARN, { title = "QuickLLM" })
        end
        return
    end

    local is_rewind = command == "rewind" or command == "undo"
    if is_rewind and #opts.fargs == 1 then
        local success = History.undo_last_exchange(bufnr)
        if success then
            vim.notify("Last conversation exchange removed from history.", vim.log.levels.INFO, { title = "QuickLLM" })
        else
            vim.notify("No history to rewind.", vim.log.levels.WARN, { title = "QuickLLM" })
        end
        return
    end

    -- Handle `help` as a special case
    if command == "help" and #opts.fargs == 1 then
        local Help = require("quickllm.help")
        Help.show_help(bufnr)
        return
    end

    local cmd_opts = nil
    local overrides = nil
    
    -- Command-to-Provider Mapping
    local provider_map = {
        Gemini = "gemini",
        Claude = "anthropic",
        Openai = "openai",
        Ollama = "ollama",
        Groq = "groq",
    }

    -- Detect Presets
    local preset_idx = opts.name:match("Chat(%d)$")
    if preset_idx then
        overrides = { preset = tonumber(preset_idx) }
    elseif provider_map[opts.name] then
        overrides = { 
            provider = provider_map[opts.name],
            -- By default, if they use a provider command for search, use that provider's native search
            search_provider = provider_map[opts.name]
        }
        -- Special case for Ollama + Search -> Local Grounding
        if command == "search" and opts.name == "Ollama" then
            overrides.search_provider = "local_grounding"
        end
    end

    -- If special commands were used with arguments, we want them to fall through to chat/code_edit guessing logic
    -- and prevent them from fetching default options.
    if not ((command == "clear" or is_recall or is_rewind) and #opts.fargs > 1) then
        cmd_opts = CommandsList.get_cmd_opts(command, overrides)
    end

    -- If the detected command doesn't support arguments but arguments were provided,
    -- treat it as a general chat message instead.
    if cmd_opts ~= nil and not has_command_args(cmd_opts) and #opts.fargs > 1 then
        cmd_opts = nil
    end

    if cmd_opts ~= nil then
        -- An explicit command was used (e.g., :Chat explain, :Chat tests)
        if has_command_args(cmd_opts) then
            command_args = table.concat(opts.fargs, " ", 2)
        else
            command_args = ""
        end
    elseif is_ui_window then
        -- No explicit command, but we are in a UI window. Default to chat continuation
        command = "chat"
        -- command_args is already the full input
        text_selection = "" -- Ignore any selection in the popup
    else
        -- No explicit command, and we are in a normal buffer.
        command = "chat" -- Default to chat
    end

    if command == nil or command == "" then
        vim.notify("No command or text selection provided", vim.log.levels.ERROR, {
            title = "QuickLLM",
        })
        return
    end

    Commands.run_cmd(command, command_args, text_selection, bufnr, cmd_opts, overrides)
end

return QuickllmModule
