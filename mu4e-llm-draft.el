;;; mu4e-llm-draft.el --- Smart reply drafting for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;; This file is NOT part of GNU Emacs.

;; SPDX-License-Identifier: MIT

;;; Commentary:
;; Smart reply drafting with LLM, supporting iterative refinement.
;; Output is org-mode syntax compatible with org-msg.

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'mu4e-llm-config)
(require 'mu4e-llm-prompts)
(require 'mu4e-llm-core)
(require 'mu4e-llm-thread)

;; Forward declarations
(declare-function mu4e-message-at-point "mu4e-message")
(declare-function mu4e-message-field "mu4e-message")
(declare-function mu4e-compose-reply "mu4e-compose")
(declare-function mu4e-compose-mode "mu4e-compose")
(declare-function mu4e-context-match-func "mu4e-context")
(declare-function mu4e-context-name "mu4e-context")
(declare-function mu4e-context-switch "mu4e-context")
(declare-function org-msg-mode "org-msg")
(declare-function org-msg-goto-body "org-msg")
(declare-function message-goto-body "message")
(defvar mu4e-contexts)

;; Variables from mu4e-llm-config (suppress byte-compile warnings)


;;; --- Context Matching ---

(defun mu4e-llm--find-context-for-message (msg)
  "Find the mu4e context matching MSG using each context's :match-func.
Returns the context object, or nil if no match found."
  (when (and msg (boundp 'mu4e-contexts) mu4e-contexts)
    (cl-find-if (lambda (ctx)
                  (when-let ((match-func (mu4e-context-match-func ctx)))
                    (funcall match-func msg)))
                mu4e-contexts)))

;;; --- Draft Buffer Mode ---

(defvar mu4e-llm-draft-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map org-mode-map)
    (define-key map (kbd "C-c C-r") #'mu4e-llm-draft-refine)
    (define-key map (kbd "C-c C-s") #'mu4e-llm-draft-shorten)
    (define-key map (kbd "C-c C-p") #'mu4e-llm-draft-make-polite)
    ;; C-c C-n and C-c C-b shadow org's heading navigation, which is of no
    ;; use in a five-line email.  C-c C-l is deliberately left alone: it is
    ;; org-insert-link, and drafts carry [[url][text]] links.
    (define-key map (kbd "C-c C-n") #'mu4e-llm-draft-plainer)
    (define-key map (kbd "C-c C-b") #'mu4e-llm-draft-bullets)
    (define-key map (kbd "C-c C-f") #'mu4e-llm-draft-finalize)
    (define-key map (kbd "C-c C-t") #'mu4e-llm-draft-toggle-summary)
    (define-key map (kbd "C-c C-k") #'mu4e-llm-draft-cancel)
    map)
  "Keymap for `mu4e-llm-draft-mode'.")

(define-derived-mode mu4e-llm-draft-mode org-mode "mu4e-llm-draft"
  "Major mode for editing mu4e-llm draft replies.
\\{mu4e-llm-draft-mode-map}"
  :group 'mu4e-llm
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (visual-line-mode 1))

;;; --- Draft Buffer Variables ---

(defvar-local mu4e-llm-draft--thread nil
  "Thread context for current draft.")

(defvar-local mu4e-llm-draft--original-message nil
  "The original message being replied to.")

(defvar-local mu4e-llm-draft--worker nil
  "Current worker for this draft buffer.")

(defvar-local mu4e-llm-draft--summary-visible t
  "Whether the summary section is visible.")

(defvar-local mu4e-llm-draft--summary-overlay nil
  "Overlay for the summary section.")

(defvar-local mu4e-llm-draft--draft-start nil
  "Marker for where the editable draft begins.")

(defvar-local mu4e-llm-draft--insert-marker nil
  "Marker for inserting streaming content.")

(defvar-local mu4e-llm-draft--compose-mode nil
  "Non-nil if this is a new compose (not a reply).")

(defvar-local mu4e-llm-draft--recipient nil
  "Recipient for new compose.")

(defvar-local mu4e-llm-draft--subject nil
  "Subject for new compose.")

;;; --- Draft Buffer Management ---

(defun mu4e-llm-draft--get-buffer ()
  "Get or create the draft buffer."
  (let ((buf (get-buffer-create mu4e-llm-draft-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'mu4e-llm-draft-mode)
        (mu4e-llm-draft-mode)))
    buf))

(defun mu4e-llm-draft--prepare-buffer (thread msg)
  "Prepare draft buffer for THREAD with original MSG."
  (let ((buf (mu4e-llm-draft--get-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq mu4e-llm-draft--thread thread)
        (setq mu4e-llm-draft--original-message msg)
        ;; Insert summary section
        (let ((summary-start (point)))
          (insert (propertize "Thread Summary\n" 'face 'bold))
          (insert (format "Subject: %s\n"
                          (mu4e-llm-thread-subject thread)))
          (insert (format "Messages: %d | Participants: %d\n\n"
                          (mu4e-llm-thread-message-count thread)
                          (mu4e-llm-thread-participant-count thread)))
          ;; Brief context from last message
          (let ((last-msg (mu4e-llm-thread-last-message thread)))
            (insert (format "Last from: %s\n"
                            (mu4e-llm-thread-message-from last-msg)))
            (insert (truncate-string-to-width
                     (mu4e-llm-thread-message-body last-msg)
                     300 nil nil "..."))
            (insert "\n"))
          ;; Create overlay for summary
          (let ((ov (make-overlay summary-start (point))))
            (overlay-put ov 'face 'shadow)
            (overlay-put ov 'mu4e-llm-summary t)
            (setq mu4e-llm-draft--summary-overlay ov)))
        ;; Separator
        (insert "\n" (make-string 50 ?-) "\n\n")
        ;; Draft area marker
        (setq mu4e-llm-draft--draft-start (point-marker))
        (setq mu4e-llm-draft--insert-marker (point-marker))
        (insert mu4e-llm-streaming-indicator)
        ;; Help text at bottom
        (insert "\n\n")
        (insert (propertize
                 (concat "[C-c C-f]inalize  [C-c C-r]efine  [C-c C-s]horten  "
                         "[C-c C-p]olite  [C-c C-n] plainer  [C-c C-b]ullets  "
                         "[C-c C-k]cancel")
                 'face 'shadow))))
    buf))

(defun mu4e-llm-draft--prepare-compose-buffer (recipient subject instructions)
  "Prepare draft buffer for new compose with RECIPIENT, SUBJECT, and INSTRUCTIONS."
  (let ((buf (mu4e-llm-draft--get-buffer)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (setq mu4e-llm-draft--thread nil)
        (setq mu4e-llm-draft--original-message nil)
        (setq mu4e-llm-draft--compose-mode t)
        (setq mu4e-llm-draft--recipient recipient)
        (setq mu4e-llm-draft--subject subject)
        (setq mu4e-llm-draft--summary-overlay nil)
        ;; Insert compose info section
        (insert (propertize "New Email\n" 'face 'bold))
        (when recipient
          (insert (format "To: %s\n" recipient)))
        (when subject
          (insert (format "Subject: %s\n" subject)))
        (insert (format "Instructions: %s\n" instructions))
        ;; Separator
        (insert "\n" (make-string 50 ?-) "\n\n")
        ;; Draft area marker
        (setq mu4e-llm-draft--draft-start (point-marker))
        (setq mu4e-llm-draft--insert-marker (point-marker))
        (insert mu4e-llm-streaming-indicator)
        ;; Help text at bottom
        (insert "\n\n")
        (insert (propertize
                 (concat "[C-c C-f]inalize  [C-c C-r]efine  [C-c C-s]horten  "
                         "[C-c C-p]olite  [C-c C-n] plainer  [C-c C-b]ullets  "
                         "[C-c C-k]cancel")
                 'face 'shadow))))
    buf))

(defun mu4e-llm-draft--insert-text (buf text)
  "Insert TEXT at marker position in BUF."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (save-excursion
        (goto-char mu4e-llm-draft--insert-marker)
        ;; Find and delete to next marker or help text
        (let ((end (save-excursion
                     (if (search-forward "\n\n[C-c" nil t)
                         (match-beginning 0)
                       (point-max)))))
          (delete-region (point) end))
        ;; Insert new text
        (insert text)
        (insert mu4e-llm-streaming-indicator)))))

(defun mu4e-llm-draft--finalize-text (buf text)
  "Finalize draft in BUF with final TEXT."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (save-excursion
        (goto-char mu4e-llm-draft--insert-marker)
        (let ((end (save-excursion
                     (if (search-forward "\n\n[C-c" nil t)
                         (match-beginning 0)
                       (point-max)))))
          (delete-region (point) end))
        (insert text))
      ;; Move cursor to draft area for editing
      (goto-char mu4e-llm-draft--draft-start))))

;;; --- Draft Generation ---

(defun mu4e-llm-draft--generate (thread msg &optional instructions)
  "Generate draft reply for THREAD based on MSG with optional INSTRUCTIONS."
  (let* ((buf (mu4e-llm-draft--prepare-buffer thread msg))
         (identity (mu4e-llm--user-identity))
         (user-name (car identity))
         (user-email (cdr identity))
         (context (mu4e-llm-thread-to-prompt-context thread))
         (extra-instructions (if instructions
                                 (format "\nAdditional instructions: %s" instructions)
                               ""))
         (prompt (mu4e-llm--prompt
                  mu4e-llm-draft-reply-prompt
                  `((?n . ,user-name)
                    (?e . ,user-email)
                    (?t . ,context)
                    (?i . ,extra-instructions))))
         (worker (mu4e-llm--create-worker
                  'draft
                  msg
                  (lambda (success result)
                    (if success
                        (mu4e-llm-draft--finalize-text buf result)
                      (mu4e-llm-draft--finalize-text
                       buf (format "Error: %s" result))))
                  `(:thread ,thread))))
    (with-current-buffer buf
      (setq mu4e-llm-draft--worker worker))
    (pop-to-buffer buf)
    ;; Start LLM call
    (mu4e-llm--chat
     worker
     prompt
     (lambda (partial)
       (mu4e-llm-draft--insert-text buf partial))
     (lambda (final)
       (mu4e-llm-draft--finalize-text buf final)))))

;;;###autoload
(defun mu4e-llm-draft-reply (&optional instructions msg)
  "Generate a smart reply to an email.
Optional INSTRUCTIONS customize the reply.  MSG is the message to reply
to, defaulting to the one at point.  The summary buffer passes the
message it was generated from, because it has no message at point.

MSG is appended rather than prepended so the existing autoload and the
keymap entry, which call this with no arguments, keep working."
  (interactive)
  (let* ((msg (or msg (mu4e-message-at-point)))
         (thread (mu4e-llm-thread-extract msg)))
    (mu4e-llm-draft--generate thread msg instructions)))

;;; --- New Email Composition ---

(defun mu4e-llm-draft--generate-compose (instructions &optional recipient subject)
  "Generate new email based on INSTRUCTIONS.
Optional RECIPIENT and SUBJECT provide context."
  (let* ((buf (mu4e-llm-draft--prepare-compose-buffer recipient subject instructions))
         (identity (mu4e-llm--user-identity))
         (user-name (car identity))
         (user-email (cdr identity))
         (recipient-context (if recipient
                                (format "The recipient is: %s" recipient)
                              ""))
         (prompt (mu4e-llm--prompt
                  mu4e-llm-draft-compose-prompt
                  `((?n . ,user-name)
                    (?e . ,user-email)
                    (?i . ,instructions)
                    (?r . ,recipient-context))))
         (worker (mu4e-llm--create-worker
                  'compose
                  nil
                  (lambda (success result)
                    (if success
                        (mu4e-llm-draft--finalize-text buf result)
                      (mu4e-llm-draft--finalize-text
                       buf (format "Error: %s" result))))
                  `(:instructions ,instructions
                    :recipient ,recipient
                    :subject ,subject))))
    (with-current-buffer buf
      (setq mu4e-llm-draft--worker worker))
    (pop-to-buffer buf)
    ;; Start LLM call
    (mu4e-llm--chat
     worker
     prompt
     (lambda (partial)
       (mu4e-llm-draft--insert-text buf partial))
     (lambda (final)
       (mu4e-llm-draft--finalize-text buf final)))))

;;;###autoload
(defun mu4e-llm-draft-compose (instructions)
  "Compose a new email based on INSTRUCTIONS.
Prompts for recipient and subject, then generates the email body."
  (interactive "sWhat email do you want to write? ")
  (let ((recipient (read-string "To (optional, press RET to skip): "))
        (subject (read-string "Subject (optional, press RET to skip): ")))
    (mu4e-llm-draft--generate-compose
     instructions
     (if (string-empty-p recipient) nil recipient)
     (if (string-empty-p subject) nil subject))))

;;; --- Refinement Commands ---

(defun mu4e-llm-draft--get-draft-text ()
  "Get the current draft text from buffer."
  (when mu4e-llm-draft--draft-start
    (save-excursion
      (goto-char mu4e-llm-draft--draft-start)
      (let ((end (save-excursion
                   (if (search-forward "\n\n[C-c" nil t)
                       (match-beginning 0)
                     (point-max)))))
        (string-trim (buffer-substring-no-properties (point) end))))))

(defun mu4e-llm-draft--refine-with-instruction (instruction)
  "Refine current draft with INSTRUCTION."
  (let* ((current-draft (mu4e-llm-draft--get-draft-text))
         (buf (current-buffer))
         (prompt (mu4e-llm--prompt
                  mu4e-llm-draft-refine-prompt
                  `((?i . ,instruction)
                    (?d . ,(or current-draft ""))))))
    ;; Abort previous worker if any
    (when mu4e-llm-draft--worker
      (mu4e-llm--abort-worker mu4e-llm-draft--worker))
    ;; Prepare for new content
    (save-excursion
      (goto-char mu4e-llm-draft--insert-marker)
      (let ((end (save-excursion
                   (if (search-forward "\n\n[C-c" nil t)
                       (match-beginning 0)
                     (point-max)))))
        (delete-region (point) end))
      (insert mu4e-llm-streaming-indicator))
    ;; Create new worker
    (let ((worker (mu4e-llm--create-worker
                   'refine
                   mu4e-llm-draft--original-message
                   (lambda (success result)
                     (if success
                         (mu4e-llm-draft--finalize-text buf result)
                       (mu4e-llm-draft--finalize-text
                        buf (format "Error: %s\n\n%s" result current-draft))))
                   `(:instruction ,instruction))))
      (setq mu4e-llm-draft--worker worker)
      ;; Save undo boundary
      (undo-boundary)
      ;; Start LLM call
      (mu4e-llm--chat
       worker
       prompt
       (lambda (partial)
         (mu4e-llm-draft--insert-text buf partial))
       (lambda (final)
         (mu4e-llm-draft--finalize-text buf final))))))

;;;###autoload
(defun mu4e-llm-draft-refine (instruction)
  "Refine the current draft with custom INSTRUCTION."
  (interactive "sRefinement instruction: ")
  (unless (derived-mode-p 'mu4e-llm-draft-mode)
    (error "Not in a mu4e-llm draft buffer"))
  (mu4e-llm-draft--refine-with-instruction instruction))

(defun mu4e-llm-draft-shorten ()
  "Make the current draft shorter without losing anything it says."
  (interactive)
  (mu4e-llm-draft--refine-with-instruction mu4e-llm-draft-shorten-instruction))

(defun mu4e-llm-draft-make-polite ()
  "Make the current draft warmer."
  (interactive)
  (mu4e-llm-draft--refine-with-instruction mu4e-llm-draft-polite-instruction))

(defun mu4e-llm-draft-plainer ()
  "Rewrite the current draft in plainer language, keeping its meaning."
  (interactive)
  (mu4e-llm-draft--refine-with-instruction mu4e-llm-draft-plainer-instruction))

(defun mu4e-llm-draft-bullets ()
  "Turn the body of the current draft into a bulleted list."
  (interactive)
  (mu4e-llm-draft--refine-with-instruction mu4e-llm-draft-bullets-instruction))

;;; --- Buffer Actions ---

(defun mu4e-llm-draft-toggle-summary ()
  "Toggle visibility of the summary section."
  (interactive)
  (when mu4e-llm-draft--summary-overlay
    (if mu4e-llm-draft--summary-visible
        (overlay-put mu4e-llm-draft--summary-overlay 'invisible t)
      (overlay-put mu4e-llm-draft--summary-overlay 'invisible nil))
    (setq mu4e-llm-draft--summary-visible
          (not mu4e-llm-draft--summary-visible))))

(defun mu4e-llm-draft-cancel ()
  "Cancel draft and close buffer."
  (interactive)
  (when mu4e-llm-draft--worker
    (mu4e-llm--abort-worker mu4e-llm-draft--worker))
  (kill-buffer (current-buffer)))

(declare-function mu4e-compose-new "mu4e-compose")
(declare-function message-goto-to "message")
(declare-function message-goto-subject "message")

(defun mu4e-llm-draft-finalize ()
  "Accept draft and open in mu4e compose buffer."
  (interactive)
  (let ((draft-text (mu4e-llm-draft--get-draft-text))
        (compose-mode mu4e-llm-draft--compose-mode)
        (recipient mu4e-llm-draft--recipient)
        (subject mu4e-llm-draft--subject)
        (msg mu4e-llm-draft--original-message)
        (draft-buffer (current-buffer)))
    ;; For reply mode, we need the original message
    (when (and (not compose-mode) (not msg))
      (user-error "No original message context"))
    ;; Switch to correct mu4e context based on original message
    ;; This ensures the signature hook sees the right account
    (when (and msg (not compose-mode))
      (when-let ((ctx (mu4e-llm--find-context-for-message msg)))
        (mu4e-context-switch nil (mu4e-context-name ctx))))
    ;; Open compose buffer (new or reply).
    ;;
    ;; `mu4e-compose-reply' replies to the message at point, and
    ;; `mu4e-message-at-point' answers only in a headers or view buffer.  The
    ;; draft buffer is neither, so this used to work only because the window
    ;; behind the draft usually held one -- and it fails outright when the
    ;; draft was reached from a summary buffer.  The message we want is on the
    ;; buffer already, so make that the message at point for this one call.
    ;;
    ;; The draft buffer is killed after this, never before: if composing
    ;; signals, the draft text must still be there to try again with.
    (if compose-mode
        (mu4e-compose-new)
      (cl-letf (((symbol-function 'mu4e-message-at-point) (lambda (&rest _) msg)))
        (mu4e-compose-reply)))
    (when (buffer-live-p draft-buffer)
      (kill-buffer draft-buffer))
    ;; Wait for compose buffer to be ready
    (run-at-time 0.1 nil
                 (lambda ()
                   ;; Fill in recipient and subject for new compose
                   (when compose-mode
                     (when recipient
                       (message-goto-to)
                       (insert recipient))
                     (when subject
                       (message-goto-subject)
                       (insert subject)))
                   ;; Insert draft body
                   (if (and (featurep 'org-msg)
                            (bound-and-true-p org-msg-mode))
                       ;; org-msg mode
                       (progn
                         (org-msg-goto-body)
                         ;; Clear default content (for replies)
                         (unless compose-mode
                           (let ((body-start (point)))
                             (when (re-search-forward "^#\\+begin_signature" nil t)
                               (goto-char (match-beginning 0))
                               (delete-region body-start (point)))))
                         (insert draft-text "\n\n"))
                     ;; Regular message mode
                     (progn
                       (message-goto-body)
                       (insert draft-text "\n\n")))))))

(provide 'mu4e-llm-draft)
;;; mu4e-llm-draft.el ends here
