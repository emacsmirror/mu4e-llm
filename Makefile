# mu4e-llm Makefile
# Run tests, compile, and lint for MELPA package quality

EMACS ?= emacs
BATCH = $(EMACS) -batch -Q -L .

# Source files (excluding test files)
SRCS = mu4e-llm.el mu4e-llm-config.el mu4e-llm-prompts.el mu4e-llm-core.el \
       mu4e-llm-draft.el \
       mu4e-llm-summary.el mu4e-llm-thread.el mu4e-llm-translate.el

.PHONY: all test compile lint checkdoc package-lint clean help

all: compile test

help:
	@echo "Available targets:"
	@echo "  test         - Run ERT tests"
	@echo "  compile      - Byte-compile all source files"
	@echo "  lint         - Run checkdoc and package-lint"
	@echo "  checkdoc     - Run checkdoc on all files"
	@echo "  package-lint - Run package-lint (requires package-lint from MELPA)"
	@echo "  clean        - Remove compiled files"
	@echo "  all          - Compile and test (default)"

test:
	$(BATCH) -l ert -l test/mu4e-llm-test.el -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile $(SRCS)

lint: checkdoc package-lint

checkdoc:
	@echo "Running checkdoc on source files..."
	@for f in $(SRCS); do \
		echo "Checking $$f..."; \
		$(BATCH) --eval "(require 'checkdoc)" \
		         --eval "(setq checkdoc-spellcheck-documentation-flag nil)" \
		         --eval "(with-current-buffer (find-file-noselect \"$$f\") \
		                   (checkdoc-current-buffer t))"; \
	done
	@echo "Checkdoc complete."

package-lint:
	@echo "Running package-lint on main file..."
	$(BATCH) --eval "(require 'package)" \
	         --eval "(push '(\"melpa\" . \"https://melpa.org/packages/\") package-archives)" \
	         --eval "(package-initialize)" \
	         --eval "(unless (package-installed-p 'package-lint) \
	                   (package-refresh-contents) \
	                   (package-install 'package-lint))" \
	         --eval "(require 'package-lint)" \
	         -f package-lint-batch-and-exit mu4e-llm.el

clean:
	rm -f *.elc test/*.elc
