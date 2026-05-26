local curl = require("plenary.curl")
local Render = require("quickllm.template_render")
local Utils = require("quickllm.utils")
local Api = require("quickllm.api")
local History = require("quickllm.history")

local LocalGroundingProvider = {}

LocalGroundingProvider.has_streaming = true

function LocalGroundingProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    -- We just need the rendered user message.
    -- The actual payload construction for Ollama will happen in make_call after Tavily returns.
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    local thinking = false

    local request = {
        temperature = cmd_opts.temperature,
        model = cmd_opts.model,
        stream = false,
        think = thinking,
    }

    return request, new_user_message_text
end

local function call_tavily(query, cb)
    local api_key = vim.g.quickllm_tavily_api_key or os.getenv("TAVILY_API_KEY")
    if not api_key then
        error("Tavily API Key not found. Set 'quickllm_tavily_api_key' or TAVILY_API_KEY environment variable.")
    end

    local url = "https://api.tavily.com/search"
    local payload = {
        query = query,
        search_depth = "basic",
        max_results = 5,
    }

    curl.post(url, {
        body = vim.fn.json_encode(payload),
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. api_key,
        },
        callback = function(response)
            vim.schedule(function()
                if response.status ~= 200 then
                    local body_str = response.body
                    if type(body_str) == "table" then
                        body_str = table.concat(body_str, "")
                    end
                    cb(nil, "Tavily Error: " .. response.status .. " " .. (body_str or ""))
                    return
                end

                local body = response.body
                if type(body) == "table" then
                    body = table.concat(body, "")
                end

                local ok, json = pcall(vim.json.decode, body)
                if not ok then
                    ok, json = pcall(vim.fn.json_decode, body)
                end

                if not ok or not json then
                    cb(nil, "Error decoding Tavily response: " .. tostring(json))
                    return
                end
                cb(json)
            end)
        end,
        on_error = function(err)
            vim.schedule(function()
                cb(nil, "Tavily Curl Error: " .. tostring(err))
            end)
        end,
    })
end

function LocalGroundingProvider.make_call(payload, user_message_text, cb, bufnr)
    Api.run_started_hook()
    
    -- Call Tavily
    call_tavily(user_message_text, function(tavily_json, err)
        if err then
            if type(cb) == "table" then
                cb.on_error(err)
            else
                print(err)
            end
            Api.run_finished_hook()
            return
        end

        -- Process Tavily Results
        local sources = {}
        local context_text = "SEARCH RESULTS:\n"
        for _, result in ipairs(tavily_json.results or {}) do
            context_text = context_text .. "- " .. result.content .. "\n"
            table.insert(sources, string.format("- %s (%s)", result.title, result.url))
        end

        -- Construct Ollama Prompt
        local past_messages = History.get_messages(bufnr)
        local messages = {}
        
        if vim.g.quickllm_ground_with_history ~= false then
            for _, msg in ipairs(past_messages) do
                table.insert(messages, msg)
            end
        end

        local final_user_content = context_text .. "\nUsing the search results above, answer the following question. If the search results are insufficient to fully answer the question, you must first state that the search results were insufficient, and then answer from your general knowledge.\n\nQuestion:\n" .. user_message_text

        table.insert(messages, {role = "user", content = final_user_content})

        local ollama_payload = vim.deepcopy(payload)
        ollama_payload.messages = messages
        ollama_payload.stream = (type(cb) == "table")

        -- Call Ollama
        local ollama_url = vim.g.quickllm_ollama_url or "http://127.0.0.1:11434/api/chat"
        local ollama_headers = { ["Content-Type"] = "application/json" }

        if type(cb) == "table" then
            -- Streaming Mode
            local payload_str = vim.fn.json_encode(ollama_payload)
            local partial_data = ""
            local full_text = ""

            curl.post(ollama_url, {
                body = payload_str,
                headers = ollama_headers,
                raw = { "--no-buffer" },
                stream = function(stream_err, chunk)
                    if stream_err then
                        vim.schedule(function() cb.on_error(stream_err) end)
                        return
                    end
                    if not chunk then
                        vim.schedule(function()
                            -- Process any remaining data in partial_data
                            if partial_data and partial_data ~= "" then
                                local ok, json = pcall(vim.json.decode, partial_data)
                                if ok and json and json.message and json.message.content then
                                    local text_fragment = json.message.content
                                    full_text = full_text .. text_fragment
                                    cb.on_chunk(text_fragment)
                                end
                            end

                            if #sources > 0 and vim.g.quickllm_show_search_sources then
                                local sources_text = "\n\n**Sources:**\n" .. table.concat(sources, "\n")
                                cb.on_chunk(sources_text)
                            end
                            cb.on_complete(full_text)
                            Api.run_finished_hook()
                        end)
                        return
                    end

                    partial_data = partial_data .. chunk
                    local current_buffer = partial_data
                    local processed_segment_end = 0

                    while true do
                        local json_start_idx = string.find(current_buffer, "{", processed_segment_end + 1, true)
                        if not json_start_idx then break end

                        local brace_level = 0
                        local json_end_idx = -1
                        for i = json_start_idx, #current_buffer do
                            local char = string.sub(current_buffer, i, i)
                            if char == "{" then brace_level = brace_level + 1
                            elseif char == "}" then brace_level = brace_level - 1 end
                            if brace_level == 0 and char == "}" then
                                json_end_idx = i
                                break
                            end
                        end

                        if json_end_idx == -1 then break end

                        local json_str = string.sub(current_buffer, json_start_idx, json_end_idx)
                        processed_segment_end = json_end_idx

                        local ok, json = pcall(vim.json.decode, json_str)
                        if ok and json and json.message then
                            local content = json.message.content
                            if content and content ~= "" then
                                full_text = full_text .. content
                                cb.on_chunk(content)
                            end
                        end
                    end
                    partial_data = string.sub(current_buffer, processed_segment_end + 1)
                end,
                on_error = function(err_msg)
                    cb.on_error(err_msg)
                    Api.run_finished_hook()
                end,
            })
        else
            -- Non-Streaming Mode
            curl.post(ollama_url, {
                body = vim.fn.json_encode(ollama_payload),
                headers = ollama_headers,
                callback = function(response)
                    vim.schedule(function()
                        if response.status ~= 200 then
                            print("Ollama Error: " .. response.status .. " " .. response.body)
                            Api.run_finished_hook()
                            return
                        end
                        local ok, json = pcall(vim.fn.json_decode, response.body)
                        if ok and json and json.message and json.message.content then
                            local response_text = json.message.content
                            if #sources > 0 and vim.g.quickllm_show_search_sources then
                                response_text = response_text .. "\n\n**Sources:**\n" .. table.concat(sources, "\n")
                            end
                            History.add_message(bufnr, "user", user_message_text)
                            History.add_message(bufnr, "assistant", response_text)
                            cb(Utils.parse_lines(response_text))
                        end
                        Api.run_finished_hook()
                    end)
                end,
                on_error = function(err_msg)
                    print("Ollama Curl Error: " .. tostring(err_msg))
                    Api.run_finished_hook()
                end,
            })
        end
    end)
end

return LocalGroundingProvider
