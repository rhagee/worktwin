---
name: worktwin-update
description: Pull the latest worktwin and reinstall the skills without leaving Claude Code. Requires that install.sh or install.ps1 was originally run from a cloned worktwin repo so the source path was recorded.
disable-model-invocation: true
allowed-tools: Bash(bash *), Bash(test *)
---

Show the script output below verbatim. After the output, print exactly one extra line:

```
Restart Claude Code to load the updated skills.
```

!`bash "$HOME/.claude/skills/worktwin/bin/worktwin-update"`
