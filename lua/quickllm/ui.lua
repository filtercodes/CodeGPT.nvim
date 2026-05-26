local Popup = require("nui.popup")
local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Ui = {}

local Api = require("quickllm.api")

-- "History Owner" buffer (e.g., { [popup_bufnr] = owner_bufnr }).
local ui_to_owner_map = {}

-- Track which popups are currently active
local active_popups = {}

---Looks up the owner buffer for a given UI buffer.
function Ui.get_owner_bufnr(bufnr)
    return ui_to_owner_map[bufnr]
end

---Checks if there is an active popup associated with the given buffer.
function Ui.has_active_popup(bufnr)
    if active_popups[bufnr] then return true end
    for _, info in pairs(active_popups) do
        if info.owner == bufnr then return true end
    end
    return false
end

---Retrieves metadata for the active popup or the buffer itself.
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

    -- Fallback: If no active popup, check the buffer itself (for direct edits)
    local metadata = vim.b[bufnr] and vim.b[bufnr].quickllm_metadata
    if metadata then
        return metadata.command, metadata.model
    end

    return nil, nil
end

---Closes the active popup associated with the given buffer.
function Ui.close_active_popup(bufnr)
    -- If the buffer is itself a popup
    if active_popups[bufnr] then
        local info = active_popups[bufnr]
        active_popups[bufnr] = nil
        ui_to_owner_map[bufnr] = nil
        info.ui_elem:unmount()
        return
    end

    -- If the buffer is an owner, find and close its popup
    for p_bufnr, info in pairs(active_popups) do
        if info.owner == bufnr then
            active_popups[p_bufnr] = nil
            ui_to_owner_map[p_bufnr] = nil
            info.ui_elem:unmount()
            break
        end
    end
end


local function create_horizontal()
    local size = vim.g.quickllm_horizontal_popup_size or "40%"
    local split_obj = Split({
        relative = "editor",
        position = "bottom",
        size = size,
    })

    -- Calculate height for tracking (but split will remain static)
    local height = 0
    if type(size) == "string" and size:match("%%$") then
        height = math.floor(vim.o.lines * (tonumber(size:sub(1, -2)) / 100))
    else
        height = tonumber(size) or 10
    end

    -- Split doesn't use row/col/midpoint logic for dynamic resizing
    return split_obj, height, 0, vim.o.columns, 0
end

local function create_vertical()
    local size = vim.g.quickllm_vertical_popup_size or "50%"
    local split_obj = Split({
        relative = "editor",
        position = "right",
        size = size,
    })

    local width = 0
    if type(size) == "string" and size:match("%%$") then
        width = math.floor(vim.o.columns * (tonumber(size:sub(1, -2)) / 100))
    else
        width = tonumber(size) or 40
    end

    return split_obj, vim.o.lines, 0, width, 0
end

local function create_popup()
    -- 1. Resolve window options (wrap, etc.)
    local window_options = vim.deepcopy(vim.g.quickllm_popup_window_options or {})

    -- 2. Resolve base options from user config
    local options = vim.deepcopy(vim.g.quickllm_popup_layout or {
        relative = "editor",
        position = "50%",
        size = { width = "80%", height = "60%" }
    })

    -- 3. Calculate MAX Dimensions
    local lines = vim.o.lines
    local columns = vim.o.columns

    local statusline_h = (vim.o.laststatus > 0) and 1 or 0
    local tabline_h = (vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)) and 1 or 0
    local cmdline_h = vim.o.cmdheight

    local usable_h = math.max(1, lines - statusline_h - tabline_h - cmdline_h - 2)

    local function parse_dim(val, total)
        if type(val) == "string" and val:match("%%$") then
            return math.floor(total * (tonumber(val:sub(1, -2)) / 100))
        end
        return tonumber(val) or val
    end

    local width_raw = options.size and options.size.width or "80%"
    local height_raw = options.size and options.size.height or "60%"

    local max_width = parse_dim(width_raw, columns)
    local max_height = parse_dim(height_raw, usable_h)

    -- Calculate centered position within USABLE area for the MAX height
    local max_row = math.floor((usable_h - max_height) / 2) + tabline_h
    local col = math.floor((columns - max_width) / 2)

    -- Calculate initial row for 1-line height to start centered
    local midpoint = max_row + (max_height / 2)
    local initial_row = math.floor(midpoint - (1 / 2))

    -- 4. Return the element and its max constraints
    local ui_elem = Popup({
        enter = true,
        focusable = true,
        border = { style = vim.g.quickllm_popup_style or "rounded" },
        relative = options.relative or "editor",
        position = {
            row = initial_row,
            col = col,
        },
        size = {
            width = max_width,
            height = 1, -- Start small
        },
        win_options = window_options,
    })

    return ui_elem, max_height, max_row, max_width, col
end

---Syncs the window height to match the buffer content.
function Ui.sync_window_size(ui_bufnr)
    local info = active_popups[ui_bufnr]
    if not info or not info.ui_elem then return end

    -- Dynamic resizing only applies to 'popup' type (not horizontal/vertical splits)
    if vim.g.quickllm_popup_type ~= "popup" then
        return
    end

    -- Calculate visual line count (accounting for wrapping)
    local lines = vim.api.nvim_buf_get_lines(ui_bufnr, 0, -1, false)
    local visual_height = 0
    local available_width = info.max_w

    -- Account for potential border/padding if NUI doesn't subtract them from max_w
    -- Most borders take 2 columns.
    local wrap_width = math.max(1, available_width - 2)

    for _, line in ipairs(lines) do
        -- A line takes at least 1 visual row.
        -- If it's longer than wrap_width, it takes ceil(len / wrap_width) rows.
        -- Note: this is a simple estimation that works well for monospaced fonts.
        local line_len = #line
        if line_len == 0 then
            visual_height = visual_height + 1
        else
            visual_height = visual_height + math.ceil(line_len / wrap_width)
        end
    end

    local new_h = math.min(visual_height, info.max_h)

    if new_h ~= info.current_h then
        -- Calculate the "Start Row" for this specific height so it's centered
        -- relative to the SAME midpoint as the max-height window.
        local midpoint = info.max_row + (info.max_h / 2)
        local centered_row = math.floor(midpoint - (new_h / 2))

        info.ui_elem:update_layout({
            size = { height = new_h, width = info.max_w },
            position = { row = centered_row, col = info.col }
        })
        info.current_h = new_h
    end
end

function Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    -- Close any existing popup for this owner before opening a new one
    Ui.close_active_popup(bufnr)

    local popup_type = vim.g.quickllm_popup_type
    local ui_elem, max_h, max_row, max_w, col

    if popup_type == "horizontal" then
        ui_elem, max_h, max_row, max_w, col = create_horizontal()
    elseif popup_type == "vertical" then
        ui_elem, max_h, max_row, max_w, col = create_vertical()
    else
        ui_elem, max_h, max_row, max_w, col = create_popup()
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
    active_popups[ui_bufnr] = {
        owner = bufnr,
        ui_elem = ui_elem,
        max_h = max_h,
        max_row = max_row,
        max_w = max_w,
        col = col,
        current_h = (popup_type == "popup" and 1 or max_h)
    }

    -- Sync initial size (only for popups)
    if popup_type == "popup" then
        Ui.sync_window_size(ui_bufnr)
    end

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

    -- double escape to quit
    if vim.g.quickllm_quit_with_double_esc then
        local last_esc_time = 0
        ui_elem:map("n", "<esc>", function()
            local now = vim.loop.now()
            if now - last_esc_time < 500 then
                ui_elem:unmount()
            else
                last_esc_time = now
            end
        end, { noremap = true, silent = true })
    end

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
        -- The tracking system handles the history automatically.
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
        Ui.sync_window_size(bufnr)
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
            Ui.sync_window_size(bufnr)
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

    -- Dynamically resize
    Ui.sync_window_size(bufnr)

    -- Auto-scroll if following
    if should_scroll then
        pcall(vim.api.nvim_win_set_cursor, winid, {vim.api.nvim_buf_line_count(bufnr), 0})
    end
end

function Ui.popup(lines, filetype, bufnr, start_row, start_col, end_row, end_col)
    local ui_elem = Ui.create_window(filetype, bufnr, start_row, start_col, end_row, end_col)
    vim.api.nvim_buf_set_lines(ui_elem.bufnr, 0, -1, false, lines)
    Ui.sync_window_size(ui_elem.bufnr)
end

return Ui
