;;; mu4e-llm-config.el --- Configuration for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

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

(defcustom mu4e-llm-draft-persona 'professional
  "Default persona style for draft replies.
This affects the tone and formality of generated replies."
  :type '(choice (const :tag "Professional" professional)
                 (const :tag "Friendly" friendly)
                 (const :tag "Formal" formal)
                 (const :tag "Concise" concise))
  :group 'mu4e-llm)

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

(defcustom mu4e-llm-keymap-prefix "C-c a e"
  "Prefix key for mu4e-llm commands.
Set to nil to disable automatic keybinding setup.
Users can then bind `mu4e-llm-map' manually.

If set to a string starting with \"C-c a \" and `ai-commands-prefix-map'
is available, only the suffix will be bound under that prefix map."
  :type '(choice (string :tag "Key sequence")
                 (const :tag "Disable automatic keybindings" nil))
  :group 'mu4e-llm)

(provide 'mu4e-llm-config)
;;; mu4e-llm-config.el ends here
