# Contributing

Open an issue before proposing a feature or desktop-environment integration.

Preserve preview rollback, undo history, quoted paths, and clear dependency checks. Do not add unvalidated remote execution, destructive filesystem operations, or automatic privileged installs.

Before opening a pull request, run `bash -n adrice.sh` and `shellcheck adrice.sh` on a supported Linux distribution. Include the desktop environment and manual undo/rollback verification in the pull request.
