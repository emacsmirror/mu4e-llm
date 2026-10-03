# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-10-03

This release changes how the AI writes, and removes two settings. Read
"Removed" and "Changed" before upgrading.

### Removed

- **BREAKING. `mu4e-llm-draft-persona` and
  `mu4e-llm-draft-persona-descriptions` are gone.** They were four
  adjectives -- "Write in a professional, business-appropriate tone" and
  three like it -- and adjectives tell a model almost nothing. The default
  was `professional`, so every draft got the vaguest of the four whether or
  not the email was business correspondence.

  `mu4e-llm-prompt-voice` replaces them. If you had set a persona, set the
  voice to describe how you write instead; it takes habits rather than
  labels, and one edit changes every email the package writes.

### Changed

- **Finalize replies to the message you drafted from, not the message at
  point.** This is what makes `r` in the summary buffer work. The trade-off:
  the message is a snapshot taken when drafting began, so if you read the
  message in between, maildir renames the file and finalize can fail where it
  previously worked. The draft survives and the error says so.
- **BREAKING. Prompts take named placeholders instead of positional `%s`.**
  A customised prompt written against the old shape will keep its `%s` and
  send it to the model as literal text, with no error. Check any prompt you
  have set. Each prompt's docstring lists the letters it takes: `%t` is the
  thread, `%d` the draft, `%i` the instruction, and so on. A literal percent
  sign is now written `%%`.

  Order no longer matters and an unsupplied letter is left alone, so an edit
  can no longer break the call -- which is also why a stale `%s` passes
  silently.

- **Every prompt moved to `mu4e-llm-prompts.el`.** They were spread through
  `mu4e-llm-config.el` among provider, cache and keybinding settings. There
  is now one file to open.

- **Replies are prose.** The reply prompt used to instruct the model to use
  bullet lists, so every generated reply was a bullet list. Ask for bullets
  with `C-c C-b` when a list reads better.

- **Replies are written in the language of the message being answered.** No
  prompt mentioned language before.

- **Refine, shorten and polite do what their names say.** The refine prompt
  said "keep the same basic structure and points", which contradicted every
  shortening instruction sent through it. It now knows an email has a
  greeting, a body and a sign-off, and applies the instruction to the body:
  "make it one line" means the body, not the whole email.

- **The standard summary has sections**, separated by blank lines, instead of
  one run of bullet points.

### Added

- **The draft buffer is read-only while the model is writing.** It takes focus
  now, and every streamed chunk rewrites the whole draft region, so anything
  typed during generation was silently discarded on the next chunk. Finalizing
  mid-stream also used to hand the compose buffer a truncated reply ending in
  the streaming indicator; it now says so and waits.
- **`mu4e-llm-draft-instructions-label` and `mu4e-llm-draft-recipient-label`**:
  the two short strings the package wraps around your instructions and the
  recipient. They were inline in the code, which made the claim that one file
  holds every prompt untrue.
- **`mu4e-llm-prompt-voice`**: how email written by this package should
  sound. Sent as the system prompt for drafting, composing and refining.
  Summaries and translations do not use it.
- **`C-c C-n` in the draft buffer, plainer**: same meaning, plainer words.
- **`C-c C-b` in the draft buffer, bullets**: turns the body into a list and
  leaves the greeting and sign-off as prose.

### Fixed

- **The signature matched the wrong account.** Fixed in the Emacs
  configuration rather than here, but it affects this package's finalize
  step: the hook that chose the signature ran after org-msg had already
  inserted one, so every compose carried the previous compose's signature.
- **The summary and draft buffers take focus.** They used `display-buffer`,
  which shows a buffer without selecting it.
- **`r` in the summary buffer replies.** It called the drafting command with
  no arguments, which reads the message at point, and a summary buffer has
  none. The message was stored on the buffer the whole time.
- **A reply drafted after an abandoned compose is a reply.** The draft buffer
  is reused and `erase-buffer` does not clear buffer-local state, so the
  compose flag, recipient and subject from an earlier `i n` survived into the
  next draft. Finalizing then sent the reply as a new mail to that earlier
  address, under the wrong account's signature. Longstanding; found while
  reviewing this release.
- **Starting a second draft stops the first.** Both wrote through the same
  buffer marker, so whichever finished last won, and the reply shown could
  belong to a different message than the one the buffer was for. Longstanding;
  the summary buffer's `r` key is a new way to reach it.
- **The window configuration is restored correctly after sending.** Finalize
  now kills the draft buffer after composing rather than before, and mu4e
  snapshots the window configuration in between, so the snapshot named a
  buffer about to be killed.
- **Finalizing a draft no longer destroys it on failure.** It killed the
  draft buffer and then called `mu4e-compose-reply`, which also reads the
  message at point. That worked only when the window behind the draft
  happened to hold a mu4e buffer. It now replies to the stored message, and
  kills the draft only once composing has succeeded.

- **Provider errors are reported, not swallowed**: the streaming error
  callback took one argument where llm.el passes two, so every API failure
  raised `wrong-number-of-arguments` and the real message was never shown.
  The second argument is a message string rather than an error object, so it
  is formatted directly: `error-message-string` would signal on it.
- **`g` in the summary buffer regenerates**: it cleared the cache and printed
  "Please regenerate from the mu4e message view". The message and the summary
  type are now kept in the buffer, so a summary can rerun itself.

### Added

- **`mu4e-llm-operation-models`**: a model and reasoning level per operation,
  so summarising and drafting need not share one model. Keyed by operation
  type (`summary`, `executive-summary`, `translate`, `draft`, `compose`,
  `refine`), with `:model` and `:reasoning` both optional:

  ```elisp
  (setq mu4e-llm-operation-models
        '((summary . (:model "gpt-6-luna"  :reasoning "low"))
          (draft   . (:model "gpt-6.1-sol" :reasoning "medium"))))
  ```

  Defaults to nil and nothing inherits, so an absent operation behaves
  exactly as before. The provider is copied before its model is replaced,
  because the same object is shared with the user's other AI tools.

  The reasoning level is sent as a `reasoning_effort` request parameter, so
  its accepted values are the provider's. llm.el has a `:reasoning` argument
  of its own, but the Open AI provider does not read it: only the Claude,
  Vertex and Ollama providers do.

- **`mu4e-llm-parent-keymap` and `mu4e-llm-parent-keymap-suffix`**: the
  shared-prefix binding used to be derived by matching the prefix against
  `C-c a`, which tied the two together and refused any other prefix shape. A
  single unmodified key now works, which suits mu4e because its buffers are
  modal.

### Changed

- The suffix inside the parent keymap is no longer derived from
  `mu4e-llm-keymap-prefix`. It defaults to `e`, matching the previous
  default. Set `mu4e-llm-parent-keymap-suffix` if you had changed the prefix.
- `mu4e-llm-help` names the prefix actually in use instead of a hardcoded one.

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
