;;; mu4e-llm-thread.el --- Thread extraction for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;;; Commentary:
;; Thread extraction and message body cleanup for mu4e-llm.
;; Supports both in-Emacs extraction and mu CLI fallback.

;;; Code:

(require 'cl-lib)
(require 'mu4e-llm-config)

;; Forward declarations
(declare-function mu4e-message-at-point "mu4e-message")
(declare-function mu4e-message-field "mu4e-message")
(declare-function mu4e-view-message-text "mu4e-view")

;;; --- Data Structures ---

(cl-defstruct mu4e-llm-thread
  "Structure representing an email thread."
  message-id        ; Message ID of the current/anchor message
  subject           ; Thread subject
  messages          ; List of mu4e-llm-thread-message structs
  participant-count ; Number of unique participants
  message-count)    ; Total messages in thread

(cl-defstruct mu4e-llm-thread-message
  "Structure representing a single message in a thread."
  message-id  ; Message ID
  date        ; Date as string
  from        ; From address (name <email> or just email)
  to          ; To addresses
  subject     ; Subject line
  body        ; Cleaned body text
  is-reply    ; Whether this is a reply
  depth)      ; Thread depth (0 = root)

;;; --- Body Cleanup ---

(defconst mu4e-llm--quote-patterns
  '("^>+ *"                             ; Standard quoting
    "^On .* wrote:$"                   ; Gmail/Outlook quote intro
    "^Am .* schrieb .*:$"              ; German quote intro
    "^Le .* a écrit :$"                ; French quote intro
    "^-+\\s-*Original Message\\s-*-+$" ; Outlook original message
    "^-+\\s-*Forwarded message\\s-*-+$" ; Forwarded message header
    "^From: .* <.*@.*>"                ; Forwarded From header
    "^Sent: "                          ; Forwarded Sent header
    "^To: "                            ; Forwarded To header
    "^Subject: ")                      ; Forwarded Subject header
  "Patterns that indicate quoted or forwarded content.")

(defconst mu4e-llm--signature-patterns
  '("^-- ?$"                    ; Standard signature marker
    "^___+$"                   ; Underscore separator
    "^---+$"                   ; Dash separator
    "^Sent from my "           ; Mobile signature
    "^Get Outlook for "        ; Outlook mobile
    "^Diese Nachricht wurde von" ; German mobile signature
    "^Envoyé depuis")          ; French mobile signature
  "Patterns that indicate signature start.")

(defun mu4e-llm-thread--clean-body (body &optional max-length)
  "Clean BODY text by removing quotes and signatures.
Truncate to MAX-LENGTH if specified (default: `mu4e-llm-max-message-length')."
  (let ((max-len (or max-length mu4e-llm-max-message-length))
        (lines (split-string (or body "") "\n"))
        result
        in-signature)
    ;; Process lines, removing quotes and detecting signature
    (dolist (line lines)
      (let ((trimmed (string-trim line)))
        ;; Check for signature start
        (when (and (not in-signature)
                   (cl-some (lambda (pat)
                              (string-match-p pat trimmed))
                            mu4e-llm--signature-patterns))
          (setq in-signature t))
        ;; Skip quoted lines and signature content
        (unless (or in-signature
                    (string-match-p "^>+ *" trimmed)
                    (and (> (length result) 0)
                         (string-match-p "^On .* wrote:$" trimmed))
                    (string-match-p "^-+\\s-*Original Message" trimmed))
          (push line result))))
    ;; Reassemble and clean up
    (let* ((text (string-trim
                  (replace-regexp-in-string
                   "\n\\{3,\\}" "\n\n"  ; Collapse multiple blank lines
                   (mapconcat #'identity (nreverse result) "\n"))))
           (len (length text)))
      ;; Truncate if needed
      (if (and max-len (> len max-len))
          (concat (substring text 0 max-len) "\n[... truncated ...]")
        text))))

;;; --- Thread Extraction ---

(defun mu4e-llm-thread--get-references (msg)
  "Get list of message IDs from MSG's References and In-Reply-To headers."
  (let ((refs-str (or (mu4e-message-field msg :references)
                      (mu4e-message-field msg :in-reply-to)
                      ""))
        refs)
    ;; Parse message IDs from the references string
    (with-temp-buffer
      (insert (if (stringp refs-str) refs-str ""))
      (goto-char (point-min))
      (while (re-search-forward "<\\([^>]+\\)>" nil t)
        (push (match-string 1) refs)))
    (nreverse refs)))

(defun mu4e-llm-thread--fetch-message-by-id (msg-id)
  "Fetch message data for MSG-ID using mu CLI.
Returns a plist with message fields or nil if not found."
  (let* ((cmd (format "mu find 'msgid:%s' --format=sexp 2>/dev/null" msg-id))
         (output (with-temp-buffer
                   (let ((exit-code (call-process-shell-command cmd nil t nil)))
                     (when (= exit-code 0)
                       (buffer-string))))))
    (when (and output (> (length (string-trim output)) 0))
      (condition-case nil
          (car (read (concat "(" output ")")))
        (error nil)))))

(defun mu4e-llm-thread--format-address (addr)
  "Format address ADDR as a readable string."
  (cond
   ((stringp addr) addr)
   ((and (listp addr) (plist-get addr :name))
    (format "%s <%s>"
            (plist-get addr :name)
            (or (plist-get addr :email) "unknown")))
   ((and (listp addr) (plist-get addr :email))
    (plist-get addr :email))
   ((and (consp addr) (stringp (car addr)))
    ;; Old format: (name . email)
    (if (and (car addr) (not (string-empty-p (car addr))))
        (format "%s <%s>" (car addr) (cdr addr))
      (cdr addr)))
   (t "unknown")))

(defun mu4e-llm-thread--format-addresses (addrs)
  "Format list of addresses ADDRS as a readable string."
  (if (listp addrs)
      (mapconcat #'mu4e-llm-thread--format-address addrs ", ")
    (mu4e-llm-thread--format-address addrs)))

(defun mu4e-llm-thread--get-body (msg)
  "Get the body text of MSG.
Uses mu4e-view-message-text if available, otherwise tries body-txt field."
  (or (when (fboundp 'mu4e-view-message-text)
        (condition-case nil
            (mu4e-view-message-text msg)
          (error nil)))
      (mu4e-message-field msg :body-txt)
      (mu4e-message-field msg :body-html)
      ""))

(defun mu4e-llm-thread--msg-to-struct (msg depth)
  "Convert mu4e MSG to `mu4e-llm-thread-message' struct at DEPTH."
  (make-mu4e-llm-thread-message
   :message-id (mu4e-message-field msg :message-id)
   :date (format-time-string "%Y-%m-%d %H:%M"
                             (mu4e-message-field msg :date))
   :from (mu4e-llm-thread--format-address
          (mu4e-message-field msg :from))
   :to (mu4e-llm-thread--format-addresses
        (mu4e-message-field msg :to))
   :subject (mu4e-message-field msg :subject)
   :body (mu4e-llm-thread--clean-body
          (mu4e-llm-thread--get-body msg))
   :is-reply (> depth 0)
   :depth depth))

(defun mu4e-llm-thread-extract (&optional msg)
  "Extract thread information for MSG (default: message at point).
Returns a `mu4e-llm-thread' struct."
  (unless msg
    (setq msg (mu4e-message-at-point)))
  (unless msg
    (error "No message at point"))
  (let* ((msg-id (mu4e-message-field msg :message-id))
         (subject (mu4e-message-field msg :subject))
         (refs (mu4e-llm-thread--get-references msg))
         messages
         participants)
    ;; Get current message
    (push (mu4e-llm-thread--msg-to-struct msg 0) messages)
    (push (mu4e-llm-thread--format-address
           (mu4e-message-field msg :from))
          participants)
    ;; Fetch referenced messages (up to limit)
    (let ((count 1))
      (dolist (ref-id refs)
        (when (< count mu4e-llm-max-thread-messages)
          (when-let ((ref-msg (mu4e-llm-thread--fetch-message-by-id ref-id)))
            (push (mu4e-llm-thread--msg-to-struct ref-msg count) messages)
            (push (mu4e-llm-thread--format-address
                   (plist-get ref-msg :from))
                  participants)
            (cl-incf count)))))
    ;; Sort messages by date (oldest first)
    (setq messages (sort messages
                         (lambda (a b)
                           (string< (mu4e-llm-thread-message-date a)
                                    (mu4e-llm-thread-message-date b)))))
    ;; Build thread struct
    (make-mu4e-llm-thread
     :message-id msg-id
     :subject subject
     :messages messages
     :participant-count (length (delete-dups participants))
     :message-count (length messages))))

;;; --- Thread Formatting for LLM ---

(defun mu4e-llm-thread-to-prompt-context (thread)
  "Convert THREAD to a formatted string for LLM context."
  (let ((msgs (mu4e-llm-thread-messages thread))
        result)
    (push (format "Email Thread: %s\n"
                  (mu4e-llm-thread-subject thread))
          result)
    (push (format "Participants: %d | Messages: %d\n"
                  (mu4e-llm-thread-participant-count thread)
                  (mu4e-llm-thread-message-count thread))
          result)
    (push "---\n" result)
    (dolist (msg msgs)
      (push (format "\n[%s] From: %s\nTo: %s\nSubject: %s\n\n%s\n"
                    (mu4e-llm-thread-message-date msg)
                    (mu4e-llm-thread-message-from msg)
                    (mu4e-llm-thread-message-to msg)
                    (mu4e-llm-thread-message-subject msg)
                    (mu4e-llm-thread-message-body msg))
            result)
      (push "\n---\n" result))
    (apply #'concat (nreverse result))))

(defun mu4e-llm-thread-last-message (thread)
  "Get the most recent message from THREAD."
  (car (last (mu4e-llm-thread-messages thread))))

(provide 'mu4e-llm-thread)
;;; mu4e-llm-thread.el ends here
