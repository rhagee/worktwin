# tests

Bats tests for the scripts in `bin/`. Each test sets up a fresh throwaway git repo so the scripts run against something real, not a mock.

## Install bats

macOS:

```
brew install bats-core
```

Linux:

```
git clone https://github.com/bats-core/bats-core
cd bats-core
sudo ./install.sh /usr/local
```

npm (any platform with node):

```
npm install -g bats
```

## Run

From the repo root:

```
bats tests/
```

Run a single file:

```
bats tests/worktwin-init.bats
```

## Layout

- `test_helper.bash` - shared setup and teardown (fresh git repo per test)
- `worktwin-init.bats` - spawn behaviour, slug, state file, idempotency
- `worktwin-claude-md.bats` - block insert, replace, preservation, idempotency
- `worktwin-list.bats` - discovery, filtering, stale detection, NDJSON shape

The PowerShell mirrors (`*.ps1`) are not covered by bats. They follow the same contract as the bash versions and are smoke-tested manually. Pester coverage is on the roadmap.
