# Shared setup for the bats tests. Creates a throwaway git repo per test
# so the bin/ scripts can run against something real.

setup() {
  TEST_BASE=$(mktemp -d 2>/dev/null || mktemp -d -t worktwin)
  export TEST_BASE
  export TEST_REPO="$TEST_BASE/myrepo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"

  git init -b main -q
  git config user.email "test@example.com"
  git config user.name "worktwin test"
  echo "hello" > README.md
  git add README.md
  git commit -q -m "initial"

  # Resolve bin/ relative to the tests directory regardless of cwd
  BIN_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../bin" && pwd)"
  export BIN_DIR
  export PATH="$BIN_DIR:$PATH"
}

teardown() {
  cd /
  rm -rf "$TEST_BASE" 2>/dev/null || true
}
