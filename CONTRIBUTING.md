# Contributing to mu4e-llm

Thank you for your interest in contributing to mu4e-llm!

## Development Setup

```bash
git clone https://github.com/sillyfellow/mu4e-llm.git
cd mu4e-llm
make all
```

## Before Submitting a PR

Run all checks:

```bash
make compile  # Byte-compile all files
make test     # Run ERT tests
make lint     # Run checkdoc
```

All three must pass.

## Code Style

- Use `lexical-binding: t` in all files
- Public functions: `mu4e-llm-*`
- Internal functions: `mu4e-llm--*`
- Add docstrings to all public functions
- Use `declare-function` for cross-module calls

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new summarization option
fix: handle empty thread gracefully
docs: update configuration examples
refactor: simplify worker cleanup
test: add tests for translation
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feat/my-feature`)
3. Make your changes
4. Run `make all` to verify
5. Commit with a descriptive message
6. Push and open a PR against `master`

## Reporting Bugs

Use the GitHub issue tracker with the bug report template. Include:

- Emacs version (`M-x emacs-version`)
- mu4e version
- LLM provider being used
- Steps to reproduce
- Error messages from `*Messages*` buffer

## Questions?

Open a discussion or issue on GitHub.
