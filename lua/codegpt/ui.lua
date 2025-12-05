local Popup = require("nui.popup")
local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Ui = {}

-- This table will store the link between a temporary UI buffer and its
-- "History Owner" buffer (e.g., { [popup_bufnr] = owner_bufnr }).
local ui_to_owner_map = {}

local popup
local split

---Looks up the owner buffer for a given UI buffer.
---@param bufnr number: The buffer number of the UI window.
---@return number | nil: The owner's buffer number or nil if not found.
function Ui.get_owner_bufnr(bufnr)
    return ui_to_owner_map[bufnr]
end



local function create_horizontal()
    if not split then
        split = Split({
            relative = "editor",
            position = "bottom",
            size = vim.g["codegpt_horizontal_popup_size"],
        })
    end

    return split
end

local function create_vertical()
    if not split then
        split = Split({
            relative = "editor",
            position = "right",
            size = vim.g["codegpt_vertical_popup_size"],
        })
    end

    return split
end

local function create_popup()
    if not popup then
        local window_options = vim.g["codegpt_popup_window_options"]
        if window_options == nil then
            window_options = {}
        end

        -- check the old wrap config variable and use it if it's not set
        if window_options["wrap"] == nil then
            window_options["wrap"] = vim.g["codegpt_wrap_popup_text"]
        end

        popup = Popup({
            enter = true,
            focusable = true,
            border = vim.g["codegpt_popup_border"],
            position = "50%",
            size = {
                width = "80%",
                height = "60%",
            },
            win_options = window_options,
        })
    end

    popup:update_layout(vim.g["codegpt_popup_options"])

    return popup
end

function Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    local popup_type = vim.g["codegpt_popup_type"]
    local ui_elem = nil
    if popup_type == "horizontal" then
        ui_elem = create_horizontal()
    elseif popup_type == "vertical" then
        ui_elem = create_vertical()
    else
        ui_elem = create_popup()
    end
    
    -- mount/open the component
    ui_elem:mount()

    -- Capture the buffer number in a local variable for the closure
    local ui_bufnr = ui_elem.bufnr

    -- Register the link between the UI buffer and its owner
    ui_to_owner_map[ui_bufnr] = bufnr

    -- unmount component when cursor leaves buffer
    ui_elem:on(event.BufLeave, function()
        -- Deregister the link using the captured buffer number
        ui_to_owner_map[ui_bufnr] = nil
        ui_elem:unmount()
    end)

    -- unmount component when key 'q'
    ui_elem:map("n", vim.g["codegpt_ui_commands"].quit, function()
        ui_elem:unmount()
    end, { noremap = true, silent = true })

    -- set content type
    vim.api.nvim_buf_set_option(ui_elem.bufnr, "filetype", filetype)

    -- replace lines when ctrl-o pressed
    ui_elem:map("n", vim.g["codegpt_ui_commands"].use_as_output, function()
        local lines = vim.api.nvim_buf_get_lines(ui_elem.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
        ui_elem:unmount()
    end)

    -- selecting all the content when ctrl-i is pressed
    -- so the user can proceed with another API request
    ui_elem:map("n", vim.g["codegpt_ui_commands"].use_as_input, function()
        -- The new tracking system handles the history automatically.
        -- We just need to select the text and start the Chat command.
        vim.api.nvim_feedkeys("ggVG:Chat ", "n", false)
    end, { noremap = false })

    -- mapping custom commands
    for _, command in ipairs(vim.g.codegpt_ui_custom_commands) do
        ui_elem:map(command[1], command[2], command[3], command[4])
    end

    return ui_elem
end

function Ui.start_spinner(bufnr)
    local frames = { "|", "/", "-", "\\" }
    local idx = 1
    local timer = vim.loop.new_timer()
    
    -- Initial set
    if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "   " .. frames[1] .. "  Thinking..." })
    end

    timer:start(100, 100, vim.schedule_wrap(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
            -- If buffer is no longer valid, stop and close the timer.
            if timer then
                timer:stop()
                if not timer:is_closing() then
                    timer:close()
                end
            end
            return
        end

        idx = (idx % #frames) + 1
        -- Only replace the first line.
        -- Use pcall in case buffer was closed mid-tick
        pcall(vim.api.nvim_buf_set_lines, bufnr, 0, 1, false, { "   " .. frames[idx] .. "  Thinking..." })
    end))

    return function()
        if timer then
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
            timer = nil
        end
    end
end

function Ui.append_to_buf(bufnr, text_chunk)
    if text_chunk == nil or #text_chunk == 0 then
        return
    end

    vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return
        end

        local current_line_count = vim.api.nvim_buf_line_count(bufnr)
        local last_line_len = 0
        if current_line_count > 0 then
            local last_line = vim.api.nvim_buf_get_lines(bufnr, current_line_count - 1, current_line_count, false)[1]
            last_line_len = #last_line
        end

        -- Append the chunk at the end of the buffer
        -- nvim_buf_set_text handles newlines within the text_chunk correctly.
        vim.api.nvim_buf_set_text(bufnr, current_line_count - 1, last_line_len, current_line_count - 1, last_line_len, vim.split(text_chunk, '\n', { plain = true }))
    end)
end

function Ui.popup(lines, filetype, bufnr, start_row, start_col, end_row, end_col)
    local ui_elem = Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    vim.api.nvim_buf_set_lines(ui_elem.bufnr, 0, 1, false, lines)
end

return Ui
