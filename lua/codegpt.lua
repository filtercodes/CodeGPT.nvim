local Commands = require("codegpt.commands")
local CommandsList = require("codegpt.commands_list")
local Utils = require("codegpt.utils")
local Ui = require("codegpt.ui")
local History = require("codegpt.history")
local CodeGptModule = {}

local function has_command_args(opts)
    local pattern = "%{%{command_args%}%}"
    return string.find(opts.user_message_template or "", pattern)
        or string.find(opts.system_message_template or "", pattern)
end

function CodeGptModule.get_status(...)
    return Commands.get_status(...)
end

function CodeGptModule.run_cmd(opts)
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
    if command == "clear" then
        History.clear_history(bufnr)
        vim.notify("Chat history cleared for this buffer.", vim.log.levels.INFO, { title = "CodeGPT" })
        return -- Stop all further processing
    end

    local cmd_opts = CommandsList.get_cmd_opts(command)

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
        -- No explicit command, and we are in a normal buffer. Use original guessing logic
        if command_args ~= "" then
            if text_selection == "" then
                command = "chat"
            else
                command = "code_edit"
            end
        elseif text_selection ~= "" then
            command = "completion"
        else
            command = "chat" -- Default to chat
        end
    end

    if command == nil or command == "" then
        vim.notify("No command or text selection provided", vim.log.levels.ERROR, {
            title = "CodeGPT",
        })
        return
    end

    Commands.run_cmd(command, command_args, text_selection, bufnr, cmd_opts)
end

return CodeGptModule
