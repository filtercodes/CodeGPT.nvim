--/lua/codegpt/history.lua
-- This module manages the chat history on a per-buffer basis.

local M = {}

-- In-memory store for chat history, keyed by buffer number.
-- Each history is a list of messages.
-- e.g., history[bufnr] = { { role = "user", content = "...", timestamp = 123 }, ... }
local history = {}

---Adds a message to the history for a given buffer.
---Enforces the sliding window to limit history size.
---@param bufnr number: The buffer number.
---@param role string: "user" or "assistant".
---@param content string: The message content.
function M.add_message(bufnr, role, content)
    if not history[bufnr] then
        history[bufnr] = {}
    end

    local message = {
        role = role,
        content = content,
        timestamp = os.time(),
    }
    table.insert(history[bufnr], message)

    -- Enforce max messages (sliding window)
    local max_messages = vim.g.codegpt_chat_history_max_messages or 10
    if #history[bufnr] > max_messages then
        table.remove(history[bufnr], 1)
    end
end

---Retrieves the message history for a buffer, handling timeouts.
---@param bufnr number: The buffer number.
---@return table: A list of messages ready to be sent to the API.
function M.get_messages(bufnr)
    local bufnr_history = history[bufnr]

    if not bufnr_history or #bufnr_history == 0 then
        return {}
    end

    local last_message = bufnr_history[#bufnr_history]
    local current_time = os.time()
    local time_diff = current_time - last_message.timestamp
    local timeout = vim.g.codegpt_chat_history_timeout or 180

    if time_diff > timeout then
        M.clear_history(bufnr)
        -- Notify the user that the history was cleared
        -- print("Chat history cleared due to inactivity (timeout: " .. timeout .. "s)")
        vim.notify("CodeGPT chat history cleared due to inactivity (timeout: " .. timeout .. "s)", vim.log.levels.INFO, { title = "CodeGPT" })
        -- Return empty history
        return {}
    end

    -- History is valid, return it
    local messages_to_send = {}
    for _, msg in ipairs(bufnr_history) do
        -- We only need role and content for the API
        table.insert(messages_to_send, { role = msg.role, content = msg.content })
    end

    return messages_to_send
end

---Clears the history for a given buffer.
---@param bufnr number: The buffer number to clear.
function M.clear_history(bufnr)
    if history[bufnr] then
        history[bufnr] = nil
    end
end

return M
