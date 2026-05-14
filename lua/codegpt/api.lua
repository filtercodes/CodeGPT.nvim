local curl = require("plenary.curl")

local Api = {}

CODEGPT_CALLBACK_COUNTER = 0

local status_index = 0
Api.progress_bar_dots = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

function Api.get_status(...)
    local Ui = require("codegpt.ui")
    local bufnr = vim.api.nvim_get_current_buf()
    local last_command, last_model = Ui.get_active_status_info(bufnr)

    local status = ""
    if CODEGPT_CALLBACK_COUNTER > 0 then
        status_index = status_index + 1
        if status_index > #Api.progress_bar_dots then
            status_index = 1
        end
        status = Api.progress_bar_dots[status_index]
    end

    if last_model and last_model ~= "" then
        local model_info = string.format("%s  🤖 %s", last_command, last_model)
        if status ~= "" then
            status = status .. " " .. model_info
        else
            status = model_info
        end
        return status
    end

    return ""
end

function Api.run_started_hook()
    if vim.g["codegpt_hooks"]["request_started"] ~= nil then
        vim.g["codegpt_hooks"]["request_started"]()
    end

    CODEGPT_CALLBACK_COUNTER = CODEGPT_CALLBACK_COUNTER + 1
end

function Api.run_finished_hook()
    CODEGPT_CALLBACK_COUNTER = CODEGPT_CALLBACK_COUNTER - 1
    if CODEGPT_CALLBACK_COUNTER <= 0 then
        if vim.g["codegpt_hooks"]["request_finished"] ~= nil then
            vim.g["codegpt_hooks"]["request_finished"]()
        end
    end
end


return Api
