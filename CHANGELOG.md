# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-01

### Added

- **Thread Summarization**: Generate detailed or executive summaries of email threads
  - `mu4e-llm-summarize` - Full thread summary with key points
  - `mu4e-llm-summarize-executive` - Brief 2-3 sentence summary
  - Summary caching with configurable TTL

- **Smart Reply Drafting**: AI-powered email reply generation
  - `mu4e-llm-draft-reply` - Context-aware reply drafts
  - `mu4e-llm-draft-compose` - Compose new emails with AI
  - Iterative refinement: shorten, make polite, custom instructions
  - org-msg integration for styled HTML emails

- **Translation**: Translate messages and threads
  - `mu4e-llm-translate-message` - Translate current message
  - `mu4e-llm-translate-thread` - Translate entire thread
  - `mu4e-llm-translate-region` - Translate selected text
  - Configurable target languages

- **Provider Agnostic**: Works with any llm.el provider
  - OpenAI, Claude, Gemini, Ollama support
  - Streaming responses with progress indicators
  - Configurable temperature and max tokens

- **Customizable Keybindings**:
  - Default prefix: `C-c a e`
  - Integrates with `ai-commands-prefix-map` when available
  - Configurable via `mu4e-llm-keymap-prefix`

### Configuration Options

- `mu4e-llm-provider` - LLM provider instance
- `mu4e-llm-temperature` - Response creativity (0.0-1.0)
- `mu4e-llm-max-tokens` - Maximum response length
- `mu4e-llm-max-thread-messages` - Thread extraction limit
- `mu4e-llm-cache-summaries` - Enable summary caching
- `mu4e-llm-draft-persona` - Default reply style
- `mu4e-llm-languages` - Available translation languages
