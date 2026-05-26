local OpenAIProvider = require("quickllm.providers.openai")
local AnthropicProvider = require("quickllm.providers.anthropic")
local OllaMaProvider = require("quickllm.providers.ollama")
local GroqProvider = require("quickllm.providers.groq")
local GeminiProvider = require("quickllm.providers.gemini")
local LocalGroundingProvider = require("quickllm.providers.local_grounding")

local Providers = {}

function Providers.get_provider(overrides)
    local provider_name = (overrides and (overrides.search_provider or overrides.provider))
    local provider
    if provider_name then
        provider = vim.fn.tolower(provider_name)
    else
        provider = vim.fn.tolower(vim.g.quickllm_api_provider or "openai")
    end

    if provider == "openai" then
        return OpenAIProvider
    elseif provider == "anthropic" then
        return AnthropicProvider
    elseif provider == "ollama" then
        return OllaMaProvider
    elseif provider == "groq" then
        return GroqProvider
    elseif provider == "gemini" then
        return GeminiProvider
    elseif provider == "local_grounding" then
        return LocalGroundingProvider
    else
        error("Provider not found: " .. provider)
    end
end

return Providers
