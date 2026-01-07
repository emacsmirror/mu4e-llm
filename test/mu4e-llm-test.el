;;; mu4e-llm-test.el --- Tests for mu4e-llm -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Dr. Sandeep Sadanandan

;;; Commentary:
;; Unit tests for mu4e-llm pure functions.

;;; Code:

(require 'ert)

;; Add parent directory to load-path for testing
(let ((dir (file-name-directory (or load-file-name buffer-file-name))))
  (add-to-list 'load-path (expand-file-name ".." dir)))

(require 'mu4e-llm-config)
(require 'mu4e-llm-thread)
(require 'mu4e-llm-core)

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

(ert-deftest mu4e-llm-test-config-persona ()
  "Default persona should be valid."
  (should (memq mu4e-llm-draft-persona
                '(professional friendly formal concise))))

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

(provide 'mu4e-llm-test)
;;; mu4e-llm-test.el ends here
