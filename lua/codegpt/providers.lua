local OpenAIProvider = require("codegpt.providers.openai")
local AnthropicProvider = require("codegpt.providers.anthropic")
local OllaMaProvider = require("codegpt.providers.ollama")
local GroqProvider = require("codegpt.providers.groq")
local GeminiProvider = require("codegpt.providers.gemini")
local LocalGroundingProvider = require("codegpt.providers.local_grounding")

Providers = {}

function Providers.get_provider(provider_name)
    local provider
    if provider_name then
        provider = vim.fn.tolower(provider_name)
    else
        provider = vim.fn.tolower(vim.g["codegpt_api_provider"] or "openai")
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
