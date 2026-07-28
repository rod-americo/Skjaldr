# AGENTS.md

This file applies to the entire repository unless a nested `AGENTS.md`
provides more specific instructions.

## Language

- Use English for code, identifiers, comments, documentation, tests, and
  commit messages.
- Preserve the established language of user-facing copy unless the task
  explicitly changes it.

## Git Workflow

- Work directly on `main` unless the user requests another branch.
- Create a commit automatically after each small, validated logical change;
  do not wait for a separate request to commit.
- Keep each commit focused on one responsibility and exclude unrelated
  worktree changes.
- Before committing, inspect `git status`, the complete staged diff, and
  `git diff --cached --check`.
- Use an English imperative subject no longer than 72 characters, preferably
  in `type(scope): summary` form.
- Do not amend, squash, rewrite, or discard existing commits unless the user
  explicitly requests it.
- Push only when the user explicitly requests publication or the task already
  includes a push.

## Validation

- Run `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test`
  before completing an application-code change.
- Run `./Scripts/compilar-app.sh` when the requested change must be installed
  for local use.
