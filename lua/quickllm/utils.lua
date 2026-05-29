Utils = {}

function Utils.get_filetype()
    local bufnr = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_option(bufnr, "filetype")
end

function Utils.get_visual_selection()
    local bufnr = vim.api.nvim_get_current_buf()

    local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
    local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")

    if start_pos[1] == end_pos[1] and start_pos[2] == end_pos[2] then
        return 0, 0, 0, 0
    end

    local start_row = start_pos[1] - 1
    local start_col = start_pos[2]

    local end_row = end_pos[1] - 1
    local end_col = end_pos[2] + 1

    if vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1] == nil then
        return 0, 0, 0, 0
    end

    local start_line_length = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1]:len()
    start_col = math.min(start_col, start_line_length)

    local end_line_length = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]:len()
    end_col = math.min(end_col, end_line_length)

    return start_row, start_col, end_row, end_col
end

function Utils.get_selected_lines()
    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
    local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
    return table.concat(lines, "\n")
end

function Utils.insert_lines(lines)
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, line, line, false, lines)
    vim.api.nvim_win_set_cursor(0, { line + #lines, 0 })
end

function Utils.replace_lines(lines, bufnr, start_row, start_col, end_row, end_col)
    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
end

local function get_code_block(lines2)
    local code_block = {}
    local in_code_block = false
    for _, line in ipairs(lines2) do
        if line:match("^```") then
            in_code_block = not in_code_block
        elseif in_code_block then
            table.insert(code_block, line)
        end
    end
    return code_block
end

local function contains_code_block(lines2)
    for _, line in ipairs(lines2) do
        if line:match("^```") then
            return true
        end
    end
    return false
end

function Utils.trim_to_code_block(lines)
    if contains_code_block(lines) then
        return get_code_block(lines)
    end
    return lines
end

function Utils.parse_lines(response_text)
    if vim.g.quickllm_write_response_to_err_log then
        vim.api.nvim_err_write("Response: \n" .. response_text .. "\n")
    end

    return vim.fn.split(vim.trim(response_text), "\n")
end

function Utils.fix_indentation(bufnr, start_row, end_row, new_lines)
    local original_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, true)
    local min_indentation = math.huge
    local original_identation = ""

    -- Find the minimum indentation of any line in original_lines
    for _, line in ipairs(original_lines) do
        local indentation = string.match(line, "^%s*")
        if #indentation < min_indentation then
            min_indentation = #indentation
            original_identation = indentation
        end
    end

    -- Change the existing lines in new_lines by adding the old identation
    for i, line in ipairs(new_lines) do
        new_lines[i] = original_identation .. line
    end
end

function Utils.get_accurate_tokens(content)
    local ok, result = pcall(
        vim.api.nvim_exec2,
        string.format([[
python3 << EOF
import tiktoken
encoder = tiktoken.get_encoding("cl100k_base")
encoded = encoder.encode("""%s""")
print(len(encoded))
EOF
]], content), true)
    if ok and #result > 0 then
        return ok, tonumber(result)
    end
    return ok, 0
end


function Utils.remove_trailing_whitespace(lines)
    for i, line in ipairs(lines) do
        lines[i] = line:gsub("%s+$", "")
    end
    return lines
end


function Utils.adjust_popup_size(delta_w, delta_h)
    local layout = vim.deepcopy(vim.g.quickllm_popup_layout or {
        relative = "editor",
        position = "50%",
        size = { width = "80%", height = "60%" }
    })

    -- Ensure size table exists
    layout.size = layout.size or { width = "80%", height = "60%" }

    -- Helper to extract number from "80%" or 80
    local function to_num(val, default)
        if type(val) == "string" then
            return tonumber(val:match("%d+")) or default
        end
        return tonumber(val) or default
    end

    local w = to_num(layout.size.width, 80)
    local h = to_num(layout.size.height, 60)

    -- Calculate and clamp (10% to 100%)
    local new_w = math.max(10, math.min(100, w + (delta_w or 0)))
    local new_h = math.max(10, math.min(100, h + (delta_h or 0)))

    -- Apply new values back as strings
    layout.size.width = new_w .. "%"
    layout.size.height = new_h .. "%"
    
    vim.g.quickllm_popup_layout = layout
    vim.notify(string.format("QuickLLM Window Size: %d%% x %d%%", new_w, new_h), vim.log.levels.INFO, { title = "QuickLLM" })
end


return Utils
