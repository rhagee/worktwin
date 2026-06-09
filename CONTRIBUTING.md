# Contributing to worktwin

Thanks for considering a contribution. The bar is low: worktwin is small on purpose. Issues, fixes, and skill improvements are all welcome.

## Filing issues

Open an issue for anything that does not work as documented, anything that is confusing in the README, or anything you wish worktwin did. Useful information to include:

- OS and shell (macOS, Linux, Git Bash, WSL)
- git version (`git --version`)
- Claude Code version
- The exact `/worktwin` command and the output you got

For feature requests, describe the workflow you want, not the implementation you have in mind.

## Sending pull requests

1. Fork the repo.
2. Branch off `main` (and yes, you can use worktwin itself for the branch: `/worktwin main feat/your-thing "describe the change"`).
3. Keep the change focused. One PR per logical unit.
4. Conventional commit prefixes: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`.
5. Open the PR against `main`.

## Testing skills locally

There is no automated test suite yet (a real one would need a sandbox git repo and a way to drive Claude Code headlessly). The pragmatic loop:

1. Create a throwaway git repo somewhere.
2. Install worktwin with `./install.sh local` inside that repo.
3. Run the commands by hand and verify the side effects: worktree appears, state file lives at `$(git rev-parse --git-common-dir)/parallel/`, the worktree's `CLAUDE.md` contains the marked block.
4. For `/worktwin-ship`, point the repo at a private test repo on GitHub so you can confirm the PR creation and update paths without polluting anything real.

## Constraints worth respecting

- Zero hard dependencies beyond git, bash, and Claude Code. `gh` and `jq` are optional and the skills must degrade gracefully without them.
- The skills must work from inside a worktree, not just from the main checkout. Always use `git rev-parse --git-common-dir`, never `.git/`.
- Do not write user-facing text that contains characters not on a standard keyboard. Plain ASCII keeps the README and skill output readable everywhere.

## License

By contributing you agree that your contribution will be released under the MIT license.
