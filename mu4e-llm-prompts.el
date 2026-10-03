;;; mu4e-llm-prompts.el --- Every prompt mu4e-llm sends -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.2.0

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
- After the greeting, the first sentence carries the point: the answer, the
  decision, or the request.  Thanks, if any, come after it and take one clause.
- Continuous prose, not a list, unless you are asked for a list.
- End with a short sign-off line such as \"Best regards,\" on its own line.  Do
  not write a name or a signature block after it; that gets added for you.

When you are revising a draft rather than writing one, these rules apply to the
text you are asked to change.  Leave everything else word for word, and keep the
draft in the language it is already written in.

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

A nil value renders as the empty string.  `format-spec' would treat nil as
missing and leave the placeholder showing, which is the same silent failure
by another route, so it is coerced here rather than at every call site."
  (format-spec template
               (mapcar (lambda (pair) (cons (car pair) (or (cdr pair) "")))
                       spec)
               'ignore))

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
End with a sign-off line, but no name and no signature block: the signature is
added for you.
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
are, unless the instruction asks for them by name. Do not add a sign-off
that is not already there. \"Make it one line\" means the body becomes one
line, not that the whole email collapses into one line.

Write the result in the same language as the draft below. The instruction
is in English; that says nothing about what language the email is in.

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

(defcustom mu4e-llm-draft-plainer-instruction
  "Make this plainer. Split long sentences. Replace jargon and formal
vocabulary with ordinary words. Cut throat-clearing before the point.
Keep the meaning exactly as it is: this is a rewrite of the wording, not
of the substance. It should read as though a person wrote it quickly and
clearly."
  "What the plainer key asks for.

This is the check on whether a draft reads like a person wrote it.  No
test can make that judgement, so the key exists to let the reader make
it in one keystroke."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-bullets-instruction
  "Turn the body into a short bulleted list, using org-mode \"- \"
bullets. One point per bullet, each on a single line where it fits. Keep
the greeting and the sign-off as prose, exactly as they are. If the body
makes a single point, leave it as prose rather than writing a list of
one."
  "What the bullets key asks for.

Prose is the default for a generated reply.  This is how you ask for the
other thing, for the emails where a list genuinely reads better."
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
End with a sign-off line, but no name and no signature block: the signature is
added for you.
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

;;; --- Labels ---
;;
;; Short strings the package wraps around a value before it becomes a
;; placeholder.  They live here so the claim at the top of this file -- that
;; nothing else holds prompt text -- is true.

(defcustom mu4e-llm-draft-instructions-label "\nAlso bear this in mind:\n%s"
  "How extra instructions are introduced in the reply prompt.
Rendered into `mu4e-llm-draft-reply-prompt' as its %i.  Takes one `format'
argument, the user\='s instructions."
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-draft-recipient-label "The recipient is: %s"
  "How the recipient is introduced in the compose prompt.
Rendered into `mu4e-llm-draft-compose-prompt' as its %r.  Takes one `format'
argument, the recipient."
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
  "Summarize the email thread below in about 200 words.

Use these sections, in this order. Put each heading on its own line, and
leave a blank line between one section and the next. Skip a section
entirely when the thread gives it nothing -- do not write a heading with
\"none\" underneath it.

What this is about
  One or two sentences.

Key points
  Short bullets, using \"- \".

Decisions
  What was settled, and by whom. Short bullets.

Action items
  Who needs to do what, and by when where a date was named. Short bullets.

Where it stands
  One or two sentences on the current state and what happens next.

Write for someone who needs to understand this thread quickly.

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
