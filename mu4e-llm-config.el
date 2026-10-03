;;; mu4e-llm-config.el --- Configuration for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Customization variables for mu4e-llm.

;;; Code:

(require 'cl-lib)

(defgroup mu4e-llm nil
  "AI-powered email assistance for mu4e."
  :group 'mu4e
  :prefix "mu4e-llm-")

;;; --- LLM Provider Settings ---

(defcustom mu4e-llm-provider nil
  "LLM provider to use for AI operations.
If nil, falls back to the variable specified by
`mu4e-llm-provider-fallback-variable'."
  :type '(choice (const :tag "Use fallback provider" nil)
                 (sexp :tag "LLM provider object"))
  :group 'mu4e-llm)

(defcustom mu4e-llm-provider-fallback-variable nil
  "Variable to check for LLM provider if `mu4e-llm-provider' is nil.
Set to a symbol naming a variable that holds an llm.el provider.
Example: (setq mu4e-llm-provider-fallback-variable \\='my/llm-current-provider)"
  :type '(choice (const :tag "No fallback" nil)
                 (symbol :tag "Variable name"))
  :group 'mu4e-llm)

(defcustom mu4e-llm-temperature 0.7
  "Temperature for LLM responses.
Lower values (0.0-0.5) produce more focused, deterministic output.
Higher values (0.7-1.0) produce more creative, varied output."
  :type 'number
  :group 'mu4e-llm)

(defcustom mu4e-llm-max-tokens 2048
  "Maximum tokens for LLM responses."
  :type 'integer
  :group 'mu4e-llm)

;;; --- Thread Extraction Settings ---

(defcustom mu4e-llm-max-thread-messages 20
  "Maximum number of messages to include in thread context.
Older messages are truncated to fit this limit."
  :type 'integer
  :group 'mu4e-llm)

(defcustom mu4e-llm-max-message-length 4000
  "Maximum characters per message body in thread context.
Longer messages are truncated with ellipsis."
  :type 'integer
  :group 'mu4e-llm)

;;; --- Caching Settings ---

(defcustom mu4e-llm-operation-models nil
  "Model and reasoning level per operation, overriding the provider.

An alist keyed by operation type.  The types are `summary',
`executive-summary', `translate', `draft', `compose' and `refine'.
Each value is a plist accepting `:model' and `:reasoning', both
optional:

  \='((summary   . (:model \"gpt-6-luna\"  :reasoning \"low\"))
    (draft     . (:model \"gpt-6.1-sol\" :reasoning \"medium\")))

An operation absent from this table uses the provider as resolved by
`mu4e-llm-provider' and `mu4e-llm-provider-fallback-variable', so the
default of nil leaves every operation unchanged.  Nothing inherits:
list each operation you want to pin.

`:reasoning' is sent to the provider as a `reasoning_effort' request
parameter, so its accepted values are the provider's, not llm.el's.
llm.el has a `:reasoning' argument of its own, but the Open AI provider
does not read it, which is why this goes through a request parameter
instead."
  :type '(alist :key-type symbol :value-type plist)
  :group 'mu4e-llm)

(defcustom mu4e-llm-cache-summaries t
  "Whether to cache thread summaries.
Summaries are cached by thread-id and message count."
  :type 'boolean
  :group 'mu4e-llm)

(defcustom mu4e-llm-cache-ttl 3600
  "Time-to-live for cached summaries in seconds.
Default is 1 hour (3600 seconds)."
  :type 'integer
  :group 'mu4e-llm)

;;; --- Draft Settings ---

(defcustom mu4e-llm-draft-include-summary t
  "Whether to include thread summary in draft buffer."
  :type 'boolean
  :group 'mu4e-llm)

;;; --- Translation Settings ---

(defcustom mu4e-llm-languages
  '(("English" . "en")
    ("German" . "de")
    ("French" . "fr")
    ("Spanish" . "es")
    ("Japanese" . "ja")
    ("Chinese" . "zh"))
  "Available languages for translation.
Alist of (DISPLAY-NAME . CODE) pairs."
  :type '(alist :key-type string :value-type string)
  :group 'mu4e-llm)

(defcustom mu4e-llm-default-target-language "en"
  "Default target language for translation."
  :type 'string
  :group 'mu4e-llm)

;;; --- UI Settings ---

(defcustom mu4e-llm-summary-buffer-name "*mu4e-llm-summary*"
  "Name of the summary display buffer."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-buffer-name "*mu4e-llm-draft*"
  "Name of the draft composition buffer."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-streaming-indicator "..."
  "Indicator shown while LLM is streaming response."
  :type 'string
  :group 'mu4e-llm)

;;; --- Keybinding Settings ---

(defcustom mu4e-llm-parent-keymap 'ai-commands-prefix-map
  "Symbol naming a prefix keymap to hang the commands under, or nil.
When the symbol is bound to a keymap, `mu4e-llm-map' is bound inside it
at `mu4e-llm-parent-keymap-suffix'.  When it is nil or unbound, only
`mu4e-llm-keymap-prefix' is bound and nothing else is required."
  :type '(choice (const :tag "None" nil) symbol)
  :group 'mu4e-llm)

(defcustom mu4e-llm-parent-keymap-suffix "e"
  "Key for `mu4e-llm-map' inside `mu4e-llm-parent-keymap'."
  :type '(choice (const :tag "None" nil) string)
  :group 'mu4e-llm)

(defcustom mu4e-llm-keymap-prefix "C-c a e"
  "Prefix key for mu4e-llm commands in mu4e buffers.
Set to nil to disable automatic keybinding setup.
Users can then bind `mu4e-llm-map' manually.

Any key description works, including a single unmodified key such as
\"i\", which is useful because the mu4e buffers are modal.  Binding
under a shared prefix map is separate; see `mu4e-llm-parent-keymap'."
  :type '(choice (string :tag "Key sequence")
                 (const :tag "Disable automatic keybindings" nil))
  :group 'mu4e-llm)

(provide 'mu4e-llm-config)
;;; mu4e-llm-config.el ends here
