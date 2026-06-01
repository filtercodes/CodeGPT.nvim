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

local function get_code_block(text)
    local ok, parser = pcall(vim.treesitter.get_string_parser, text, "markdown")
    if not ok or not parser then return nil end

    local tree = parser:parse()[1]
    local root = tree:root()

    -- Query for fenced code blocks and their content
    local query = vim.treesitter.query.parse("markdown", "(fenced_code_block (code_fence_content) @code)")
    local code_contents = {}

    for _, node, _ in query:iter_captures(root, text, 0, -1) do
        local content = vim.treesitter.get_node_text(node, text)
        for _, line in ipairs(vim.split(content, "\n")) do
            table.insert(code_contents, line)
        end
        -- Return the first valid code block content found
        if #code_contents > 0 then
            return code_contents
        end
    end

    return nil
end

function Utils.trim_to_code_block(lines)
    local text = table.concat(lines, "\n")
    local code = get_code_block(text)
    if code then
        return code
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

---Removes <think> tags and their content from a string (handles multi-line and multiple blocks).
---@param text string
---@return string
function Utils.strip_thinking_tags(text)
    if not text then return "" end

    local result = ""
    local last_pos = 1

    while true do
        local start_idx = text:find("<think>", last_pos, true)
        if not start_idx then
            result = result .. text:sub(last_pos)
            break
        end

        result = result .. text:sub(last_pos, start_idx - 1)

        local end_idx = text:find("</think>", start_idx + 7, true)
        if not end_idx then
            -- Orphaned start tag: we skip the rest as it's likely a thinking block in progress
            break
        end

        last_pos = end_idx + 8
    end

    -- Cleanup remaining orphaned end tags (safety)
    result = result:gsub("</think>", "")

    -- Trim leading and trailing whitespace/newlines
    return result:match("^%s*(.-)%s*$") or ""
end


return Utils
