;;; mu4e-llm-translate.el --- Translation for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;;; Commentary:
;; Email translation using LLM for mu4e.
;; Supports message, thread, and region translation.

;;; Code:

(require 'cl-lib)
(require 'mu4e-llm-config)
(require 'mu4e-llm-core)
(require 'mu4e-llm-thread)

;; Forward declarations
(declare-function mu4e-message-at-point "mu4e-message")

;;; --- Prompt Templates ---

(defcustom mu4e-llm-translate-message-prompt
  "Translate the following email to %s.
Preserve the formatting and structure.
Keep names, email addresses, and technical terms as-is.
Do not add any commentary or notes.

EMAIL:
From: %s
Subject: %s

%s"
  "Prompt template for message translation.
Placeholders (in order):
  1. target-language - the language to translate to
  2. from - the sender's name/email
  3. subject - the email subject
  4. body - the email body text"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-translate-thread-prompt
  "Translate the following email thread to %s.
Preserve the formatting and structure of each message.
Keep names, email addresses, and technical terms as-is.
Maintain the chronological order and clear separation between messages.
Do not add any commentary or notes.

EMAIL THREAD:
%s"
  "Prompt template for thread translation.
Placeholders (in order):
  1. target-language - the language to translate to
  2. thread-context - the formatted email thread"
  :type 'string
  :group 'mu4e-llm)

(defcustom mu4e-llm-translate-text-prompt
  "Translate the following text to %s.
Preserve the formatting.
Do not add any commentary or notes.

TEXT:
%s"
  "Prompt template for text/region translation.
Placeholders (in order):
  1. target-language - the language to translate to
  2. text - the text to translate"
  :type 'string
  :group 'mu4e-llm)

;;; --- Translation Buffer Mode ---

(defvar mu4e-llm-translate-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "t") #'mu4e-llm-translate--change-language)
    (define-key map (kbd "c") #'mu4e-llm-translate--copy)
    (define-key map (kbd "a") #'mu4e-llm-abort)
    map)
  "Keymap for `mu4e-llm-translate-mode'.")

(define-derived-mode mu4e-llm-translate-mode special-mode "mu4e-llm-translate"
  "Major mode for displaying mu4e-llm translations.
\\{mu4e-llm-translate-mode-map}"
  :group 'mu4e-llm
  (setq-local buffer-read-only nil)
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (visual-line-mode 1))

;;; --- Translation Buffer ---

(defvar-local mu4e-llm-translate--source-text nil
  "Original text being translated.")

(defvar-local mu4e-llm-translate--target-lang nil
  "Target language for translation.")

(defvar-local mu4e-llm-translate--worker nil
  "Current worker for this translation buffer.")

(defvar-local mu4e-llm-translate--insert-marker nil
  "Marker for inserting streaming content.")

(defun mu4e-llm-translate--get-buffer ()
  "Get or create the translation buffer."
  (let ((buf (get-buffer-create "*mu4e-llm-translation*")))
    (with-current-buffer buf
      (unless (derived-mode-p 'mu4e-llm-translate-mode)
        (mu4e-llm-translate-mode)))
    buf))

(defun mu4e-llm-translate--prepare-buffer (target-lang source-type)
  "Prepare translation buffer for TARGET-LANG and SOURCE-TYPE."
  (let ((buf (mu4e-llm-translate--get-buffer)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (setq mu4e-llm-translate--target-lang target-lang)
      ;; Header
      (insert (propertize
               (format "Translation (%s → %s)\n"
                       source-type
                       (car (rassoc target-lang mu4e-llm-languages)))
               'face 'bold))
      (insert (make-string 50 ?-) "\n\n")
      ;; Content marker
      (setq mu4e-llm-translate--insert-marker (point-marker))
      (insert mu4e-llm-streaming-indicator)
      (setq buffer-read-only t))
    buf))

(defun mu4e-llm-translate--insert-text (buf text)
  "Insert TEXT at marker position in BUF."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char mu4e-llm-translate--insert-marker)
          (delete-region (point) (point-max))
          (insert text)
          (insert mu4e-llm-streaming-indicator))))))

(defun mu4e-llm-translate--finalize (buf text)
  "Finalize translation in BUF with final TEXT."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char mu4e-llm-translate--insert-marker)
          (delete-region (point) (point-max))
          (insert text)
          (insert "\n\n")
          (insert (propertize
                   "[q]uit  [t]ranslate to different language  [c]opy"
                   'face 'shadow)))))))

;;; --- Language Selection ---

(defun mu4e-llm-translate--select-language ()
  "Prompt user to select a target language."
  (let* ((choices (mapcar #'car mu4e-llm-languages))
         (choice (completing-read "Translate to: " choices nil t)))
    (cdr (assoc choice mu4e-llm-languages))))

(defun mu4e-llm-translate--change-language ()
  "Change translation to a different language."
  (interactive)
  (when mu4e-llm-translate--source-text
    (let ((new-lang (mu4e-llm-translate--select-language)))
      (mu4e-llm-translate--do-translate
       mu4e-llm-translate--source-text
       new-lang
       "Text"))))

(defun mu4e-llm-translate--copy ()
  "Copy translation to kill ring."
  (interactive)
  (save-excursion
    (goto-char mu4e-llm-translate--insert-marker)
    (let ((text (buffer-substring-no-properties
                 (point)
                 (if (search-forward "\n\n[q]" nil t)
                     (match-beginning 0)
                   (point-max)))))
      (kill-new (string-trim text))
      (message "Translation copied to clipboard"))))

;;; --- Translation Commands ---

(defun mu4e-llm-translate--do-translate (text target-lang source-type)
  "Translate TEXT to TARGET-LANG, labeled as SOURCE-TYPE in UI."
  (let* ((buf (mu4e-llm-translate--prepare-buffer target-lang source-type))
         (lang-name (car (rassoc target-lang mu4e-llm-languages)))
         (prompt (format mu4e-llm-translate-text-prompt lang-name text))
         (worker (mu4e-llm--create-worker
                  'translate
                  nil
                  (lambda (success result)
                    (if success
                        (mu4e-llm-translate--finalize buf result)
                      (mu4e-llm-translate--finalize
                       buf (format "Error: %s" result))))
                  `(:lang ,target-lang :type ,source-type))))
    (with-current-buffer buf
      (setq mu4e-llm-translate--source-text text)
      (setq mu4e-llm-translate--worker worker))
    (display-buffer buf)
    ;; Start LLM call
    (mu4e-llm--chat
     worker
     prompt
     (lambda (partial)
       (mu4e-llm-translate--insert-text buf partial))
     (lambda (final)
       (mu4e-llm-translate--finalize buf final)))))

;;;###autoload
(defun mu4e-llm-translate-message (&optional target-lang)
  "Translate the current email message.
Prompt for TARGET-LANG if not specified."
  (interactive)
  (let* ((msg (mu4e-message-at-point))
         (thread (mu4e-llm-thread-extract msg))
         (last-msg (mu4e-llm-thread-last-message thread))
         (lang (or target-lang (mu4e-llm-translate--select-language)))
         (lang-name (car (rassoc lang mu4e-llm-languages)))
         (prompt (format mu4e-llm-translate-message-prompt
                         lang-name
                         (mu4e-llm-thread-message-from last-msg)
                         (mu4e-llm-thread-message-subject last-msg)
                         (mu4e-llm-thread-message-body last-msg))))
    (let* ((buf (mu4e-llm-translate--prepare-buffer lang "Message"))
           (worker (mu4e-llm--create-worker
                    'translate
                    msg
                    (lambda (success result)
                      (if success
                          (mu4e-llm-translate--finalize buf result)
                        (mu4e-llm-translate--finalize
                         buf (format "Error: %s" result))))
                    `(:lang ,lang :type message))))
      (with-current-buffer buf
        (setq mu4e-llm-translate--source-text
              (mu4e-llm-thread-message-body last-msg))
        (setq mu4e-llm-translate--worker worker))
      (display-buffer buf)
      (mu4e-llm--chat
       worker
       prompt
       (lambda (partial)
         (mu4e-llm-translate--insert-text buf partial))
       (lambda (final)
         (mu4e-llm-translate--finalize buf final))))))

;;;###autoload
(defun mu4e-llm-translate-thread (&optional target-lang)
  "Translate the entire email thread.
Prompt for TARGET-LANG if not specified."
  (interactive)
  (let* ((msg (mu4e-message-at-point))
         (thread (mu4e-llm-thread-extract msg))
         (context (mu4e-llm-thread-to-prompt-context thread))
         (lang (or target-lang (mu4e-llm-translate--select-language)))
         (lang-name (car (rassoc lang mu4e-llm-languages)))
         (prompt (format mu4e-llm-translate-thread-prompt lang-name context)))
    (let* ((buf (mu4e-llm-translate--prepare-buffer lang "Thread"))
           (worker (mu4e-llm--create-worker
                    'translate
                    msg
                    (lambda (success result)
                      (if success
                          (mu4e-llm-translate--finalize buf result)
                        (mu4e-llm-translate--finalize
                         buf (format "Error: %s" result))))
                    `(:lang ,lang :type thread))))
      (with-current-buffer buf
        (setq mu4e-llm-translate--source-text context)
        (setq mu4e-llm-translate--worker worker))
      (display-buffer buf)
      (mu4e-llm--chat
       worker
       prompt
       (lambda (partial)
         (mu4e-llm-translate--insert-text buf partial))
       (lambda (final)
         (mu4e-llm-translate--finalize buf final))))))

;;;###autoload
(defun mu4e-llm-translate-region (start end &optional target-lang)
  "Translate the region from START to END.
Prompt for TARGET-LANG if not specified."
  (interactive "r")
  (let ((text (buffer-substring-no-properties start end))
        (lang (or target-lang (mu4e-llm-translate--select-language))))
    (mu4e-llm-translate--do-translate text lang "Selection")))

(provide 'mu4e-llm-translate)
;;; mu4e-llm-translate.el ends here
