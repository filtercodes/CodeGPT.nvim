local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

AnthropicProvider = {}

AnthropicProvider.has_streaming = true

function AnthropicProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    local past_messages = History.get_messages(bufnr)
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)

    local messages_for_api = {}
    local include_history = true
    if cmd_opts.is_search_command and vim.g["codegpt_ground_with_history"] == false then
        include_history = false
    end

    if include_history then
        for _, msg in ipairs(past_messages) do
            table.insert(messages_for_api, msg)
        end
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    local model = cmd_opts.model
    local max_tokens = cmd_opts.max_tokens or 4096

    -- Default request
    local request = {
        model = model,
        max_tokens = max_tokens,
        system = system_message,
        messages = messages_for_api,
        stream = true,
        temperature = cmd_opts.temperature or 1.0,
    }

    -- Capability detection based on model ID
    local is_sonnet = model:find("sonnet") ~= nil
    local is_search = cmd_opts.is_search_command

    if is_search then
        -- Default Search version
        request.tools = {
            { type = "web_search_20250305", name = "web_search", max_uses = 5 }
        }

        -- Only enable thinking for Sonnet when searching
        if is_sonnet then
            local budget = math.floor((tonumber(max_tokens) or 4096) * 0.5)
            if budget < 1024 then budget = 1024 end
            -- Ensure max_tokens is higher than budget
            if tonumber(max_tokens) < budget + 512 then
                request.max_tokens = budget + 512
            end
            request.thinking = { type = "enabled", budget_tokens = budget }
            request.temperature = 1.0
        end
    end

    return request, new_user_message_text
end

function AnthropicProvider.make_headers(payload)
    local api_key = vim.g["codegpt_anthropic_api_key"] or os.getenv("ANTHROPIC_API_KEY")

    if not api_key then
        error("Anthropic API Key not found.")
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_key,
        ["anthropic-version"] = "2023-06-01",
    }

    -- Consolidate beta headers
    local betas = {}
    if payload.tools then
        for _, t in ipairs(payload.tools) do
            if t.type == "web_search_20260209" then
                table.insert(betas, "code-execution-web-tools-2026-02-09")
                break
            elseif t.type == "web_search_20250305" then
                table.insert(betas, "web-search-2025-03-05")
                break
            end
        end
    end

    -- The thinking beta header is no longer required for Sonnet 4.6

    if #betas > 0 then
        headers["anthropic-beta"] = table.concat(betas, ",")
    end

    return headers
end


function AnthropicProvider.make_call(payload, user_message_text, cb, bufnr)
    local url = "https://api.anthropic.com/v1/messages"
    local headers = AnthropicProvider.make_headers(payload)

    Api.run_started_hook()

    if type(cb) == "table" then
        local payload_str = vim.fn.json_encode(payload)
        local partial_data = ""
        local full_text = ""
        local collected_sources = {}
        local Ui = require("codegpt.ui")

        curl.post(url, {
            body = payload_str,
            headers = headers,
            raw = { "--no-buffer" },
            timeout = 30000,
            stream = function(err, chunk)
                -- DIAGNOSTIC: Print raw chunks directly to the UI
                if chunk then
                    vim.schedule(function()
                        -- vim.notify("RAW CHUNK: " .. tostring(chunk), vim.log.levels.INFO)
                    end)
                end

                if err then
                    vim.schedule(function()
                        vim.notify("Anthropic Curl Error: " .. vim.inspect(err), vim.log.levels.ERROR)
                        cb.on_error(tostring(err))
                        Api.run_finished_hook()
                    end)
                    return
                end
                
                if not chunk then
                    vim.schedule(function()
                        if #collected_sources > 0 and vim.g["codegpt_show_search_sources"] then
                            local sources_text = "\n\n**Sources:**\n" .. table.concat(collected_sources, "\n")
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
                    local data_start_idx = string.find(current_buffer, "data: ", processed_segment_end + 1, true)
                    if not data_start_idx then break end

                    local json_start_idx = data_start_idx + string.len("data: ")

                    -- Find matching braces for JSON
                    local brace_level = 0
                    local json_end_idx = -1
                    -- To avoid failing on literal braces inside strings, we try to use the end of the line if it exists
                    local next_nl = string.find(current_buffer, "\n", json_start_idx, true)
                    if next_nl then
                        json_end_idx = next_nl - 1
                    else
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
                    end

                    if json_end_idx == -1 then break end -- Incomplete JSON

                    local json_str = string.sub(current_buffer, json_start_idx, json_end_idx)
                    processed_segment_end = json_end_idx
 
                    -- Clean up any trailing characters from the line extraction
                    json_str = string.match(json_str, "^%s*(.-)%s*$")

                    if json_str ~= "" and json_str ~= "[DONE]" then
                        local ok, json = pcall(vim.json.decode, json_str)
                        if ok and json then
                            if json.type == "error" then
                                vim.schedule(function()
                                    vim.notify("Anthropic API Error: " .. (json.error.message or vim.inspect(json.error)), vim.log.levels.ERROR)
                                    cb.on_error(json.error.message)
                                end)
                            elseif json.type == "content_block_start" then
                                local block = json.content_block
                                if block and block.type == "web_search_tool_result" and block.content then
                                    for _, result in ipairs(block.content) do
                                        if result.type == "web_search_result" and result.url then
                                            local title = result.title or "Untitled"
                                            table.insert(collected_sources, string.format("- [%s](%s)", title, result.url))
                                        end
                                    end
                                end
                            elseif json.type == "content_block_delta" and json.delta then
                                if json.delta.text then
                                    full_text = full_text .. json.delta.text
                                    cb.on_chunk(json.delta.text)
                                elseif json.delta.type == "text_delta" and json.delta.text then
                                    full_text = full_text .. json.delta.text
                                    cb.on_chunk(json.delta.text)
                                elseif json.delta.type == "thinking_delta" and json.delta.thinking then
                                    full_text = full_text .. json.delta.thinking
                                    cb.on_chunk(json.delta.thinking)
                                elseif json.delta.type == "input_json_delta" and json.delta.partial_json then
                                    -- cb.on_chunk(json.delta.partial_json)
                                    -- Do not stream raw JSON tool queries to the UI.
                                    -- This allows the spinner to continue running until the actual answer starts streaming.
                                end
                            elseif json.type == "content_block_stop" and json.index then
                                -- We check if the previous block was thinking by looking at the last characters.
                                -- The safest way is to just let the text_delta start on a new line if thinking happened.
                                -- Anthropic streams thinking in block 0 (usually), and the actual text in block 1.
                                -- So when a block stops, if it's block 0, we can add some spacing just in case it was thinking.
                                if json.index == 0 and payload.thinking then
                                    full_text = full_text .. "\n\n"
                                    cb.on_chunk("\n\n")
                                end
                            end
                        end
                    end

                    -- Move past trailing newlines and 'event: ...' lines
                    local next_newline = string.find(current_buffer, "\n", processed_segment_end + 1, true)
                    while next_newline do
                        local next_data = string.find(current_buffer, "data: ", processed_segment_end + 1, true)
                        if next_data and next_newline > next_data then break end
                        processed_segment_end = next_newline
                        next_newline = string.find(current_buffer, "\n", processed_segment_end + 1, true)
                    end
                end

                partial_data = string.sub(current_buffer, processed_segment_end + 1)
            end,
            on_error = function(err)
                cb.on_error(tostring(err.message or err))
                Api.run_finished_hook()
            end
        })
    else
        -- Legacy blocking mode
        payload.stream = false
        curl.post(url, {
            body = vim.fn.json_encode(payload),
            headers = headers,
            callback = function(res)
                vim.schedule(function()
                    if res.status ~= 200 then
                        print("Error: " .. res.status .. " " .. res.body)
                    else
                        local ok, json = pcall(vim.fn.json_decode, res.body)
                        if ok and json and json.content then
                            local txt = ""
                            for _, b in ipairs(json.content) do if b.text then txt = txt .. b.text end end
                            History.add_message(bufnr, "user", user_message_text)
                            History.add_message(bufnr, "assistant", txt)
                            cb(Utils.parse_lines(txt))
                        end
                    end
                    Api.run_finished_hook()
                end)
            end
        })
    end
end

return AnthropicProvider
