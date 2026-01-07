;;; mu4e-llm-summary.el --- Thread summarization for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;; Author: Dr. Sandeep Sadanandan <sillyfellow@whybenormal.org>
;; URL: https://github.com/sillyfellow/mu4e-llm
;; Version: 0.1.0

;;; Commentary:
;; Thread summarization with LLM, supporting standard and executive summaries.
;; Features streaming output and caching.

;;; Code:

(require 'cl-lib)
(require 'mu4e-llm-config)
(require 'mu4e-llm-core)
(require 'mu4e-llm-thread)

;; Forward declarations
(declare-function mu4e-message-at-point "mu4e-message")
(declare-function mu4e-llm-draft-reply "mu4e-llm-draft")

;;; --- Prompt Templates ---

(defconst mu4e-llm-summary--standard-prompt
  "Summarize the following email thread concisely (around 200 words).

Include:
- Main topic and purpose of the discussion
- Key points and decisions made
- Action items or requests (if any)
- Current status or next steps needed

Use bullet points for clarity. Focus on what's most important for someone who needs to quickly understand this thread.

EMAIL THREAD:
%s"
  "Prompt template for standard thread summaries.")

(defconst mu4e-llm-summary--executive-prompt
  "Provide a brief executive summary of this email thread in 2-3 sentences.
Focus only on the critical information: what is this about and what action (if any) is needed.

EMAIL THREAD:
%s"
  "Prompt template for executive summaries.")

;;; --- Summary Buffer Mode ---

(defvar mu4e-llm-summary-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "q") #'quit-window)
    (define-key map (kbd "g") #'mu4e-llm-summary-regenerate)
    (define-key map (kbd "r") #'mu4e-llm-draft-reply-from-summary)
    (define-key map (kbd "a") #'mu4e-llm-abort)
    map)
  "Keymap for `mu4e-llm-summary-mode'.")

(define-derived-mode mu4e-llm-summary-mode special-mode "mu4e-llm-summary"
  "Major mode for displaying mu4e-llm thread summaries.
\\{mu4e-llm-summary-mode-map}"
  :group 'mu4e-llm
  (setq-local buffer-read-only nil)
  (setq-local truncate-lines nil)
  (setq-local word-wrap t)
  (visual-line-mode 1))

;;; --- Summary Generation ---

(defvar-local mu4e-llm-summary--current-thread nil
  "The thread being summarized in the current buffer.")

(defvar-local mu4e-llm-summary--current-worker nil
  "The current worker for this summary buffer.")

(defvar-local mu4e-llm-summary--insert-marker nil
  "Marker for inserting streaming content.")

(defun mu4e-llm-summary--get-buffer ()
  "Get or create the summary buffer."
  (let ((buf (get-buffer-create mu4e-llm-summary-buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'mu4e-llm-summary-mode)
        (mu4e-llm-summary-mode)))
    buf))

(defun mu4e-llm-summary--prepare-buffer (thread type)
  "Prepare summary buffer for THREAD with TYPE (standard/executive)."
  (let ((buf (mu4e-llm-summary--get-buffer)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (setq mu4e-llm-summary--current-thread thread)
      ;; Insert header
      (insert (propertize
               (format "Thread Summary (%s)\n"
                       (if (eq type 'executive) "Executive" "Standard"))
               'face 'bold))
      (insert (propertize
               (format "Subject: %s\n"
                       (mu4e-llm-thread-subject thread))
               'face 'italic))
      (insert (format "Messages: %d | Participants: %d\n"
                      (mu4e-llm-thread-message-count thread)
                      (mu4e-llm-thread-participant-count thread)))
      (insert (make-string 50 ?-) "\n\n")
      ;; Set marker for content insertion
      (setq mu4e-llm-summary--insert-marker (point-marker))
      (insert mu4e-llm-streaming-indicator)
      (setq buffer-read-only t))
    buf))

(defun mu4e-llm-summary--insert-text (buf text)
  "Insert TEXT at marker position in BUF."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char mu4e-llm-summary--insert-marker)
          ;; Delete indicator and previous content
          (delete-region (point) (point-max))
          ;; Insert new text
          (insert text)
          (insert mu4e-llm-streaming-indicator))))))

(defun mu4e-llm-summary--finalize (buf text)
  "Finalize summary in BUF with final TEXT."
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (save-excursion
          (goto-char mu4e-llm-summary--insert-marker)
          (delete-region (point) (point-max))
          (insert text)
          (insert "\n\n")
          (insert (propertize "[q]uit  [g]enerate again  [r]eply"
                              'face 'shadow)))))))

(defun mu4e-llm--summarize-internal (type)
  "Generate summary of TYPE for message at point.
TYPE is either `standard' or `executive'."
  (let* ((msg (mu4e-message-at-point))
         (thread (mu4e-llm-thread-extract msg))
         (msg-id (mu4e-llm-thread-message-id thread))
         (msg-count (mu4e-llm-thread-message-count thread))
         (cache-key (mu4e-llm--cache-key msg-id msg-count))
         (cached (and mu4e-llm-cache-summaries
                      (eq type 'standard)
                      (mu4e-llm--cache-get cache-key))))
    (if cached
        ;; Return cached summary
        (let ((buf (mu4e-llm-summary--prepare-buffer thread type)))
          (mu4e-llm-summary--finalize buf cached)
          (display-buffer buf)
          (message "mu4e-llm: Using cached summary"))
      ;; Generate new summary
      (let* ((buf (mu4e-llm-summary--prepare-buffer thread type))
             (context (mu4e-llm-thread-to-prompt-context thread))
             (prompt (format (if (eq type 'executive)
                                 mu4e-llm-summary--executive-prompt
                               mu4e-llm-summary--standard-prompt)
                             context))
             (worker (mu4e-llm--create-worker
                      (if (eq type 'executive) 'executive-summary 'summary)
                      msg
                      (lambda (success result)
                        (if success
                            (progn
                              (mu4e-llm-summary--finalize buf result)
                              ;; Cache standard summaries
                              (when (and mu4e-llm-cache-summaries
                                         (eq type 'standard))
                                (mu4e-llm--cache-set cache-key result)))
                          (mu4e-llm-summary--finalize
                           buf (format "Error: %s" result))))
                      `(:type ,type :thread ,thread))))
        (with-current-buffer buf
          (setq mu4e-llm-summary--current-worker worker))
        (display-buffer buf)
        ;; Start LLM call
        (mu4e-llm--chat
         worker
         prompt
         (lambda (partial)
           (mu4e-llm-summary--insert-text buf partial))
         (lambda (final)
           (mu4e-llm-summary--finalize buf final)
           (when (and mu4e-llm-cache-summaries (eq type 'standard))
             (mu4e-llm--cache-set cache-key final))))))))

;;;###autoload
(defun mu4e-llm-summarize ()
  "Summarize the email thread at point.
Shows a detailed summary with key points and action items."
  (interactive)
  (mu4e-llm--summarize-internal 'standard))

;;;###autoload
(defun mu4e-llm-summarize-executive ()
  "Generate a brief executive summary of the thread at point.
Shows only the critical information in 2-3 sentences."
  (interactive)
  (mu4e-llm--summarize-internal 'executive))

(defun mu4e-llm-summary-regenerate ()
  "Regenerate the summary for the current thread."
  (interactive)
  (when mu4e-llm-summary--current-thread
    (when mu4e-llm-summary--current-worker
      (mu4e-llm--abort-worker mu4e-llm-summary--current-worker))
    ;; Clear cache for this thread
    (let* ((thread mu4e-llm-summary--current-thread)
           (cache-key (mu4e-llm--cache-key
                       (mu4e-llm-thread-message-id thread)
                       (mu4e-llm-thread-message-count thread))))
      (remhash cache-key mu4e-llm--summary-cache))
    ;; We need to be in the original mu4e buffer to regenerate
    (message "mu4e-llm: Please regenerate from the mu4e message view")))

(defun mu4e-llm-draft-reply-from-summary ()
  "Start drafting a reply from the summary view."
  (interactive)
  (if mu4e-llm-summary--current-thread
      (progn
        (require 'mu4e-llm-draft)
        (mu4e-llm-draft-reply))
    (message "mu4e-llm: No thread context available")))

(provide 'mu4e-llm-summary)
;;; mu4e-llm-summary.el ends here
