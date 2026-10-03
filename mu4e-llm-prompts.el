;;; mu4e-llm-prompts.el --- Every prompt mu4e-llm sends -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: MIT

;;; Commentary:

;; This is the one file to edit when you want the AI to write differently.
;; Nothing else in the package holds prompt text.
;;
;; Each prompt takes named placeholders, listed in its docstring: `%t' is the
;; thread, `%d' the current draft, and so on.  Order does not matter, and a
;; placeholder the package does not supply is left alone rather than
;; signalling, so an edit cannot break the call.  Write a literal percent sign
;; as `%%'.

;;; Code:

(require 'format-spec)
(require 'mu4e-llm-config)

;;; --- Rendering ---

(defun mu4e-llm--prompt (template spec)
  "Render TEMPLATE, substituting SPEC.

SPEC is an alist of (CHARACTER . STRING), as `format-spec' takes it.  A
placeholder TEMPLATE uses but SPEC does not supply is left in place rather
than signalling, so a user\\='s edited prompt can never break the call.  The
cost is that a stale placeholder reaches the model as literal text.

Pass an empty string, never nil, for a field that may be absent: nil counts
as missing and would leave the placeholder showing."
  (format-spec template spec 'ignore))

;;; --- Drafting ---

(defcustom mu4e-llm-draft-reply-prompt
  "You are drafting an email reply for %n <%e>.

%p

Based on the email thread below, draft a reply that addresses the key points.
Use org-mode syntax for formatting (this will be used with org-msg):
- Use *bold* for emphasis
- Use /italic/ for subtle emphasis
- Use bullet lists with - for multiple points
- Use [[url][text]] for links

Do NOT include email headers (To, From, Subject) - just the body text.
Do NOT include a signature - that will be added automatically.
Start with an appropriate greeting.

EMAIL THREAD:
%t

%i"
  "Prompt template for generating draft replies.

Placeholders:
  %n  the sender\\='s name
  %e  the sender\\='s email address
  %p  the persona description
  %t  the formatted email thread
  %i  any extra instructions the user gave, or empty"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-refine-prompt
  "Revise the following email draft according to this instruction: %i

Keep the same basic structure and points, but adjust as requested.
Use org-mode syntax for formatting.
Do NOT include email headers or signature.

CURRENT DRAFT:
%d"
  "Prompt template for refining drafts.

Placeholders:
  %i  the refinement instruction
  %d  the current draft text"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-compose-prompt
  "You are composing a new email for %n <%e>.

%p

Write an email based on these instructions: %i

%r

Use org-mode syntax for formatting (this will be used with org-msg):
- Use *bold* for emphasis
- Use /italic/ for subtle emphasis
- Use bullet lists with - for multiple points
- Use [[url][text]] for links

Do NOT include email headers (To, From, Subject) - just the body text.
Do NOT include a signature - that will be added automatically.
Start with an appropriate greeting."
  "Prompt template for composing new emails.

Placeholders:
  %n  the sender\\='s name
  %e  the sender\\='s email address
  %p  the persona description
  %i  what to write about
  %r  a line naming the recipient, or empty"
  :type 'string
  :group 'mu4e-llm)

;;; --- Translation ---

(defcustom mu4e-llm-translate-message-prompt
  "Translate the following email to %l.
Preserve the formatting and structure.
Keep names, email addresses, and technical terms as-is.
Do not add any commentary or notes.

EMAIL:
From: %f
Subject: %u

%b"
  "Prompt template for message translation.

Placeholders:
  %l  the language to translate to
  %f  the sender\\='s name or address
  %u  the subject line
  %b  the message body"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-translate-thread-prompt
  "Translate the following email thread to %l.
Preserve the formatting and structure of each message.
Keep names, email addresses, and technical terms as-is.
Maintain the chronological order and clear separation between messages.
Do not add any commentary or notes.

EMAIL THREAD:
%t"
  "Prompt template for thread translation.

Placeholders:
  %l  the language to translate to
  %t  the formatted email thread"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-translate-text-prompt
  "Translate the following text to %l.
Preserve the formatting.
Do not add any commentary or notes.

TEXT:
%x"
  "Prompt template for text or region translation.

Placeholders:
  %l  the language to translate to
  %x  the text to translate"
  :type 'string
  :group 'mu4e-llm)

;;; --- Summaries ---

(defcustom mu4e-llm-summary-standard-prompt
  "Summarize the following email thread concisely (around 200 words).

Include:
- Main topic and purpose of the discussion
- Key points and decisions made
- Action items or requests (if any)
- Current status or next steps needed

Use bullet points for clarity. Focus on what's most important for someone who needs to quickly understand this thread.

EMAIL THREAD:
%t"
  "Prompt template for standard thread summaries.

Placeholders:
  %t  the formatted email thread"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-summary-executive-prompt
  "Provide a brief executive summary of this email thread in 2-3 sentences.
Focus only on the critical information: what is this about and what action (if any) is needed.

EMAIL THREAD:
%t"
  "Prompt template for executive summaries.

Placeholders:
  %t  the formatted email thread"
  :type 'string
  :group 'mu4e-llm)

(provide 'mu4e-llm-prompts)
;;; mu4e-llm-prompts.el ends here
