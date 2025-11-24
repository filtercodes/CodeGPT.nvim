--/lua/codegpt/history.lua
-- This module manages the chat history on a per-buffer basis.

local M = {}

-- In-memory store for chat history, keyed by buffer number.
-- Each history is a list of messages.
-- e.g., history[bufnr] = { { role = "user", content = "...", timestamp = 123 }, ... }
local history = {}

-- Lock to track if summarization is in progress for a buffer
local is_summarizing = {}

---Adds a message to the history for a given buffer.
---Triggers summarization if history exceeds limit.
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

    local max_messages = vim.g.codegpt_chat_history_max_messages or 20

    -- Check if we need to summarize
    if #history[bufnr] > max_messages then
        if not is_summarizing[bufnr] then
            M.summarize_history(bufnr)
        end

        -- Safety cap: If summarization is slow/failing, don't let history grow indefinitely.
        -- Keep a buffer of roughly 2x the max before hard deleting.
        if #history[bufnr] > (max_messages * 2) then
            table.remove(history[bufnr], 1)
        end
    end
end

---Retrieves the message history for a buffer, handling granular timeouts.
---@param bufnr number: The buffer number.
---@return table: A list of messages ready to be sent to the API.
function M.get_messages(bufnr)
    local bufnr_history = history[bufnr]

    if not bufnr_history or #bufnr_history == 0 then
        return {}
    end

    local time_based_expiry = true
    if vim.g.codegpt_chat_history_time_based_expiry ~= nil then
        time_based_expiry = vim.g.codegpt_chat_history_time_based_expiry
    end

    local current_time = os.time()
    local timeout = vim.g.codegpt_chat_history_timeout or 900
    
    local valid_history = {}
    local expired_count = 0

    if time_based_expiry then
        -- Granular expiry: Keep only messages within the timeout window
        for _, msg in ipairs(bufnr_history) do
            if (current_time - msg.timestamp) <= timeout then
                table.insert(valid_history, msg)
            else
                expired_count = expired_count + 1
            end
        end
        
        -- Update the internal history with filtered list
        history[bufnr] = valid_history
        bufnr_history = valid_history -- update local ref for return loop below

        if expired_count > 0 and #valid_history == 0 then
             -- vim.notify("CodeGPT chat history cleared due to inactivity.", vim.log.levels.INFO, { title = "CodeGPT" })
             return {}
        end
    end

    -- Return messages in API format
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
    is_summarizing[bufnr] = false
end

---Applies the summary to the history.
---@param bufnr
---@param summary_text string
function M.apply_summary(bufnr, summary_text)
    local msgs = history[bufnr]
    if not msgs or #msgs < 10 then return end
    
    -- Inherit timestamp from the last message being summarized (the 10th one)
    -- This ensures the summary expires when that block would have expired.
    local tenth_msg = msgs[10]
    
    local summary_msg = {
        role = "system", -- System role implies context/instruction
        content = "Summary of previous conversation:\n" .. summary_text,
        timestamp = tenth_msg.timestamp,
        is_summary = true
    }
    
    -- Remove the first 10 messages
    for _ = 1, 10 do
        table.remove(msgs, 1)
    end
    
    -- Insert summary at the beginning
    table.insert(msgs, 1, summary_msg)
    
    -- vim.notify("CodeGPT: History summarized.", vim.log.levels.INFO, { title = "CodeGPT" })
end

---Initiates background summarization of the first 10 messages.
---@param bufnr number
function M.summarize_history(bufnr)
    is_summarizing[bufnr] = true
    
    -- Lazy require to avoid circular dependency
    local Providers = require("codegpt.providers")
    local CommandsList = require("codegpt.commands_list")
    
    local msgs = history[bufnr]
    if not msgs or #msgs < 10 then
        is_summarizing[bufnr] = false
        return
    end
    
    -- Prepare text to summarize
    local text_block = ""
    for i = 1, 10 do
        local msg = msgs[i]
        text_block = text_block .. string.upper(msg.role) .. ": " .. msg.content .. "\n\n"
    end
    
    local prompt = "Summarize the following conversation flow to retain key context. Keep it concise."
    local full_request_text = prompt .. "\n\nConversation:\n" .. text_block
    
    -- Use a dummy buffer ID (-1) to prevent `make_request` from fetching existing history
    -- and `make_call` (via handle_response) from polluting the real history.
    local dummy_bufnr = -1
    local provider = Providers.get_provider()
    local opts = CommandsList.get_cmd_opts("chat")
    
    if not opts then
         -- Should not happen if chat command exists, but safe guard
        is_summarizing[bufnr] = false
        return
    end
    
    -- Construct request
    -- We pass full_request_text as command_args. 
    -- 'chat' command usually takes command_args as the prompt.
    -- text_selection is empty string.
    local request, user_msg = provider.make_request("chat", opts, full_request_text, "", dummy_bufnr)
    
    local callback = function(lines)
        if lines and #lines > 0 then
            local summary = table.concat(lines, "\n")
            -- Schedule update on main loop
            vim.schedule(function()
                M.apply_summary(bufnr, summary)
                -- Cleanup dummy history if any was created
                M.clear_history(dummy_bufnr)
            end)
        end
        is_summarizing[bufnr] = false
    end
    
    -- Execute
    provider.make_call(request, user_msg, callback, dummy_bufnr)
end

return M
