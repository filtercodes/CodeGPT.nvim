local curl = require("plenary.curl")
local Render = require("quickllm.template_render")
local Utils = require("quickllm.utils")
local Api = require("quickllm.api")
local History = require("quickllm.history")
local Ui = require("quickllm.ui")

OllaMaProvider = {}


function OllaMaProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    -- Get the history of past messages
    local past_messages = History.get_messages(bufnr)

    -- Render the new user message
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    -- Render the system message
    local system_message_text = Render.render(command, cmd_opts.system_message_template, command_args, text_selection, cmd_opts)

    -- Construct the payload for the request
    local messages_for_api = {}
    if system_message_text and system_message_text ~= "" then
        table.insert(messages_for_api, {role="system", content=system_message_text})
    end
    for _, msg in ipairs(past_messages) do
        table.insert(messages_for_api, msg)
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    -- Request object
    local request = {
        model = cmd_opts.model,
        messages = messages_for_api,
        stream = false,
        think = cmd_opts.thinking,
    }

    if cmd_opts.temperature then
        request.temperature = cmd_opts.temperature
    end

    return request, new_user_message_text
end

function OllaMaProvider.make_headers()
    return { ["Content-Type"] = "application/json" }
end

function OllaMaProvider.handle_response(json, user_message_text, cb, bufnr)
    if json == nil then
        vim.notify("Ollama Error: Response empty", vim.log.levels.ERROR)
    elseif json.error then
        Ui.popup(vim.split(vim.inspect(json), "\n"), "lua", bufnr)
    elseif json.done == nil or json.done == false then
        print("Response is incomplete " .. vim.fn.json_encode(json))
    elseif json.message == nil or json.message.content == nil then
        print("Error: No response content. Full response: " .. vim.fn.json_encode(json))
    else
        local response_text = json.message.content

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
            else
                -- Add both user and assistant messages to history at the same time
                History.add_message(bufnr, "user", user_message_text)
                History.add_message(bufnr, "assistant", response_text)

                if vim.g.quickllm_clear_visual_selection and vim.api.nvim_buf_is_valid(bufnr) then
                    vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                    vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                end
                cb(Utils.parse_lines(response_text))
            end
        else
            print("Error: No text")
        end
    end
end

local function curl_callback(response, user_message_text, cb, bufnr)
    local status = response.status
    local body = response.body
    if status ~= 200 then
        body = body:gsub("%s+", " ")
        print("Error: " .. status .. " " .. body)
        return
    end

    if body == nil or body == "" then
        print("Error: No body")
        return
    end

    vim.schedule_wrap(function(msg)
        local json = vim.fn.json_decode(msg)
        OllaMaProvider.handle_response(json, user_message_text, cb, bufnr)
    end)(body)

    Api.run_finished_hook()
end

OllaMaProvider.has_streaming = true

function OllaMaProvider.make_call(payload, user_message_text, cb, bufnr)
    local url = vim.g.quickllm_ollama_url or "http://127.0.0.1:11434/api/chat"
    local headers = OllaMaProvider.make_headers()
    Api.run_started_hook()

    if type(cb) == "table" then
        -- Streaming Mode
        payload.stream = true
        local payload_str = vim.fn.json_encode(payload)
        
        local partial_data = ""
        local full_text = ""
        -- State machine for thinking blocks
        local is_currently_thinking = false
        -- Tag Buffer: Catch <think> and </think> even if split across chunks
        local tag_buffer = ""

        curl.post(url, {
            body = payload_str,
            headers = headers,
            raw = { "--no-buffer" },
            stream = function(err, chunk)
                if err then
                    vim.schedule(function() 
                        cb.on_error(err) 
                        Api.run_finished_hook()
                    end)
                    return
                end
                
                if not chunk then 
                     -- End of stream: Handle any remaining tag buffer
                     vim.schedule(function()
                        if tag_buffer ~= "" then
                            cb.on_chunk(tag_buffer, is_currently_thinking)
                        end
                        cb.on_complete(full_text)
                        Api.run_finished_hook()
                    end)
                    return 
                end

                -- Process synchronously (off-main-thread)
                partial_data = partial_data .. chunk
                
                local current_buffer = partial_data
                local processed_segment_end = 0

                while true do
                    -- Find the start of a JSON object
                    local json_start_idx = string.find(current_buffer, "{", processed_segment_end + 1, true)
                    
                    if not json_start_idx then break end

                    -- Find the matching '}' for the JSON object
                    local brace_level = 0
                    local json_end_idx = -1
                    for i = json_start_idx, #current_buffer do
                        local char = string.sub(current_buffer, i, i)
                        if char == "{" then
                            brace_level = brace_level + 1
                        elseif char == "}" then
                            brace_level = brace_level - 1
                        end
                        if brace_level == 0 and char == "}" then
                            json_end_idx = i
                            break
                        end
                    end

                    if json_end_idx == -1 then break end

                    local json_str = string.sub(current_buffer, json_start_idx, json_end_idx)
                    processed_segment_end = json_end_idx

                    local ok, json = pcall(vim.json.decode, json_str)
                    if ok and json then
                        -- Handle Ollama API errors in the stream
                        if json.error then
                            vim.schedule(function()
                                -- Show full JSON error in a popup for transparency
                                Ui.popup(vim.split(vim.inspect(json), "\n"), "lua", bufnr)
                                cb.on_error(json.error)
                                Api.run_finished_hook()
                            end)
                            return
                        end

                        -- DEBUG: Show the raw JSON in a popup if enabled
                        if vim.g.quickllm_debug_json then
                            vim.schedule(function()
                                Ui.popup(vim.split(vim.inspect(json), "\n"), "lua", bufnr)
                            end)
                            -- Disable after first chunk to avoid popup spam, 
                            -- but you can re-enable it in init.lua for each test.
                            vim.g.quickllm_debug_json = false 
                        end

                        if json.message then
                            -- Handle dedicated thinking fields (used by models like Qwen)
                            local thinking = json.message.thinking or json.message.reasoning_content
                            if thinking and thinking ~= "" then
                                cb.on_chunk(thinking, true)
                            end

                            local content = json.message.content
                            if content and content ~= "" then
                                -- Append new content to our tag-aware buffer
                                tag_buffer = tag_buffer .. content

                                -- Look for <think> and </think> tags
                                -- We use a simple but robust check that works for split tokens
                                while tag_buffer ~= "" do
                                    if not is_currently_thinking then
                                        local start_idx = tag_buffer:find("<think>")
                                        if start_idx then
                                            -- Text before the tag is regular answer
                                            local before = tag_buffer:sub(1, start_idx - 1)
                                            if before ~= "" then
                                                full_text = full_text .. before
                                                cb.on_chunk(before, false)
                                            end
                                            is_currently_thinking = true
                                            tag_buffer = tag_buffer:sub(start_idx + 7)
                                        else
                                            -- No start tag found.
                                            -- If the buffer ends with a partial tag (e.g. "<thi"),
                                            -- we keep it. Otherwise, flush it as answer.
                                            local partial_match = false
                                            for len = 6, 1, -1 do
                                                if tag_buffer:sub(-len) == ("<think>"):sub(1, len) then
                                                    local flush_len = #tag_buffer - len
                                                    if flush_len > 0 then
                                                        local to_flush = tag_buffer:sub(1, flush_len)
                                                        full_text = full_text .. to_flush
                                                        cb.on_chunk(to_flush, false)
                                                        tag_buffer = tag_buffer:sub(flush_len + 1)
                                                    end
                                                    partial_match = true
                                                    break
                                                end
                                            end

                                            if not partial_match then
                                                full_text = full_text .. tag_buffer
                                                cb.on_chunk(tag_buffer, false)
                                                tag_buffer = ""
                                            else
                                                break -- Wait for more data
                                            end
                                        end
                                    else
                                        -- Currently thinking, look for </think>
                                        local end_idx = tag_buffer:find("</think>")
                                        if end_idx then
                                            -- Text before the tag is thought
                                            local thought = tag_buffer:sub(1, end_idx - 1)
                                            if thought ~= "" then
                                                cb.on_chunk(thought, true)
                                            end
                                            is_currently_thinking = false
                                            tag_buffer = tag_buffer:sub(end_idx + 8)
                                        else
                                            -- Look for partial end tag
                                            local partial_match = false
                                            for len = 7, 1, -1 do
                                                if tag_buffer:sub(-len) == ("</think>"):sub(1, len) then
                                                    local flush_len = #tag_buffer - len
                                                    if flush_len > 0 then
                                                        local to_flush = tag_buffer:sub(1, flush_len)
                                                        cb.on_chunk(to_flush, true)
                                                        tag_buffer = tag_buffer:sub(flush_len + 1)
                                                    end
                                                    partial_match = true
                                                    break
                                                end
                                            end

                                            if not partial_match then
                                                cb.on_chunk(tag_buffer, true)
                                                tag_buffer = ""
                                            else
                                                break
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                partial_data = string.sub(current_buffer, processed_segment_end + 1)
            end,
            on_error = function(err)
                print('Curl error:', err.message)
                cb.on_error(err.message)
                Api.run_finished_hook()
            end,
        })
    else
        -- Legacy / Blocking Mode
        payload.stream = false
        local payload_str = vim.fn.json_encode(payload)
        curl.post(url, {
            body = payload_str,
            headers = headers,
            callback = function(response)
                curl_callback(response, user_message_text, cb, bufnr)
            end,
            on_error = function(err)
                print('Curl error:', err.message)
                Api.run_finished_hook()
            end,
        })
    end
end

return OllaMaProvider
