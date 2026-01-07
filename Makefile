# mu4e-llm Makefile
# Run tests, compile, and lint for MELPA package quality

EMACS ?= emacs
BATCH = $(EMACS) -batch -Q -L .

# Source files (excluding test files)
SRCS = mu4e-llm.el mu4e-llm-config.el mu4e-llm-core.el mu4e-llm-draft.el \
       mu4e-llm-summary.el mu4e-llm-thread.el mu4e-llm-translate.el

.PHONY: all test compile lint checkdoc clean help

all: compile test

help:
	@echo "Available targets:"
	@echo "  test     - Run ERT tests"
	@echo "  compile  - Byte-compile all source files"
	@echo "  lint     - Run checkdoc on all files"
	@echo "  checkdoc - Alias for lint"
	@echo "  clean    - Remove compiled files"
	@echo "  all      - Compile and test (default)"

test:
	$(BATCH) -l ert -l test/mu4e-llm-test.el -f ert-run-tests-batch-and-exit

compile:
	$(BATCH) -f batch-byte-compile $(SRCS)

lint: checkdoc

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

clean:
	rm -f *.elc test/*.elc
