local Popup = require("nui.popup")
local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Ui = {}

local Api = require("quickllm.api")

-- "History Owner" buffer (e.g., { [popup_bufnr] = owner_bufnr }).
local ui_to_owner_map = {}

-- Track which popups are currently active
local active_popups = {}

local popup
local split

---Looks up the owner buffer for a given UI buffer.
function Ui.get_owner_bufnr(bufnr)
    return ui_to_owner_map[bufnr]
end

---Retrieves metadata for the active popup associated with the given buffer.
function Ui.get_active_status_info(bufnr)
    local target_bufnr = bufnr

    -- If the buffer is an owner, find its active popup
    if not active_popups[bufnr] then
        for p_buf, info in pairs(active_popups) do
            if info.owner == bufnr then
                target_bufnr = p_buf
                break
            end
        end
    end

    -- Return metadata if the target buffer is an active popup
    if active_popups[target_bufnr] then
        local metadata = vim.b[target_bufnr] and vim.b[target_bufnr].quickllm_metadata
        if metadata then
            return metadata.command, metadata.model
        end
    end

    return nil, nil
end

---Closes the active popup associated with the given buffer.
function Ui.close_active_popup(bufnr)
    -- If the buffer is itself a popup
    if active_popups[bufnr] then
        active_popups[bufnr].ui_elem:unmount()
        return
    end

    -- If the buffer is an owner, find and close its popup
    for _, info in pairs(active_popups) do
        if info.owner == bufnr then
            info.ui_elem:unmount()
            break
        end
    end
end


local function create_horizontal()
    if not split then
        split = Split({
            relative = "editor",
            position = "bottom",
            size = vim.g.quickllm_horizontal_popup_size,
        })
    end

    return split
end

local function create_vertical()
    if not split then
        split = Split({
            relative = "editor",
            position = "right",
            size = vim.g.quickllm_vertical_popup_size,
        })
    end

    return split
end

local function create_popup()
    if not popup then
        local window_options = vim.g.quickllm_popup_window_options
        if window_options == nil then
            window_options = {}
        end

        -- check the old wrap config variable and use it if it's not set
        if window_options["wrap"] == nil then
            window_options["wrap"] = vim.g.quickllm_wrap_popup_text
        end

        popup = Popup({
            enter = true,
            focusable = true,
            border = vim.g.quickllm_popup_border,
            position = "50%",
            size = {
                width = "80%",
                height = "60%",
            },
            win_options = window_options,
        })
    end

    popup:update_layout(vim.g.quickllm_popup_options)

    return popup
end

function Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    local popup_type = vim.g.quickllm_popup_type
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

    -- Tag the popup buffer with the same metadata as the owner
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        vim.b[ui_bufnr].quickllm_metadata = vim.b[bufnr].quickllm_metadata
    end

    -- Register the link between the UI buffer and its owner
    ui_to_owner_map[ui_bufnr] = bufnr
    active_popups[ui_bufnr] = { owner = bufnr, ui_elem = ui_elem }

    -- unmount component when cursor leaves buffer
    ui_elem:on(event.BufLeave, function()
        -- Deregister the link using the captured buffer number
        ui_to_owner_map[ui_bufnr] = nil
        active_popups[ui_bufnr] = nil
        ui_elem:unmount()
    end)

    -- unmount component when key 'q'
    ui_elem:map("n", vim.g.quickllm_ui_commands.quit, function()
        ui_elem:unmount()
    end, { noremap = true, silent = true })

    -- set content type
    vim.api.nvim_buf_set_option(ui_elem.bufnr, "filetype", filetype)

    -- replace lines when ctrl-o pressed
    ui_elem:map("n", vim.g.quickllm_ui_commands.use_as_output, function()
        local lines = vim.api.nvim_buf_get_lines(ui_elem.bufnr, 0, -1, false)
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
        ui_elem:unmount()
    end)

    -- selecting all the content when ctrl-i is pressed
    -- so the user can proceed with another API request
    ui_elem:map("n", vim.g.quickllm_ui_commands.use_as_input, function()
        -- The new tracking system handles the history automatically.
        -- We just need to select the text and start the Chat command.
        vim.api.nvim_feedkeys("ggVG:Chat ", "n", false)
    end, { noremap = false })

    -- mapping custom commands
    for _, command in ipairs(vim.g.quickllm_ui_custom_commands) do
        ui_elem:map(command[1], command[2], command[3], command[4])
    end

    return ui_elem
end

function Ui.start_spinner(bufnr, loading_message)
    local msg = loading_message or "Generating..."
    local frames = Api.progress_bar_dots
    local idx = 1
    local timer = vim.loop.new_timer()
    local start_time = vim.loop.now()
    local ns_id = vim.api.nvim_create_namespace("quickllm_spinner")
    
    -- Initial set
    if vim.api.nvim_buf_is_valid(bufnr) then
        local base_text = "  " .. frames[1] .. " " .. msg
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { base_text })
    end

    timer:start(100, 100, vim.schedule_wrap(function()
        if not timer then
            return
        end

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
        local elapsed_ms = vim.loop.now() - start_time
        local elapsed_sec = math.floor(elapsed_ms / 1000)

        local base_text = "  " .. frames[idx] .. " " .. msg
        local display_text = base_text
        if elapsed_sec >= 5 then
            display_text = base_text .. string.format(" (%ds)", elapsed_sec)
        end

        -- Only replace the first line.
        -- Use pcall in case buffer was closed mid-tick
        pcall(function()
            vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { display_text })
            if elapsed_sec >= 5 then
                vim.api.nvim_buf_add_highlight(bufnr, ns_id, "Comment", 0, #base_text, -1)
            end
        end)
    end))

    return function()
        if timer then
            timer:stop()
            if not timer:is_closing() then
                timer:close()
            end
            timer = nil
        end
        -- Clear the spinner line when stopping
        if vim.api.nvim_buf_is_valid(bufnr) then
            pcall(vim.api.nvim_buf_set_lines, bufnr, 0, 1, false, { "" })
        end
    end
end

function Ui.append_to_buf(bufnr, text_chunk)
    if text_chunk == nil or #text_chunk == 0 then
        return
    end

    if not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local current_line_count = vim.api.nvim_buf_line_count(bufnr)
    local last_line_len = 0
    if current_line_count > 0 then
        local last_line = vim.api.nvim_buf_get_lines(bufnr, current_line_count - 1, current_line_count, false)[1]
        last_line_len = #last_line
    end

    -- Identify if we should auto-scroll (cursor is at the last line before appending)
    local winid = vim.fn.bufwinid(bufnr)
    local should_scroll = winid ~= -1 and vim.api.nvim_win_get_cursor(winid)[1] == current_line_count

    -- Append the chunk at the end of the buffer
    -- nvim_buf_set_text handles newlines within the text_chunk correctly.
    vim.api.nvim_buf_set_text(bufnr, current_line_count - 1, last_line_len, current_line_count - 1, last_line_len, vim.split(text_chunk, '\n', { plain = true }))

    -- Auto-scroll if following
    if should_scroll then
        pcall(vim.api.nvim_win_set_cursor, winid, {vim.api.nvim_buf_line_count(bufnr), 0})
    end
end

function Ui.popup(lines, filetype, bufnr, start_row, start_col, end_row, end_col)
    local ui_elem = Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    vim.api.nvim_buf_set_lines(ui_elem.bufnr, 0, -1, false, lines)
end

return Ui
