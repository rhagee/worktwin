# worktwin vs other tools

## `claude --worktree`

The official Claude Code flag. Spins up a worktree and opens a session in it. Solves the filesystem side cleanly.

What is missing: the agent receives no behavioural instructions about staying on the branch, no cross-session state, no awareness of other parallel workers, and no merge or pull request workflow. Two `claude --worktree` sessions in the same repo still need every coordination decision made by hand.

Use `claude --worktree` when you want a one-off isolated session and you trust yourself to coordinate everything else manually.

## `gtr` (CodeRabbit)

A bash CLI that creates a worktree and opens an editor or shell in it. Agent-agnostic, which means it works with anything, including Claude Code.

What is missing: it is a separate tool you have to know about and install, it does not configure the agent, and it does not coordinate the end of the session. You still write the rules into `CLAUDE.md` by hand and you still run `gh pr create` per branch.

Use `gtr` if you want a generic, editor-agnostic worktree spawner and you are happy to wire the rest yourself.

## `ccswarm`

A heavier multi-agent orchestration framework. Routes tasks across agents, handles communication, supports complex topologies.

What is missing for the parallel-work use case: a steep learning curve, more configuration than the problem usually needs, and a model that assumes you want true agent-to-agent collaboration rather than independent parallel workers.

Use `ccswarm` when you actually need multi-agent collaboration, not just isolation.

## Manual `git clone` of the same repo into a sibling directory

Works. Two checkouts, two histories, no shared object store. Wastes disk, doubles fetch time, makes it harder to keep branches in sync, and still leaves agent instructions to you.

Use manual clones when you genuinely need two fully independent repositories, for example to test a destructive migration.

## Summary

worktwin is the smallest tool that addresses the full lifecycle: create the isolation, instruct the agent, persist the rules across compaction and new sessions, surface real conflicts, and open or update pull requests at the end. It does less than `ccswarm`, more than `claude --worktree`, and replaces the manual setup around `gtr`.
