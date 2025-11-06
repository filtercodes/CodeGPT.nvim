local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")
local History = require("codegpt.history")

AnthropicProvider = {}

function AnthropicProvider.make_request(command, cmd_opts, command_args, text_selection, bufnr)
    local past_messages = History.get_messages(bufnr)
    local new_user_message_text = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)
    local messages_for_api = {}
    for _, msg in ipairs(past_messages) do
        table.insert(messages_for_api, msg)
    end
    table.insert(messages_for_api, {role="user", content=new_user_message_text})

    local request = {
        temperature = cmd_opts.temperature or 1.0,
        max_tokens = cmd_opts.max_tokens,
        model = cmd_opts.model,
        system = system_message,
        messages = messages_for_api,
        stream = true,
    }

    return request, new_user_message_text
end

function AnthropicProvider.make_headers()
    local api_key = vim.g["codegpt_anthropic_api_key"] or os.getenv("ANTHROPIC_API_KEY")

    if not api_key then
        error(
            "Anthropic API Key not found, set in vim with 'codegpt_anthropic_api_key' or as the env variable 'ANTHROPIC_API_KEY'"
        )
    end

    return {
        ["Content-Type"] = "application/json",
        ["x-api-key"] = api_key,
        ["anthropic-version"] = "2023-06-01",
    }
end


local function response_handler(user_message_text, cb, bufnr)
  local full_response_text = ""

  return function(err, chunk, response)
    vim.schedule(function()
      if err then
        print("Stream error: " .. err)
        Api.run_finished_hook()
        return
      end

      if response and response.status and response.status ~= 200 then
        if chunk then
          local body = chunk:gsub("%s+", " ")
          print("Error: " .. response.status .. " " .. body)
        else
          print("Error: " .. response.status .. " (No error body received)")
        end
        Api.run_finished_hook()
        return
      end

      if chunk then
        -- Split chunk by lines, because it can contain multiple events
        for s in string.gmatch(chunk, "[^\r\n]+") do
          -- data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}
          if string.match(s, "data:") then
            local json_string = string.gsub(s, "data: ", "")
            local json = vim.fn.json_decode(json_string)
            if json.type == "content_block_delta" then
              full_response_text = full_response_text .. json.delta.text
            elseif json.type == "message_stop" then
              History.add_message(bufnr, "user", user_message_text)
              History.add_message(bufnr, "assistant", full_response_text)
              if vim.g["codegpt_clear_visual_selection"] then
                vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
              end
              cb(Utils.parse_lines(full_response_text))
              Api.run_finished_hook()
            elseif json.type == "error" then
              print("Anthropic API Error: " .. json.error.message)
              Api.run_finished_hook()
            end
          end
        end
      end
    end)
  end
end

function AnthropicProvider.make_call(payload, user_message_text, cb, bufnr)
    local payload_str = vim.fn.json_encode(payload)
    local url = "https://api.anthropic.com/v1/messages"
    local headers = AnthropicProvider.make_headers()
    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        stream = response_handler(user_message_text, cb, bufnr),
        on_error = function(err)
            print('Curl error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return AnthropicProvider
