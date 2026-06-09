---
name: worktwin-help
description: List every worktwin command installed on this machine, with the arguments each one takes and a short description. Use when you forget a command name or want to see what worktwin can do without leaving Claude Code.
disable-model-invocation: true
allowed-tools: Bash(ls *), Bash(cat *), Bash(find *), Bash(grep *), Bash(sed *), Bash(git *), Read
---

# worktwin-help

Print every worktwin command available on this machine. The list is generated from the actual installed `SKILL.md` files, not from a hardcoded list, so new commands appear automatically as soon as they are installed and removed commands disappear without anyone having to remember to update this skill.

## 1. Locate the skills directory

Try, in order, and use the first one that exists:

1. `$HOME/.claude/skills` for a global install.
2. `$(git rev-parse --show-toplevel 2>/dev/null)/.claude/skills` for a per-project install.

If neither exists, print:

```
worktwin does not seem to be installed on this machine.
See https://github.com/rhagee/worktwin for install instructions.
```

and stop.

## 2. Enumerate the worktwin skills

List every directory in the skills directory whose name starts with `worktwin`:

```bash
ls -d "$SKILLS_DIR"/worktwin* 2>/dev/null
```

For each directory, read its `SKILL.md` with the Read tool and pull from the YAML frontmatter:

- `name`
- `description`
- `argument-hint` (may be absent)

The frontmatter is the block between the first two `---` lines at the top of the file. Values are simple single-line strings.

## 3. Print the help

Print one entry per command in this order, falling through to alphabetical for anything you do not recognise:

1. `worktwin`
2. `worktwin-status`
3. `worktwin-ship`
4. `worktwin-ship-all`
5. `worktwin-finalize`
6. `worktwin-help`
7. anything else, alphabetical

Format for each entry:

```
/<name> <argument-hint>
  <short description>
```

If `argument-hint` is absent, print just `/<name>`. For the short description, rewrite the frontmatter `description` field as one tight sentence in the second person ("Bind this session to a new isolated worker", "Ship the workers you list by branch", and so on). Drop the "Use when..." clause if the frontmatter contains one. Aim for under 90 characters.

## 4. End with a single footer line

Append exactly one trailing line:

```
docs: https://github.com/rhagee/worktwin
```

Nothing else. No preface, no closing remarks, no summary. The user asked for the command list, give them the command list.
