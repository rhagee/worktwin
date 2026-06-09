---
name: worktwin-update
description: Pull the latest worktwin and reinstall the skills without leaving Claude Code. Requires that install.sh or install.ps1 was originally run from a cloned worktwin repo so the source path was recorded.
disable-model-invocation: true
allowed-tools: Bash(cat *), Bash(ls *), Bash(test *), Bash(bash *), Bash(tr *), Bash(git *)
---

Show the block below to the user verbatim. Do not paraphrase. After it, print exactly one line:

```
Restart Claude Code to load the updated skills.
```

```!
SOURCE_FILE=""
for try in "$HOME/.claude/skills/worktwin/.source" \
           "$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills/worktwin/.source"; do
  if [ -f "$try" ]; then SOURCE_FILE="$try"; break; fi
done

if [ -z "$SOURCE_FILE" ]; then
  echo "worktwin source path is not recorded (no .source file)."
  echo "Did you install via install.sh or install.ps1 from a cloned worktwin repo?"
  exit 0
fi

SOURCE_ROOT=$(cat "$SOURCE_FILE" | sed '1s/^\xef\xbb\xbf//' | tr -d '\r\n' | tr '\\' '/')
if [ ! -d "$SOURCE_ROOT" ]; then
  echo "Recorded source path no longer exists: $SOURCE_ROOT"
  echo "Re-run install.sh or install.ps1 from the current path of your cloned worktwin repo."
  exit 0
fi

if [ ! -x "$SOURCE_ROOT/update.sh" ] && [ ! -f "$SOURCE_ROOT/update.sh" ]; then
  echo "update.sh not found at $SOURCE_ROOT. Pull the worktwin repo first or re-run install."
  exit 0
fi

bash "$SOURCE_ROOT/update.sh"
```

The script only handles the default global install. For a `local` install or a custom path, run `update.sh` or `update.ps1` manually from the cloned repo so you can pass the install mode.
