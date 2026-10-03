;;; mu4e-llm-test.el --- Tests for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;;; Commentary:
;; Unit tests for mu4e-llm pure functions.

;;; Code:

(require 'ert)
(require 'cl-lib)

;; Add parent directory to load-path for testing
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

(require 'mu4e-llm-config)
(require 'mu4e-llm-prompts)
(require 'mu4e-llm-thread)
(require 'mu4e-llm-core)
(require 'mu4e-llm-summary)
(require 'mu4e-llm-draft)
(require 'mu4e-llm)

;;; ==========================================================================
;;; Body Cleanup Tests (mu4e-llm-thread--clean-body)
;;; ==========================================================================

(ert-deftest mu4e-llm-test-clean-body-passthrough ()
  "Plain text should pass through unchanged."
  (should (equal "Hello world"
                 (mu4e-llm-thread--clean-body "Hello world"))))

(ert-deftest mu4e-llm-test-clean-body-removes-single-quote ()
  "Single level quotes should be removed."
  (should (equal "Hello"
                 (mu4e-llm-thread--clean-body "> quoted line\nHello"))))

(ert-deftest mu4e-llm-test-clean-body-removes-nested-quotes ()
  "Nested quotes should be removed."
  (should (equal "Response"
                 (mu4e-llm-thread--clean-body ">> deeply quoted\n> quoted\nResponse"))))

(ert-deftest mu4e-llm-test-clean-body-removes-gmail-quote-intro ()
  "Gmail-style 'On X wrote:' should be removed when followed by quotes."
  (let ((input "Thanks!\n\nOn Mon, Dec 23, 2024 at 10:00 AM John wrote:\n> old message"))
    (should (equal "Thanks!"
                   (mu4e-llm-thread--clean-body input)))))

(ert-deftest mu4e-llm-test-clean-body-removes-signature ()
  "Standard signature marker '-- ' should truncate content."
  (should (equal "Message body"
                 (mu4e-llm-thread--clean-body "Message body\n-- \nJohn Doe\nCompany Inc"))))

(ert-deftest mu4e-llm-test-clean-body-removes-mobile-signature ()
  "Mobile signatures should be removed."
  (should (equal "Quick reply"
                 (mu4e-llm-thread--clean-body "Quick reply\nSent from my iPhone"))))

(ert-deftest mu4e-llm-test-clean-body-removes-outlook-signature ()
  "Outlook mobile signatures should be removed."
  (should (equal "Reply here"
                 (mu4e-llm-thread--clean-body "Reply here\nGet Outlook for iOS"))))

(ert-deftest mu4e-llm-test-clean-body-collapses-blank-lines ()
  "Multiple blank lines should be collapsed to maximum two."
  (let ((input "First\n\n\n\n\nSecond"))
    (should (equal "First\n\nSecond"
                   (mu4e-llm-thread--clean-body input)))))

(ert-deftest mu4e-llm-test-clean-body-truncates-long-text ()
  "Long text should be truncated with indicator."
  (let* ((long-text (make-string 5000 ?x))
         (result (mu4e-llm-thread--clean-body long-text 100)))
    (should (= (length result) (+ 100 (length "\n[... truncated ...]"))))
    (should (string-suffix-p "[... truncated ...]" result))))

(ert-deftest mu4e-llm-test-clean-body-handles-nil ()
  "Nil input should return empty string."
  (should (equal "" (mu4e-llm-thread--clean-body nil))))

(ert-deftest mu4e-llm-test-clean-body-handles-empty ()
  "Empty input should return empty string."
  (should (equal "" (mu4e-llm-thread--clean-body ""))))

(ert-deftest mu4e-llm-test-clean-body-removes-german-quote ()
  "German emails with quoted lines should have quotes removed."
  ;; The '> ' quoted lines are removed; the intro line remains
  ;; (German intro pattern is defined but not actively filtered)
  (let ((input "Danke!\n\n> alte Nachricht\n> mehr zitiert"))
    (should (equal "Danke!"
                   (mu4e-llm-thread--clean-body input)))))

(ert-deftest mu4e-llm-test-clean-body-removes-original-message ()
  "Outlook 'Original Message' separator should be removed."
  ;; Pattern: ^-+\s-*Original Message\s-*-+$ - requires dashes on both ends
  (let ((input "My reply\n\n---------- Original Message ----------\n> Old content"))
    (should (equal "My reply"
                   (mu4e-llm-thread--clean-body input)))))

;;; ==========================================================================
;;; Address Formatting Tests (mu4e-llm-thread--format-address)
;;; ==========================================================================

(ert-deftest mu4e-llm-test-format-address-string ()
  "String addresses should pass through."
  (should (equal "test@example.com"
                 (mu4e-llm-thread--format-address "test@example.com"))))

(ert-deftest mu4e-llm-test-format-address-plist-full ()
  "Plist with name and email should format correctly."
  (should (equal "John Doe <john@example.com>"
                 (mu4e-llm-thread--format-address
                  '(:name "John Doe" :email "john@example.com")))))

(ert-deftest mu4e-llm-test-format-address-plist-email-only ()
  "Plist with only email should return email."
  (should (equal "john@example.com"
                 (mu4e-llm-thread--format-address
                  '(:email "john@example.com")))))

(ert-deftest mu4e-llm-test-format-address-cons-full ()
  "Old cons format (name . email) should work."
  (should (equal "Jane Doe <jane@example.com>"
                 (mu4e-llm-thread--format-address
                  '("Jane Doe" . "jane@example.com")))))

(ert-deftest mu4e-llm-test-format-address-cons-no-name ()
  "Cons with empty name should return just email."
  (should (equal "anon@example.com"
                 (mu4e-llm-thread--format-address
                  '("" . "anon@example.com")))))

(ert-deftest mu4e-llm-test-format-address-unknown ()
  "Unknown format should return 'unknown'."
  (should (equal "unknown"
                 (mu4e-llm-thread--format-address 12345))))

(ert-deftest mu4e-llm-test-format-addresses-list ()
  "List of addresses should be comma-separated."
  (should (equal "a@test.com, b@test.com"
                 (mu4e-llm-thread--format-addresses
                  '("a@test.com" "b@test.com")))))

;;; ==========================================================================
;;; Cache Tests (mu4e-llm--cache-*)
;;; ==========================================================================

(ert-deftest mu4e-llm-test-cache-key-generation ()
  "Cache key should combine message-id and count."
  (should (equal "msg123:5"
                 (mu4e-llm--cache-key "msg123" 5))))

(ert-deftest mu4e-llm-test-cache-set-and-get ()
  "Should be able to set and get cached values."
  (let ((mu4e-llm--summary-cache (make-hash-table :test 'equal))
        (mu4e-llm-cache-ttl 3600))
    (mu4e-llm--cache-set "test-key" "test-value")
    (should (equal "test-value"
                   (mu4e-llm--cache-get "test-key")))))

(ert-deftest mu4e-llm-test-cache-miss ()
  "Non-existent key should return nil."
  (let ((mu4e-llm--summary-cache (make-hash-table :test 'equal)))
    (should (null (mu4e-llm--cache-get "nonexistent")))))

(ert-deftest mu4e-llm-test-cache-expiry ()
  "Expired entries should return nil and be removed."
  (let ((mu4e-llm--summary-cache (make-hash-table :test 'equal))
        (mu4e-llm-cache-ttl 0))  ; Immediate expiry
    (mu4e-llm--cache-set "expire-key" "value")
    ;; Sleep briefly to ensure expiry
    (sleep-for 0.1)
    (should (null (mu4e-llm--cache-get "expire-key")))
    ;; Entry should be removed
    (should (null (gethash "expire-key" mu4e-llm--summary-cache)))))

;;; ==========================================================================
;;; Config Tests
;;; ==========================================================================

(ert-deftest mu4e-llm-test-config-defaults ()
  "Default config values should be sensible."
  (should (numberp mu4e-llm-temperature))
  (should (<= 0 mu4e-llm-temperature 1))
  (should (integerp mu4e-llm-max-tokens))
  (should (> mu4e-llm-max-tokens 0))
  (should (integerp mu4e-llm-max-thread-messages))
  (should (> mu4e-llm-max-thread-messages 0))
  (should (integerp mu4e-llm-cache-ttl))
  (should (> mu4e-llm-cache-ttl 0)))

(ert-deftest mu4e-llm-test-config-languages ()
  "Language list should have valid structure."
  (should (listp mu4e-llm-languages))
  (should (> (length mu4e-llm-languages) 0))
  (dolist (lang mu4e-llm-languages)
    (should (consp lang))
    (should (stringp (car lang)))
    (should (stringp (cdr lang)))))

;;; ==========================================================================
;;; Worker Tests
;;; ==========================================================================

(ert-deftest mu4e-llm-test-worker-creation ()
  "Workers should be created with correct fields."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0))
    (let ((worker (mu4e-llm--create-worker 'summary nil)))
      (should (mu4e-llm--worker-p worker))
      (should (eq 'summary (mu4e-llm--worker-type worker)))
      (should (mu4e-llm--worker-active worker))
      (should (stringp (mu4e-llm--worker-id worker))))))

(ert-deftest mu4e-llm-test-worker-unique-ids ()
  "Each worker should have a unique ID."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0))
    (let ((w1 (mu4e-llm--create-worker 'summary nil))
          (w2 (mu4e-llm--create-worker 'draft nil)))
      (should-not (equal (mu4e-llm--worker-id w1)
                         (mu4e-llm--worker-id w2))))))

(ert-deftest mu4e-llm-test-worker-finish ()
  "Finishing a worker should deactivate it and remove from table."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (callback-called nil))
    (let ((worker (mu4e-llm--create-worker
                   'summary nil
                   (lambda (success result)
                     (setq callback-called (cons success result))))))
      (mu4e-llm--worker-finish worker "done")
      (should-not (mu4e-llm--worker-active worker))
      (should (null (gethash (mu4e-llm--worker-id worker)
                             mu4e-llm--workers)))
      (should (equal '(t . "done") callback-called)))))

;;; ==========================================================================
;;; Chat Tests (mu4e-llm--chat)
;;; ==========================================================================

;; These are the first tests here that stub a function.  `llm-chat-streaming'
;; and `llm-make-chat-prompt' are only declared in mu4e-llm-core, so they are
;; unbound unless llm is installed; `cl-letf' binds them either way.
;;
;; `mu4e-llm--chat' opens with (unless (featurep 'llm) (require 'llm)), which
;; fails when llm is absent.  `features' cannot be let-bound around that:
;; it is not a special variable, so under lexical binding the binding is
;; lexical and `featurep' keeps reading the global list.  Stub `require'
;; instead.  The stubbed body requires nothing else.

(defmacro mu4e-llm-test--with-stubbed-llm (streaming-fn &rest body)
  "Run BODY with `llm-chat-streaming' bound to STREAMING-FN.
`llm-make-chat-prompt' returns its argument unchanged, and `require' is a
no-op so no real llm is loaded."
  (declare (indent 1) (debug t))
  `(let ((mu4e-llm-provider 'test-provider))
     (cl-letf (((symbol-function 'require) (lambda (&rest _) nil))
               ((symbol-function 'llm-make-chat-prompt) (lambda (p &rest _) p))
               ((symbol-function 'llm-chat-streaming) ,streaming-fn))
       ,@body)))

(ert-deftest mu4e-llm-test-chat-error-callback-takes-two-arguments ()
  "llm.el calls the error callback with an error type and a message.
A one-argument callback signals `wrong-number-of-arguments' instead of
reporting the provider's message."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (reported nil))
    (mu4e-llm-test--with-stubbed-llm
        (lambda (_provider _prompt _partial _done errcb)
          (funcall errcb 'llm-http-error "rate limited")
          'fake-request)
      (let ((worker (mu4e-llm--create-worker
                     'summary nil
                     (lambda (success result) (setq reported (cons success result))))))
        (mu4e-llm--chat worker "prompt" nil nil)
        (should (equal nil (car reported)))
        (should (string-match-p "rate limited" (cdr reported)))))))

(ert-deftest mu4e-llm-test-chat-error-message-is-a-string ()
  "The second argument is a message, not an error object.
`error-message-string' on it signals `wrong-type-argument', so it must
not be used to format the report."
  (should-error (error-message-string "rate limited")
                :type 'wrong-type-argument))

(ert-deftest mu4e-llm-test-chat-error-ignored-when-worker-inactive ()
  "An error arriving after an abort should not reach the callback."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (reported nil))
    (mu4e-llm-test--with-stubbed-llm
        (lambda (_provider _prompt _partial _done errcb)
          (funcall errcb 'llm-http-error "too late")
          'fake-request)
      (let ((worker (mu4e-llm--create-worker
                     'summary nil
                     (lambda (success result) (setq reported (cons success result))))))
        (setf (mu4e-llm--worker-active worker) nil)
        (mu4e-llm--chat worker "prompt" nil nil)
        (should (null reported))))))

(ert-deftest mu4e-llm-test-chat-success-path ()
  "A successful run reaches on-partial and on-complete, and stores the request."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (partials nil)
        (completed nil))
    (mu4e-llm-test--with-stubbed-llm
        (lambda (_provider _prompt partial done _errcb)
          (funcall partial "par")
          (funcall partial "partial text")
          (funcall done "ignored")
          'fake-request)
      (let ((worker (mu4e-llm--create-worker 'summary nil)))
        (mu4e-llm--chat worker "prompt"
                        (lambda (text) (push text partials))
                        (lambda (text) (setq completed text)))
        (should (equal '("partial text" "par") partials))
        (should (equal "partial text" completed))
        (should (eq 'fake-request (mu4e-llm--worker-llm-request worker)))))))

(ert-deftest mu4e-llm-test-chat-passes-provider-and-prompt ()
  "The resolved provider and the prompt reach `llm-chat-streaming'."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (seen nil))
    (mu4e-llm-test--with-stubbed-llm
        (lambda (provider prompt &rest _) (setq seen (cons provider prompt)) nil)
      (mu4e-llm--chat (mu4e-llm--create-worker 'summary nil) "the prompt" nil nil)
      (should (eq 'test-provider (car seen)))
      (should (equal "the prompt" (cdr seen))))))

(ert-deftest mu4e-llm-test-chat-streaming-contract ()
  "Pin the real `llm-chat-streaming' arity, when llm is installed.
The stubs above pin this package's assumption about llm.el rather than
llm.el itself.  Four arguments is too few; five reaches the nil-provider
method and signals something else.  `func-arity' cannot be used here
because `llm-chat-streaming' is a generic and reports (1 . many)."
  ;; The Makefile runs emacs with -Q, so package.el is not initialised and
  ;; an installed llm is not yet on the load path.  Try that before giving
  ;; up, or this test would skip everywhere, including CI.
  (skip-unless (or (require 'llm nil t)
                   (progn (require 'package)
                          (package-initialize)
                          (require 'llm nil t))))
  (let ((cb (lambda (&rest _) nil)))
    (should-error (llm-chat-streaming nil "p" cb cb)
                  :type 'wrong-number-of-arguments)
    (let ((err (should-error (llm-chat-streaming nil "p" cb cb cb))))
      (should-not (eq (car err) 'wrong-number-of-arguments)))))

;;; ==========================================================================
;;; Summary Regenerate Tests (mu4e-llm-summary-regenerate)
;;; ==========================================================================

(defun mu4e-llm-test--thread (&optional id count)
  "Build a minimal thread struct for tests.
ID defaults to \"m1\" and COUNT to 1."
  (make-mu4e-llm-thread
   :message-id (or id "m1")
   :subject "Test subject"
   :messages nil
   :participant-count 1
   :message-count (or count 1)))

(defun mu4e-llm-test--thread-with-message (&optional body-text)
  "Build a thread carrying one real message.
`mu4e-llm-draft--prepare-buffer' reads the last message\='s sender and body,
so the draft tests cannot use the empty `mu4e-llm-test--thread'."
  (make-mu4e-llm-thread
   :message-id "m1"
   :subject "Test subject"
   :messages (list (make-mu4e-llm-thread-message
                    :from "Someone <someone@example.org>"
                    :to "me@example.org"
                    :date "2026-01-01"
                    :subject "Test subject"
                    :body (or body-text "THREAD-BODY-MARKER")))
   :participant-count 2
   :message-count 1))

(defmacro mu4e-llm-test--capturing-chat-prompt (captured &rest body)
  "Run BODY with the llm layer stubbed, recording each prompt in CAPTURED.
Each entry is the full argument list `llm-make-chat-prompt' received, so a
test can assert on the keyword arguments and not only on the content."
  (declare (indent 1) (debug t))
  `(let ((mu4e-llm-provider 'test-provider)
         (real-require (symbol-function 'require)))
     (cl-letf (;; Only `llm' is faked.  A blanket no-op breaks org-mode,
               ;; which loads parts of itself on demand, and the draft
               ;; buffer derives from org-mode.
               ((symbol-function 'require)
                (lambda (feature &rest args)
                  (unless (eq feature 'llm)
                    (apply real-require feature args))))
               ((symbol-function 'llm-make-chat-prompt)
                (lambda (&rest args) (push args ,captured) (car args)))
               ((symbol-function 'llm-chat-streaming)
                (lambda (&rest _) 'fake-request))
               ((symbol-function 'pop-to-buffer) (lambda (b &rest _) b))
               ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
       ,@body)))

(defun mu4e-llm-test--context-of (args)
  "Return the :context keyword from a captured ARGS list."
  (plist-get (cdr args) :context))

(defmacro mu4e-llm-test--in-summary-buffer (msg type &rest body)
  "Prepare a summary buffer for MSG and TYPE, then run BODY inside it."
  (declare (indent 2) (debug t))
  `(let ((mu4e-llm--workers (make-hash-table :test 'equal))
         (mu4e-llm--worker-counter 0)
         (mu4e-llm--summary-cache (make-hash-table :test 'equal)))
     (cl-letf (((symbol-function 'mu4e-llm-thread-extract)
                (lambda (_m) (mu4e-llm-test--thread)))
               ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                (lambda (_t) "context"))
               ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
       (let ((buf (mu4e-llm-summary--prepare-buffer ,msg (mu4e-llm-test--thread) ,type)))
         (unwind-protect
             (with-current-buffer buf ,@body)
           (kill-buffer buf))))))

(ert-deftest mu4e-llm-test-summary-regenerate-starts-a-new-call ()
  "Regenerate should start another summary, not print an instruction."
  (let ((called nil))
    (mu4e-llm-test--in-summary-buffer '(:docid 1) 'standard
      (cl-letf (((symbol-function 'mu4e-llm--chat)
                 (lambda (_w prompt &rest _) (setq called prompt) nil))
                ((symbol-function 'mu4e-llm-thread-extract)
                 (lambda (_m) (mu4e-llm-test--thread)))
                ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                 (lambda (_t) "context"))
                ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
        (mu4e-llm-summary-regenerate)
        (should called)))))

(ert-deftest mu4e-llm-test-summary-regenerate-keeps-the-type ()
  "An executive summary should regenerate as executive, not as standard."
  (let ((seen nil))
    (mu4e-llm-test--in-summary-buffer '(:docid 1) 'executive
      (cl-letf (((symbol-function 'mu4e-llm--chat)
                 (lambda (worker &rest _) (setq seen (mu4e-llm--worker-type worker)) nil))
                ((symbol-function 'mu4e-llm-thread-extract)
                 (lambda (_m) (mu4e-llm-test--thread)))
                ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                 (lambda (_t) "context"))
                ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
        (mu4e-llm-summary-regenerate)
        (should (eq 'executive-summary seen))))))

(ert-deftest mu4e-llm-test-summary-regenerate-clears-the-cache ()
  "Regenerate drops the cached entry, so the rerun is a real call."
  (mu4e-llm-test--in-summary-buffer '(:docid 1) 'standard
    (let ((key (mu4e-llm--cache-key "m1" 1)))
      (mu4e-llm--cache-set key "stale summary")
      (should (mu4e-llm--cache-get key))
      (cl-letf (((symbol-function 'mu4e-llm--chat) (lambda (&rest _) nil))
                ((symbol-function 'mu4e-llm-thread-extract)
                 (lambda (_m) (mu4e-llm-test--thread)))
                ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                 (lambda (_t) "context"))
                ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
        (mu4e-llm-summary-regenerate))
      (should-not (mu4e-llm--cache-get key)))))

(ert-deftest mu4e-llm-test-summary-regenerate-aborts-the-running-worker ()
  "A summary still streaming should be aborted before the rerun."
  (let ((aborted nil))
    (mu4e-llm-test--in-summary-buffer '(:docid 1) 'standard
      (setq mu4e-llm-summary--current-worker
            (mu4e-llm--create-worker 'summary nil))
      (cl-letf (((symbol-function 'mu4e-llm--abort-worker)
                 (lambda (w) (setq aborted w)))
                ((symbol-function 'mu4e-llm--chat) (lambda (&rest _) nil))
                ((symbol-function 'mu4e-llm-thread-extract)
                 (lambda (_m) (mu4e-llm-test--thread)))
                ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                 (lambda (_t) "context"))
                ((symbol-function 'pop-to-buffer) (lambda (b &rest _) (set-buffer b) b)))
        (mu4e-llm-summary-regenerate)
        (should aborted)))))

(ert-deftest mu4e-llm-test-summary-regenerate-outside-a-summary-buffer ()
  "Regenerate elsewhere should say so rather than fail obscurely."
  (with-temp-buffer
    (should-error (mu4e-llm-summary-regenerate) :type 'user-error)))

(ert-deftest mu4e-llm-test-summary-state-survives-finalize ()
  "The stored message and type outlive a completed summary."
  (mu4e-llm-test--in-summary-buffer '(:docid 7) 'executive
    (mu4e-llm-summary--finalize (current-buffer) "done")
    (should (equal '(:docid 7) mu4e-llm-summary--current-message))
    (should (eq 'executive mu4e-llm-summary--current-type))))

;;; ==========================================================================
;;; Per-operation Model Tests (mu4e-llm-operation-models)
;;; ==========================================================================

;; A stand-in for an llm.el provider.  The real structs are not available
;; here, and all that matters is that it is a record with a chat-model slot,
;; which every llm.el provider has.
(cl-defstruct mu4e-llm-test-provider chat-model key)

(defmacro mu4e-llm-test--with-provider (table &rest body)
  "Run BODY with a stub provider and `mu4e-llm-operation-models' set to TABLE."
  (declare (indent 1) (debug t))
  `(let ((mu4e-llm-provider (make-mu4e-llm-test-provider
                             :chat-model "base-model" :key "k"))
         (mu4e-llm-operation-models ,table))
     ,@body))

(ert-deftest mu4e-llm-test-models-absent-type-is-untouched ()
  "An operation not in the table resolves to the provider unchanged.
This is the guard that the table cannot alter existing behaviour."
  (mu4e-llm-test--with-provider '((draft . (:model "other")))
    (should (eq mu4e-llm-provider (mu4e-llm--provider-for 'summary)))))

(ert-deftest mu4e-llm-test-models-empty-table-is-untouched ()
  "An empty table behaves exactly as no table."
  (mu4e-llm-test--with-provider nil
    (should (eq mu4e-llm-provider (mu4e-llm--provider-for 'summary)))))

(ert-deftest mu4e-llm-test-models-listed-type-gets-its-model ()
  "A listed operation resolves to a provider carrying the table's model."
  (mu4e-llm-test--with-provider '((summary . (:model "fast-model")))
    (should (equal "fast-model"
                   (mu4e-llm-test-provider-chat-model
                    (mu4e-llm--provider-for 'summary))))))

(ert-deftest mu4e-llm-test-models-does-not-mutate-the-shared-provider ()
  "Resolution copies.  The provider object is shared with other tools."
  (mu4e-llm-test--with-provider '((summary . (:model "fast-model")))
    (let ((resolved (mu4e-llm--provider-for 'summary)))
      (should-not (eq resolved mu4e-llm-provider))
      (should (equal "base-model"
                     (mu4e-llm-test-provider-chat-model mu4e-llm-provider)))
      (should (equal "fast-model"
                     (mu4e-llm-test-provider-chat-model resolved))))))

(ert-deftest mu4e-llm-test-models-reasoning-only-keeps-the-base-model ()
  "An entry with a reasoning level but no model leaves the model alone."
  (mu4e-llm-test--with-provider '((summary . (:reasoning "low")))
    (should (equal "base-model"
                   (mu4e-llm-test-provider-chat-model
                    (mu4e-llm--provider-for 'summary))))
    (should (equal '(("reasoning_effort" . "low"))
                   (mu4e-llm--reasoning-params-for 'summary)))))

(ert-deftest mu4e-llm-test-models-model-only-sends-no-reasoning ()
  "An entry with a model but no reasoning sends no reasoning_effort."
  (mu4e-llm-test--with-provider '((summary . (:model "fast-model")))
    (should (null (mu4e-llm--reasoning-params-for 'summary)))))

(ert-deftest mu4e-llm-test-models-unknown-type-in-table-is-ignored ()
  "A table naming an operation that does not exist changes nothing."
  (mu4e-llm-test--with-provider '((not-a-real-operation . (:model "x")))
    (should (eq mu4e-llm-provider (mu4e-llm--provider-for 'summary)))
    (should (null (mu4e-llm--reasoning-params-for 'summary)))))

(ert-deftest mu4e-llm-test-models-every-real-worker-type-resolves ()
  "All six operation types resolve without error, so none is missed."
  (mu4e-llm-test--with-provider
      '((summary           . (:model "a" :reasoning "low"))
        (executive-summary . (:model "a" :reasoning "low"))
        (translate         . (:model "a" :reasoning "low"))
        (draft             . (:model "b" :reasoning "medium"))
        (compose           . (:model "b" :reasoning "medium"))
        (refine            . (:model "b" :reasoning "medium")))
    (dolist (type '(summary executive-summary translate draft compose refine))
      (should (mu4e-llm-test-provider-p (mu4e-llm--provider-for type)))
      (should (mu4e-llm--reasoning-params-for type)))))

(ert-deftest mu4e-llm-test-models-reasoning-reaches-the-prompt ()
  "The reasoning level is sent as a non-standard parameter."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (seen-params 'unset)
        (seen-model nil))
    (let ((mu4e-llm-operation-models '((summary . (:model "fast" :reasoning "low")))))
      (let ((mu4e-llm-provider (make-mu4e-llm-test-provider
                                :chat-model "base-model" :key "k")))
        (cl-letf (((symbol-function 'require) (lambda (&rest _) nil))
                  ((symbol-function 'llm-make-chat-prompt)
                   (lambda (p &rest args)
                     (setq seen-params (plist-get args :non-standard-params))
                     p))
                  ((symbol-function 'llm-chat-streaming)
                   (lambda (provider &rest _)
                     (setq seen-model (mu4e-llm-test-provider-chat-model provider))
                     nil)))
          (mu4e-llm--chat (mu4e-llm--create-worker 'summary nil) "p" nil nil)
          (should (equal '(("reasoning_effort" . "low")) seen-params))
          (should (equal "fast" seen-model)))))))

(ert-deftest mu4e-llm-test-models-explicit-provider-still-wins-over-fallback ()
  "`mu4e-llm-provider' beats the fallback variable, and the table applies on top."
  (let* ((fallback (make-mu4e-llm-test-provider :chat-model "fallback" :key "k"))
         (mu4e-llm-test--fallback fallback)
         (mu4e-llm-provider (make-mu4e-llm-test-provider :chat-model "explicit" :key "k"))
         (mu4e-llm-provider-fallback-variable 'mu4e-llm-test--fallback)
         (mu4e-llm-operation-models '((summary . (:model "from-table")))))
    (ignore mu4e-llm-test--fallback)
    (should (equal "from-table"
                   (mu4e-llm-test-provider-chat-model
                    (mu4e-llm--provider-for 'summary))))
    (should (equal "explicit"
                   (mu4e-llm-test-provider-chat-model
                    (mu4e-llm--provider-for 'draft))))))

;;; ==========================================================================
;;; Keymap Prefix Tests (mu4e-llm-setup)
;;; ==========================================================================

;; Must be special: `mu4e-llm-setup' finds the parent map with `boundp' and
;; `symbol-value', which only see dynamic bindings.  A plain `let' in this
;; lexically bound file would be invisible to it.
(defvar mu4e-llm-test--parent nil
  "A stand-in parent prefix map for the setup tests.")

(defmacro mu4e-llm-test--with-setup (prefix parent suffix &rest body)
  "Run `mu4e-llm-setup' with PREFIX, PARENT and SUFFIX, then run BODY.
The mode map is fresh each time so bindings do not leak between tests."
  (declare (indent 3) (debug t))
  `(let ((mu4e-llm-keymap-prefix ,prefix)
         (mu4e-llm-parent-keymap ,parent)
         (mu4e-llm-parent-keymap-suffix ,suffix)
         (mu4e-llm-mode-map (make-sparse-keymap)))
     (cl-letf (((symbol-function 'message) (lambda (&rest _) nil)))
       (mu4e-llm-setup))
     ,@body))

(ert-deftest mu4e-llm-test-setup-binds-into-a-parent-map ()
  "The suffix is bound in the configured parent map."
  (let ((mu4e-llm-test--parent (make-sparse-keymap)))
    (mu4e-llm-test--with-setup "C-c a e" 'mu4e-llm-test--parent "e"
      (should (eq mu4e-llm-map
                  (lookup-key mu4e-llm-test--parent (kbd "e")))))))

(ert-deftest mu4e-llm-test-setup-without-a-parent-map ()
  "With no parent map bound, setup still binds the local prefix."
  (mu4e-llm-test--with-setup "C-c a e" 'mu4e-llm-test--no-such-map "e"
    (should (eq mu4e-llm-map
                (lookup-key mu4e-llm-mode-map (kbd "C-c a e"))))))

(ert-deftest mu4e-llm-test-setup-accepts-a-bare-key ()
  "A single unmodified key works, which the old C-c a regex refused."
  (mu4e-llm-test--with-setup "i" nil nil
    (should (eq mu4e-llm-map (lookup-key mu4e-llm-mode-map (kbd "i"))))
    (should (eq 'mu4e-llm-summarize (lookup-key mu4e-llm-mode-map (kbd "i s"))))))

(ert-deftest mu4e-llm-test-setup-accepts-an-unrelated-prefix ()
  "A prefix that is not C-c a shaped binds correctly."
  (mu4e-llm-test--with-setup "C-, e" nil nil
    (should (eq mu4e-llm-map (lookup-key mu4e-llm-mode-map (kbd "C-, e"))))))

(ert-deftest mu4e-llm-test-setup-keeps-the-old-prefix-working ()
  "The previous default still binds, so existing users are unaffected."
  (mu4e-llm-test--with-setup "C-c a e" nil nil
    (should (eq 'mu4e-llm-summarize
                (lookup-key mu4e-llm-mode-map (kbd "C-c a e s"))))))

(ert-deftest mu4e-llm-test-setup-reaches-every-command ()
  "Every command in `mu4e-llm-map' is reachable through the prefix."
  (mu4e-llm-test--with-setup "i" nil nil
    (map-keymap
     (lambda (event def)
       (should (eq def (lookup-key mu4e-llm-mode-map
                                   (vconcat (kbd "i") (vector event))))))
     mu4e-llm-map)))

(ert-deftest mu4e-llm-test-setup-is-idempotent ()
  "Calling setup twice leaves the same bindings."
  (let ((mu4e-llm-test--parent (make-sparse-keymap)))
    (mu4e-llm-test--with-setup "i" 'mu4e-llm-test--parent "e"
      (cl-letf (((symbol-function 'message) (lambda (&rest _) nil)))
        (mu4e-llm-setup))
      (should (eq mu4e-llm-map (lookup-key mu4e-llm-mode-map (kbd "i"))))
      (should (eq mu4e-llm-map (lookup-key mu4e-llm-test--parent (kbd "e"))))
      (should (eq 'mu4e-llm-summarize
                  (lookup-key mu4e-llm-mode-map (kbd "i s")))))))

(ert-deftest mu4e-llm-test-help-names-the-configured-prefix ()
  "The help text should not advertise a prefix that is not in use."
  (let ((mu4e-llm-keymap-prefix "i"))
    (should (string-match-p "\\bi\\b" (mu4e-llm--help-text))))
  (let ((mu4e-llm-keymap-prefix "C-, e"))
    (should (string-match-p "C-, e" (mu4e-llm--help-text)))
    (should-not (string-match-p "C-c a e prefix" (mu4e-llm--help-text)))))

;;; ==========================================================================
;;; Prompt File Tests (mu4e-llm-prompts)
;;; ==========================================================================

(defconst mu4e-llm-test--prompt-variables
  '(mu4e-llm-draft-reply-prompt
    mu4e-llm-draft-refine-prompt
    mu4e-llm-draft-compose-prompt
    mu4e-llm-translate-message-prompt
    mu4e-llm-translate-thread-prompt
    mu4e-llm-translate-text-prompt
    mu4e-llm-summary-standard-prompt
    mu4e-llm-summary-executive-prompt)
  "Every prompt the package sends, as the README documents them.")

(ert-deftest mu4e-llm-test-prompts-all-bound ()
  "Loading mu4e-llm-prompts should bind every documented prompt."
  (dolist (var mu4e-llm-test--prompt-variables)
    (should (boundp var))
    (should (stringp (symbol-value var)))))

(ert-deftest mu4e-llm-test-prompts-left-config ()
  "No prompt should still be defined by mu4e-llm-config.
The point of the prompts file is that there is one place to look."
  (let ((config (expand-file-name
                 "mu4e-llm-config.el"
                 (file-name-directory (locate-library "mu4e-llm-config")))))
    (when (file-readable-p config)
      (with-temp-buffer
        (insert-file-contents config)
        (dolist (var mu4e-llm-test--prompt-variables)
          (goto-char (point-min))
          (should-not (search-forward (format "(defcustom %s" var) nil t)))))))

(ert-deftest mu4e-llm-test-prompt-substitutes-named-letters ()
  "Each named letter should be replaced by its value, order independent."
  (should (equal "B then A"
                 (mu4e-llm--prompt "%b then %a"
                                   '((?a . "A") (?b . "B"))))))

(ert-deftest mu4e-llm-test-prompt-leaves-unknown-letter ()
  "An unsupplied placeholder stays put rather than signalling.
A user who edits a prompt cannot break the call this way."
  (should (equal "A and %z"
                 (mu4e-llm--prompt "%a and %z" '((?a . "A"))))))

(ert-deftest mu4e-llm-test-prompt-renders-literal-percent ()
  "A doubled percent is how a prompt writes a literal percent sign."
  (should (equal "50% off"
                 (mu4e-llm--prompt "50%% off" '((?a . "A"))))))

(ert-deftest mu4e-llm-test-prompt-reply-carries-identity-and-thread ()
  "A rendered reply prompt should contain the sender and the thread."
  (let ((rendered (mu4e-llm--prompt
                   mu4e-llm-draft-reply-prompt
                   '((?n . "Ada") (?e . "ada@example.org") (?p . "")
                     (?t . "THREAD-MARKER") (?i . "")))))
    (should (string-match-p "Ada" rendered))
    (should (string-match-p "ada@example.org" rendered))
    (should (string-match-p "THREAD-MARKER" rendered))
    (should-not (string-match-p "%" rendered))))

(ert-deftest mu4e-llm-test-prompt-empty-subject-leaves-no-placeholder ()
  "A message with no subject must not leak its placeholder into the prompt.
`mu4e-message-field' returns nil for a missing subject, and nil counts as
missing to `format-spec', so the call site passes an empty string."
  (let ((rendered (mu4e-llm--prompt
                   mu4e-llm-translate-message-prompt
                   '((?l . "German") (?f . "someone@example.org")
                     (?u . "") (?b . "BODY-MARKER")))))
    (should (string-match-p "BODY-MARKER" rendered))
    (should (string-match-p "Subject: *\n" rendered))
    (should-not (string-match-p "%u" rendered))))

;;; ==========================================================================
;;; Voice Tests (mu4e-llm-prompt-voice)
;;;
;;; Wiring tests prove where the voice goes.  Deletion guards only prove a
;;; sentence is still present -- they cannot tell "reply in the language of
;;; the original" from "ignore the language of the original".  Nothing here
;;; can tell whether a draft reads well; that judgement is the user's, which
;;; is what the plainer key is for.
;;; ==========================================================================

(ert-deftest mu4e-llm-test-voice-reaches-writing-operations ()
  "Drafting, composing and refining each get the voice as system prompt."
  (dolist (type '(draft compose refine))
    (should (equal mu4e-llm-prompt-voice (mu4e-llm--voice-for type)))))

(ert-deftest mu4e-llm-test-voice-skips-reporting-operations ()
  "Summarising and translating report what someone else wrote.
Telling the model to write in the user's voice would be wrong there."
  (dolist (type '(summary executive-summary translate))
    (should-not (mu4e-llm--voice-for type))))

(ert-deftest mu4e-llm-test-chat-passes-voice-as-context ()
  "A draft worker's chat prompt carries the voice in :context."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (captured nil))
    (mu4e-llm-test--capturing-chat-prompt captured
      (mu4e-llm--chat (mu4e-llm--create-worker 'draft nil) "task" nil nil))
    (should (equal mu4e-llm-prompt-voice
                   (mu4e-llm-test--context-of (car captured))))))

(ert-deftest mu4e-llm-test-chat-passes-no-context-for-summary ()
  "A summary worker's chat prompt carries no system prompt."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (captured nil))
    (mu4e-llm-test--capturing-chat-prompt captured
      (mu4e-llm--chat (mu4e-llm--create-worker 'summary nil) "task" nil nil))
    (should-not (mu4e-llm-test--context-of (car captured)))))

(ert-deftest mu4e-llm-test-chat-passes-no-context-for-translate ()
  "A translate worker's chat prompt carries no system prompt."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (captured nil))
    (mu4e-llm-test--capturing-chat-prompt captured
      (mu4e-llm--chat (mu4e-llm--create-worker 'translate nil) "task" nil nil))
    (should-not (mu4e-llm-test--context-of (car captured)))))

(ert-deftest mu4e-llm-test-personas-are-gone ()
  "The persona variables were removed in favour of one voice."
  (should-not (boundp 'mu4e-llm-draft-persona))
  (should-not (boundp 'mu4e-llm-draft-persona-descriptions)))

(ert-deftest mu4e-llm-test-draft-reply-still-reaches-the-provider ()
  "Removing the personas must not have broken the drafting call site."
  (let ((mu4e-llm--workers (make-hash-table :test 'equal))
        (mu4e-llm--worker-counter 0)
        (captured nil))
    (cl-letf (((symbol-function 'mu4e-llm-thread-extract)
               (lambda (_m) (mu4e-llm-test--thread-with-message)))
              ((symbol-function 'mu4e-llm-thread-to-prompt-context)
               (lambda (_t) "THREAD-MARKER"))
              ((symbol-function 'mu4e-message-at-point) (lambda () 'fake-msg)))
      (mu4e-llm-test--capturing-chat-prompt captured
        (mu4e-llm-draft-reply)))
    (should captured)
    (should (string-match-p "THREAD-MARKER" (car (car captured))))
    (should (equal mu4e-llm-prompt-voice
                   (mu4e-llm-test--context-of (car captured))))
    (kill-buffer mu4e-llm-draft-buffer-name)))

;;; --- Deletion guards ---

(ert-deftest mu4e-llm-test-guard-voice-names-the-language-rule ()
  "Deletion guard: the voice still tells the model which language to use."
  (should (string-match-p "same language" mu4e-llm-prompt-voice)))

(ert-deftest mu4e-llm-test-guard-voice-asks-for-the-email-only ()
  "Deletion guard: the voice still forbids preamble and commentary."
  (should (string-match-p "Return only the email body" mu4e-llm-prompt-voice)))

(ert-deftest mu4e-llm-test-guard-no-prompt-asks-for-bullets ()
  "Deletion guard: prose is the default; bullets are opt-in.
This is the instruction that made every generated reply a bullet list."
  (dolist (prompt (list mu4e-llm-draft-reply-prompt
                        mu4e-llm-draft-compose-prompt))
    (should-not (string-match-p "bullet" prompt))))

;;; ==========================================================================
;;; Refinement Tests (refine, shorten, polite)
;;; ==========================================================================

(defmacro mu4e-llm-test--in-draft-buffer (&rest body)
  "Open a draft buffer with the llm layer stubbed, then run BODY inside it."
  (declare (indent 0) (debug t))
  `(let ((mu4e-llm--workers (make-hash-table :test 'equal))
         (mu4e-llm--worker-counter 0)
         (captured nil))
     (cl-letf (((symbol-function 'mu4e-llm-thread-extract)
                (lambda (_m) (mu4e-llm-test--thread-with-message)))
               ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                (lambda (_t) "THREAD-MARKER"))
               ((symbol-function 'mu4e-message-at-point) (lambda () 'fake-msg)))
       (mu4e-llm-test--capturing-chat-prompt captured
         (mu4e-llm-draft-reply)
         (unwind-protect
             (with-current-buffer mu4e-llm-draft-buffer-name
               (setq captured nil)
               ,@body)
           ;; Tolerate an already-dead buffer: finalize kills it on success,
           ;; which is the behaviour several of these tests are checking.
           (when-let ((buf (get-buffer mu4e-llm-draft-buffer-name)))
             (kill-buffer buf)))))))

(ert-deftest mu4e-llm-test-shorten-instruction-is-a-variable ()
  "The fixed instructions live in the prompts file, not inline in the code.
A user who wants shorten to behave differently edits one variable."
  (should (stringp mu4e-llm-draft-shorten-instruction))
  (should (stringp mu4e-llm-draft-polite-instruction)))

(ert-deftest mu4e-llm-test-shorten-sends-its-instruction ()
  "Pressing shorten reaches the provider with the shorten instruction."
  (mu4e-llm-test--in-draft-buffer
    (mu4e-llm-draft-shorten)
    (should captured)
    (should (string-match-p (regexp-quote mu4e-llm-draft-shorten-instruction)
                            (car (car captured))))))

(ert-deftest mu4e-llm-test-polite-sends-its-instruction ()
  "Pressing polite reaches the provider with the polite instruction."
  (mu4e-llm-test--in-draft-buffer
    (mu4e-llm-draft-make-polite)
    (should captured)
    (should (string-match-p (regexp-quote mu4e-llm-draft-polite-instruction)
                            (car (car captured))))))

(ert-deftest mu4e-llm-test-refine-carries-the-voice ()
  "A refinement must not undo the voice the first draft was written in."
  (mu4e-llm-test--in-draft-buffer
    (mu4e-llm-draft--refine-with-instruction "make it shorter")
    (should (equal mu4e-llm-prompt-voice
                   (mu4e-llm-test--context-of (car captured))))))

(ert-deftest mu4e-llm-test-refine-carries-instruction-and-draft ()
  "The refine prompt contains both the instruction and the current draft."
  (mu4e-llm-test--in-draft-buffer
    (let ((inhibit-read-only t))
      (goto-char mu4e-llm-draft--draft-start)
      (insert "DRAFT-MARKER"))
    (mu4e-llm-draft--refine-with-instruction "INSTRUCTION-MARKER")
    (let ((prompt (car (car captured))))
      (should (string-match-p "INSTRUCTION-MARKER" prompt))
      (should (string-match-p "DRAFT-MARKER" prompt)))))

;;; --- Deletion guards ---

(ert-deftest mu4e-llm-test-guard-refine-does-not-pin-the-structure ()
  "Deletion guard: \"keep the same basic structure\" fought every
shortening instruction it was sent with."
  (should-not (string-match-p "same basic structure"
                              mu4e-llm-draft-refine-prompt)))

(ert-deftest mu4e-llm-test-guard-refine-protects-greeting-and-signoff ()
  "Deletion guard: refine still knows an email has parts.
\"Make it one line\" means the body, not the greeting and sign-off too."
  (should (string-match-p "greeting" mu4e-llm-draft-refine-prompt))
  (should (string-match-p "sign-off" mu4e-llm-draft-refine-prompt)))

;;; ==========================================================================
;;; Draft Key Tests (plainer, bullets, and what they must not shadow)
;;; ==========================================================================

(ert-deftest mu4e-llm-test-plainer-is-bound ()
  "Plainer is on C-c C-n."
  (should (eq 'mu4e-llm-draft-plainer
              (lookup-key mu4e-llm-draft-mode-map (kbd "C-c C-n")))))

(ert-deftest mu4e-llm-test-bullets-is-bound ()
  "Bullets is on C-c C-b."
  (should (eq 'mu4e-llm-draft-bullets
              (lookup-key mu4e-llm-draft-mode-map (kbd "C-c C-b")))))

(ert-deftest mu4e-llm-test-insert-link-survives ()
  "C-c C-l must still insert an org link.
The draft map inherits org-mode-map, and a draft is org syntax carrying
[[url][text]] links, so this is the one org key worth protecting."
  (mu4e-llm-test--in-draft-buffer
    (should (eq 'org-insert-link (key-binding (kbd "C-c C-l"))))))

(ert-deftest mu4e-llm-test-existing-draft-keys-survive ()
  "The six bindings that were already there still resolve."
  (dolist (pair '(("C-c C-r" . mu4e-llm-draft-refine)
                  ("C-c C-s" . mu4e-llm-draft-shorten)
                  ("C-c C-p" . mu4e-llm-draft-make-polite)
                  ("C-c C-f" . mu4e-llm-draft-finalize)
                  ("C-c C-t" . mu4e-llm-draft-toggle-summary)
                  ("C-c C-k" . mu4e-llm-draft-cancel)))
    (should (eq (cdr pair)
                (lookup-key mu4e-llm-draft-mode-map (kbd (car pair)))))))

(ert-deftest mu4e-llm-test-plainer-sends-its-instruction ()
  "Pressing plainer reaches the provider with the plainer instruction."
  (mu4e-llm-test--in-draft-buffer
    (mu4e-llm-draft-plainer)
    (should captured)
    (should (string-match-p (regexp-quote mu4e-llm-draft-plainer-instruction)
                            (car (car captured))))))

(ert-deftest mu4e-llm-test-bullets-sends-its-instruction ()
  "Pressing bullets reaches the provider with the bullets instruction."
  (mu4e-llm-test--in-draft-buffer
    (mu4e-llm-draft-bullets)
    (should captured)
    (should (string-match-p (regexp-quote mu4e-llm-draft-bullets-instruction)
                            (car (car captured))))))

(ert-deftest mu4e-llm-test-help-line-keeps-its-sentinel ()
  "Four functions find the end of the draft by searching for \"\\n\\n[C-c\".
Extending the help line must not break that prefix, or streaming output
would overwrite the legend -- and the draft boundary would move."
  (mu4e-llm-test--in-draft-buffer
    (should (save-excursion
              (goto-char (point-min))
              (search-forward "\n\n[C-c" nil t)))))

(ert-deftest mu4e-llm-test-help-line-names-the-new-keys ()
  "Deletion guard: the legend advertises all eight keys."
  (mu4e-llm-test--in-draft-buffer
    (let ((text (buffer-substring-no-properties (point-min) (point-max))))
      (dolist (key '("C-c C-f" "C-c C-r" "C-c C-s" "C-c C-p"
                     "C-c C-n" "C-c C-b" "C-c C-k"))
        (should (string-match-p (regexp-quote key) text))))))

;;; ==========================================================================
;;; Summary Prompt Tests
;;; ==========================================================================

(ert-deftest mu4e-llm-test-guard-summary-asks-for-blank-lines ()
  "Deletion guard: the standard summary still asks for separated sections.
Without it the model returns one undifferentiated run of bullets."
  (should (string-match-p "blank line" mu4e-llm-summary-standard-prompt)))

(ert-deftest mu4e-llm-test-guard-summary-names-its-sections ()
  "Deletion guard: the section headings are still spelled out."
  (dolist (heading '("What this is about" "Key points" "Decisions"
                     "Action items" "Where it stands"))
    (should (string-match-p (regexp-quote heading)
                            mu4e-llm-summary-standard-prompt))))

(ert-deftest mu4e-llm-test-executive-summary-untouched ()
  "Two or three sentences have no sections to separate, so the executive
summary keeps asking for exactly that."
  (should (string-match-p "2-3 sentences" mu4e-llm-summary-executive-prompt))
  (should-not (string-match-p "blank line" mu4e-llm-summary-executive-prompt)))

(ert-deftest mu4e-llm-test-summary-prompt-carries-the-thread ()
  "Both summary prompts still render the thread into the request."
  (dolist (template (list mu4e-llm-summary-standard-prompt
                          mu4e-llm-summary-executive-prompt))
    (let ((rendered (mu4e-llm--prompt template '((?t . "THREAD-MARKER")))))
      (should (string-match-p "THREAD-MARKER" rendered))
      (should-not (string-match-p "%t" rendered)))))

;;; ==========================================================================
;;; Focus and Reply-From-Summary Tests
;;; ==========================================================================

(defmacro mu4e-llm-test--with-real-windows (&rest body)
  "Run BODY with the llm layer stubbed but window handling left real.
Used by the tests that check which buffer ends up selected."
  (declare (indent 0) (debug t))
  `(let ((mu4e-llm-provider 'test-provider)
         (mu4e-llm--workers (make-hash-table :test 'equal))
         (mu4e-llm--worker-counter 0)
         (real-require (symbol-function 'require)))
     (cl-letf (((symbol-function 'require)
                (lambda (feature &rest args)
                  (unless (eq feature 'llm)
                    (apply real-require feature args))))
               ((symbol-function 'llm-make-chat-prompt) (lambda (p &rest _) p))
               ((symbol-function 'llm-chat-streaming) (lambda (&rest _) 'fake))
               ((symbol-function 'mu4e-llm-thread-extract)
                (lambda (_m) (mu4e-llm-test--thread-with-message)))
               ((symbol-function 'mu4e-llm-thread-to-prompt-context)
                (lambda (_t) "context"))
               ((symbol-function 'mu4e-message-at-point) (lambda () 'fake-msg)))
       ,@body)))

(ert-deftest mu4e-llm-test-summary-buffer-takes-focus ()
  "`i s' should leave point in the summary, not merely show it."
  (mu4e-llm-test--with-real-windows
    (unwind-protect
        (progn
          (mu4e-llm--summarize-message 'fake-msg 'standard)
          (should (equal mu4e-llm-summary-buffer-name (buffer-name))))
      (kill-buffer mu4e-llm-summary-buffer-name))))

(ert-deftest mu4e-llm-test-draft-buffer-takes-focus ()
  "The draft buffer has the same defect, and the same fix."
  (mu4e-llm-test--with-real-windows
    (unwind-protect
        (progn
          (mu4e-llm-draft-reply)
          (should (equal mu4e-llm-draft-buffer-name (buffer-name))))
      (kill-buffer mu4e-llm-draft-buffer-name))))

(ert-deftest mu4e-llm-test-draft-reply-uses-the-message-given ()
  "When handed a message, drafting must not consult point at all."
  (let ((asked nil) (used nil))
    (cl-letf (((symbol-function 'mu4e-message-at-point)
               (lambda () (setq asked t) 'from-point))
              ((symbol-function 'mu4e-llm-thread-extract)
               (lambda (m) (setq used m) (mu4e-llm-test--thread-with-message)))
              ((symbol-function 'mu4e-llm-draft--generate) (lambda (&rest _) nil)))
      (mu4e-llm-draft-reply nil 'explicit-msg)
      (should (eq 'explicit-msg used))
      (should-not asked))))

(ert-deftest mu4e-llm-test-draft-reply-still-defaults-to-point ()
  "With no message argument, drafting still replies to the message at point."
  (let ((used nil))
    (cl-letf (((symbol-function 'mu4e-message-at-point) (lambda () 'from-point))
              ((symbol-function 'mu4e-llm-thread-extract)
               (lambda (m) (setq used m) (mu4e-llm-test--thread-with-message)))
              ((symbol-function 'mu4e-llm-draft--generate) (lambda (&rest _) nil)))
      (mu4e-llm-draft-reply)
      (should (eq 'from-point used)))))

(ert-deftest mu4e-llm-test-reply-from-summary-passes-the-stored-message ()
  "`r' in a summary replies to the message that summary came from."
  (let ((got 'unset))
    (cl-letf (((symbol-function 'mu4e-llm-draft-reply)
               (lambda (&optional _instructions msg) (setq got msg))))
      (mu4e-llm-test--in-summary-buffer 'stored-msg 'standard
        (mu4e-llm-draft-reply-from-summary)))
    (should (eq 'stored-msg got))))

(ert-deftest mu4e-llm-test-reply-from-summary-outside-a-summary ()
  "Outside a summary buffer there is nothing to reply to."
  (with-temp-buffer
    (should-error (mu4e-llm-draft-reply-from-summary) :type 'user-error)))

(ert-deftest mu4e-llm-test-reply-from-summary-without-a-message ()
  "A summary buffer whose stored message is nil says so plainly."
  (mu4e-llm-test--in-summary-buffer nil 'standard
    (should-error (mu4e-llm-draft-reply-from-summary) :type 'user-error)))

(ert-deftest mu4e-llm-test-finalize-composes-from-the-stored-message ()
  "Finalize must not read the message at point.

`mu4e-compose-reply' replies to the message at point, and a draft buffer
has none.  Reaching the draft from a summary used to signal here, after
the draft text had already been destroyed."
  (let ((asked nil) (replied-to nil))
    (cl-letf (((symbol-function 'mu4e-message-at-point)
               (lambda (&rest _) (setq asked t) (user-error "No message at point")))
              ((symbol-function 'mu4e-compose-reply)
               (lambda (&rest _) (setq replied-to (mu4e-message-at-point))))
              ((symbol-function 'mu4e-llm--find-context-for-message) (lambda (_m) nil))
              ((symbol-function 'run-at-time) (lambda (&rest _) nil)))
      (mu4e-llm-test--in-draft-buffer
        (setq mu4e-llm-draft--original-message 'stored-msg)
        (mu4e-llm-draft-finalize)
        (should (eq 'stored-msg replied-to))
        (should-not asked)))))

(ert-deftest mu4e-llm-test-finalize-keeps-the-draft-when-composing-fails ()
  "A failed compose must not take the draft text with it."
  (cl-letf (((symbol-function 'mu4e-compose-reply)
             (lambda (&rest _) (error "compose exploded")))
            ((symbol-function 'mu4e-llm--find-context-for-message) (lambda (_m) nil))
            ((symbol-function 'run-at-time) (lambda (&rest _) nil)))
    (mu4e-llm-test--in-draft-buffer
      (setq mu4e-llm-draft--original-message 'stored-msg)
      (should-error (mu4e-llm-draft-finalize))
      (should (buffer-live-p (get-buffer mu4e-llm-draft-buffer-name))))))

(provide 'mu4e-llm-test)
;;; mu4e-llm-test.el ends here
