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
;; It has two parts.
;;
;; The voice.  `mu4e-llm-prompt-voice' says how your email should sound.  It
;; goes to the model as the system prompt for the three operations that write
;; email -- drafting a reply, composing a new message, and refining a draft --
;; so changing it changes all of them at once.  Summaries and translations do
;; not use it.
;;
;; The task prompts.  One per operation, saying what to do rather than how to
;; sound.  Each takes named placeholders, listed in its docstring: `%t' is the
;; thread, `%d' the current draft, and so on.  Order does not matter, and a
;; placeholder the package does not supply is left alone rather than
;; signalling, so an edit cannot break the call.  Write a literal percent sign
;; as `%%'.

;;; Code:

(require 'format-spec)
(require 'mu4e-llm-config)

;;; --- The voice ---

(defcustom mu4e-llm-prompt-voice
  "You are writing an email on behalf of the sender, in their own voice.

Language: write in the same language as the message you are answering.  When
starting a new message rather than replying, write in the language of the
instructions you were given.

How to write:
- Short sentences.  One idea per sentence.
- Plain words.  If a shorter word means the same thing, use it.
- Warm and direct, the way a good colleague writes.  Friendly, not chummy.
- Contractions are fine.
- Say the thing.  Do not restate the question before answering it.
- Continuous prose, not a list, unless you are asked for a list.

Never write any of these:
- \"I hope this email finds you well\", or any other opening remark about how
  the reader is doing.
- \"I wanted to reach out\", \"Just circling back\", \"Per my last email\".
- \"Certainly!\", \"Of course!\", \"Great question!\".
- A closing paragraph whose only content is an offer of further help.
- Praise for the other person's message.

Return only the email body.  No preamble, no commentary on what you wrote, no
code fences, no subject line, no signature."
  "How email written by this package should sound.

Sent as the system prompt for drafting, composing and refining.  This is
the one place to change the tone of every email the package writes.
Summaries and translations do not use it."
  :type 'string
  :group 'mu4e-llm)

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
  "Draft a reply to the email thread below, for %n <%e>.

Answer the points that are actually addressed to the sender.  Leave out
anything the thread has already settled.

The reply is written in org-mode syntax, because it is sent as HTML:
- *bold* for emphasis
- /italic/ for light emphasis
- [[url][text]] for links

Do NOT include email headers (To, From, Subject) - just the body text.
Do NOT include a signature - that will be added automatically.
Start with an appropriate greeting.

EMAIL THREAD:
%t

%i"
  "Prompt template for generating draft replies.

How the reply should sound is not here; that is `mu4e-llm-prompt-voice',
which is sent as the system prompt.

Placeholders:
  %n  the sender\\='s name
  %e  the sender\\='s email address
  %t  the formatted email thread
  %i  any extra instructions the user gave, or empty"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-refine-prompt
  "Revise the email draft below. The instruction is: %i

An email has three parts: the greeting, the body, and the sign-off. Apply
the instruction to the body. Leave the greeting and the sign-off as they
are, unless the instruction asks for them by name. \"Make it one line\"
means the body becomes one line, not that the whole email collapses into
one line.

Change what the instruction asks for and nothing else. Do not rewrite
sentences you were not asked to touch.

Keep org-mode syntax. No email headers, no signature.

CURRENT DRAFT:
%d"
  "Prompt template for refining drafts.

Placeholders:
  %i  the refinement instruction
  %d  the current draft text

The instruction is one of `mu4e-llm-draft-shorten-instruction' and its
siblings below, or whatever the user typed."
  :type 'string
  :group 'mu4e-llm)

;;; --- Refinement instructions ---
;;
;; Each is handed to `mu4e-llm-draft-refine-prompt' as its %i, so each
;; inherits the rule about leaving the greeting and the sign-off alone.

(defcustom mu4e-llm-draft-shorten-instruction
  "Cut this down. Remove whole sentences that carry no information, not
just words. Keep every fact, request, question and commitment. Where two
sentences say the same thing, keep the clearer one. Do not make the tone
clipped or abrupt in the process."
  "What the shorten key asks for."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-polite-instruction
  "Make this warmer without making it longer. Soften anything that reads
as blunt or demanding: turn bare instructions into requests, and
acknowledge whatever the other person is being asked to do. Do not add
flattery, do not add an opening pleasantry, and do not add a closing
paragraph that only offers further help."
  "What the polite key asks for."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-compose-prompt
  "Write a new email for %n <%e>, about this: %i

%r

The email is written in org-mode syntax, because it is sent as HTML:
- *bold* for emphasis
- /italic/ for light emphasis
- [[url][text]] for links

Do NOT include email headers (To, From, Subject) - just the body text.
Do NOT include a signature - that will be added automatically.
Start with an appropriate greeting."
  "Prompt template for composing new emails.

How the email should sound is not here; that is `mu4e-llm-prompt-voice',
which is sent as the system prompt.

Placeholders:
  %n  the sender\\='s name
  %e  the sender\\='s email address
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
