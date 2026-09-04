#!/usr/bin/env bash
# common.bash — Bats helper library for makefile-skill-installer tests
#
# Usage in a Bats test file:
#   load '../helpers/common'
#
# Provides:
#   - setup / teardown  (per-test temp dir + PATH stub injection)
#   - assert_exit
#   - assert_output_contains
#   - assert_stderr_contains
#   - assert_symlink
#   - get_call_log / assert_called_with  (stub call-log mechanism)
#   - random_string / random_comma_list  (lightweight input generators)

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------

# Repo root is two levels up from tests/helpers/
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ---------------------------------------------------------------------------
# setup / teardown
# ---------------------------------------------------------------------------

# Called automatically by Bats before each test.
# Creates a per-test temp directory, a stubs sub-dir inside it, and
# injects the stubs directory at the front of PATH so that stub scripts
# for 'gh' and 'brew' shadow any real binaries for the duration of the test.
setup() {
  # Bats provides BATS_TEST_TMPDIR in newer versions; fall back to mktemp.
  if [[ -z "${BATS_TEST_TMPDIR:-}" ]]; then
    BATS_TEST_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bats-test.XXXXXX")"
  fi

  TEST_TMPDIR="${BATS_TEST_TMPDIR}"
  TEST_STUBS_DIR="${TEST_TMPDIR}/stubs"
  CALL_LOG="${TEST_TMPDIR}/call.log"

  mkdir -p "${TEST_STUBS_DIR}"
  touch "${CALL_LOG}"

  # Prepend per-test stubs dir to PATH
  export PATH="${TEST_STUBS_DIR}:${PATH}"
  export CALL_LOG
  export TEST_TMPDIR
  export TEST_STUBS_DIR
}

# Called automatically by Bats after each test.
# Removes the per-test temp directory.
teardown() {
  if [[ -n "${TEST_TMPDIR:-}" && -d "${TEST_TMPDIR}" ]]; then
    rm -rf "${TEST_TMPDIR}"
  fi
}

# ---------------------------------------------------------------------------
# Stub helpers
# ---------------------------------------------------------------------------

# install_stub <name> [exit_code]
#   Creates an executable stub script at $TEST_STUBS_DIR/<name>.
#   The stub appends "name arg1 arg2 ..." to $CALL_LOG and exits with
#   the given exit code (default 0).
install_stub() {
  local name="$1"
  local exit_code="${2:-0}"
  local stub_path="${TEST_STUBS_DIR}/${name}"

  cat > "${stub_path}" <<EOF
#!/usr/bin/env bash
echo "${name} \$*" >> "\${CALL_LOG}"
exit ${exit_code}
EOF
  chmod +x "${stub_path}"
}

# install_stub_failing <name>
#   Convenience wrapper: stub that always exits 1.
install_stub_failing() {
  install_stub "$1" 1
}

# ---------------------------------------------------------------------------
# Call-log helpers
# ---------------------------------------------------------------------------

# get_call_log
#   Prints the entire call log to stdout.
get_call_log() {
  cat "${CALL_LOG}"
}

# assert_called_with <name> <expected_args_substring>
#   Asserts that the call log contains at least one line where the first
#   token is <name> and the rest of the line contains <expected_args_substring>.
assert_called_with() {
  local name="$1"
  local expected="$2"
  local log
  log="$(get_call_log)"

  if ! echo "${log}" | grep -qE "^${name}.*${expected}"; then
    echo "ASSERTION FAILED: assert_called_with '${name}' '${expected}'" >&2
    echo "Call log was:" >&2
    echo "${log}" >&2
    return 1
  fi
}

# assert_not_called <name>
#   Asserts that the stub named <name> was never invoked.
assert_not_called() {
  local name="$1"
  local log
  log="$(get_call_log)"

  if echo "${log}" | grep -qE "^${name}"; then
    echo "ASSERTION FAILED: assert_not_called '${name}' — but it was called" >&2
    echo "Call log was:" >&2
    echo "${log}" >&2
    return 1
  fi
}

# call_count <name>
#   Prints the number of times the stub <name> was called.
call_count() {
  local name="$1"
  get_call_log | grep -cE "^${name}" || true
}

# ---------------------------------------------------------------------------
# Core assertions
# ---------------------------------------------------------------------------

# assert_exit <expected_code> <actual_code>
assert_exit() {
  local expected="$1"
  local actual="$2"
  if [[ "${actual}" -ne "${expected}" ]]; then
    echo "ASSERTION FAILED: expected exit code ${expected}, got ${actual}" >&2
    return 1
  fi
}

# assert_output_contains <substring> <output>
#   Pass multi-line output as the second argument (use "$output" in Bats).
assert_output_contains() {
  local substring="$1"
  local output="$2"
  if ! echo "${output}" | grep -qF "${substring}"; then
    echo "ASSERTION FAILED: expected stdout to contain '${substring}'" >&2
    echo "Actual stdout:" >&2
    echo "${output}" >&2
    return 1
  fi
}

# assert_stderr_contains <substring> <stderr_output>
assert_stderr_contains() {
  local substring="$1"
  local stderr_output="$2"
  if ! echo "${stderr_output}" | grep -qF "${substring}"; then
    echo "ASSERTION FAILED: expected stderr to contain '${substring}'" >&2
    echo "Actual stderr:" >&2
    echo "${stderr_output}" >&2
    return 1
  fi
}

# assert_symlink <link_path> <expected_target>
#   Asserts that <link_path> is a symlink pointing to <expected_target>.
assert_symlink() {
  local link_path="$1"
  local expected_target="$2"

  if [[ ! -L "${link_path}" ]]; then
    echo "ASSERTION FAILED: '${link_path}' is not a symlink" >&2
    return 1
  fi

  local actual_target
  actual_target="$(readlink "${link_path}")"
  if [[ "${actual_target}" != "${expected_target}" ]]; then
    echo "ASSERTION FAILED: symlink '${link_path}' points to '${actual_target}', expected '${expected_target}'" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Random input generators
# ---------------------------------------------------------------------------

# random_string <N>
#   Prints N random alphanumeric characters (lowercase + digits).
random_string() {
  local n="${1:-8}"
  # Use /dev/urandom for portability; tr keeps [a-z0-9].
  LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "${n}"
}

# random_comma_list <MIN> <MAX>
#   Prints a comma-delimited list of random words with between MIN and MAX
#   elements (inclusive). Each element is 4–10 random alphanumeric chars.
random_comma_list() {
  local min="${1:-1}"
  local max="${2:-5}"
  local count=$(( min + RANDOM % (max - min + 1) ))
  local list=""
  local i
  for (( i = 0; i < count; i++ )); do
    local len=$(( 4 + RANDOM % 7 ))   # 4..10 chars
    local word
    word="$(random_string "${len}")"
    if [[ -z "${list}" ]]; then
      list="${word}"
    else
      list="${list},${word}"
    fi
  done
  echo "${list}"
}
