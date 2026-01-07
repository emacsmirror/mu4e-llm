# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

mu4e-llm is an Emacs Lisp package providing AI-powered email assistance for mu4e. It integrates LLM providers (OpenAI, Claude, Ollama, etc.) via the llm.el library to enable thread summarization, smart reply drafting, and email translation.

## Build, Test, and Lint Commands

```bash
make all       # Compile and test (default)
make compile   # Byte-compile all source files
make test      # Run ERT unit tests
make lint      # Run checkdoc documentation linting
make clean     # Remove compiled .elc files
```

CI tests against Emacs 28.2, 29.1, and 29.4.

## Architecture

### Module Organization

- **mu4e-llm.el** - Entry point, keymap setup, minor mode, lazy-loading via autoloads
- **mu4e-llm-config.el** - Configuration variables and customization group
- **mu4e-llm-core.el** - Worker lifecycle, LLM interface, provider resolution, TTL-based caching
- **mu4e-llm-thread.el** - Thread extraction, message body cleanup (quote/signature removal)
- **mu4e-llm-summary.el** - Thread summarization with streaming output
- **mu4e-llm-draft.el** - Smart reply generation with persona system and org-mode formatting
- **mu4e-llm-translate.el** - Message and thread translation

### Key Patterns

1. **Async Worker System** - All LLM operations use `mu4e-llm--worker` structs with callbacks and streaming
2. **Lazy Loading** - Feature modules loaded via autoloads on first command use
3. **Provider Agnostic** - Pluggable LLM via llm.el; provider resolved from config or fallback variable
4. **Hook Integration** - Minor mode auto-enables in mu4e-headers and mu4e-view modes

## Emacs Lisp Conventions

- **Lexical Binding** - All files use `lexical-binding: t` header
- **Naming** - Public functions: `mu4e-llm-*`, Internal: `mu4e-llm--*`
- **Forward Declarations** - Use `declare-function` for cross-module calls to avoid compile warnings
- **Error Handling** - Wrap with context using `error`, use `condition-case` for recovery
- **File Headers** - Use triple semicolon sections (;;; ---) with proper docstrings

## Testing

- Framework: ERT in `test/mu4e-llm-test.el`
- Focus on pure functions (body cleanup, cache operations)
- Run single test: `emacs -batch -Q -L . -l test/mu4e-llm-test.el -f ert-run-tests-batch-and-exit`

## Adding New Features

### New Command
1. Add function in appropriate module with docstring
2. Add to `mu4e-llm-map` keymap in mu4e-llm.el
3. Add autoload at bottom of mu4e-llm.el
4. Add tests if pure function

### New Configuration Option
1. Add `defcustom` in mu4e-llm-config.el
2. Reference via `mu4e-llm-<option-name>`

## Important Notes

- Worker callbacks must check `:active` flag to prevent late callbacks after cancellation
- Org-mode syntax in drafts is required for org-msg HTML email compatibility
- Provider can be nil; always check availability before use
- Body cleanup handles multiple quote styles: standard `>`, Gmail "On X wrote:", German/French variants
