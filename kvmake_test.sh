#!/usr/bin/env bash
# Focused unit tests for bazel-test/kvmake. Stub no ssh/rsync.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/kvmake"

fail() {
	echo "FAIL: $*" >&2
	exit 1
}

pass() {
	echo "ok: $*"
}

# --- workspace_id ---
id=$(workspace_id /home/user/src/kubevirt)
[[ "$id" == "home-user-src-kubevirt" ]] || fail "workspace_id: $id"
pass "workspace_id encodes slashes"

# --- parse_make_targets ---
parse_make_targets
[[ ${#MAKE_TARGETS[@]} -eq 1 && "${MAKE_TARGETS[0]}" == all ]] || fail "no-args targets should be all"
parse_make_targets bazel-build
[[ "${MAKE_TARGETS[0]}" == bazel-build ]] || fail "bazel-build target"
parse_make_targets SYNC_OUT=false generate
[[ "${MAKE_TARGETS[0]}" == generate ]] || fail "assignment is not a target"
pass "parse_make_targets"

# --- quote_make_args: zero args must not emit a quoted empty string ---
REMOTE_DIR=/tmp/kv-remote
quote_make_args
[[ -z "${QUOTED_MAKE_ARGS}" ]] || fail "zero args produced QUOTED_MAKE_ARGS=[${QUOTED_MAKE_ARGS}]"
quote_make_args bazel-build
[[ "$QUOTED_MAKE_ARGS" == *bazel-build* ]] || fail "quoted bazel-build"
quote_make_args ARTIFACTS=/laptop/out bazel-build
[[ "$QUOTED_MAKE_ARGS" == *"${REMOTE_DIR}/_out/artifacts"* ]] || fail "ARTIFACTS not remapped in argv"
[[ "$QUOTED_MAKE_ARGS" != */laptop/out* ]] || fail "laptop ARTIFACTS leaked into argv"
KUBEVIRT_PROVIDER=external
quote_make_args KUBECONFIG=/laptop/kubeconfig
[[ "$QUOTED_MAKE_ARGS" == *"${REMOTE_SIDECAR}/kubeconfig"* ]] || fail "KUBECONFIG not remapped"
pass "quote_make_args"

# --- apply_wrapper_make_assignments ---
SYNC_OUT=true
ARTIFACTS=""
KUBEVIRT_PROVIDER=k8s-1.32
apply_wrapper_make_assignments SYNC_OUT=false ARTIFACTS=/tmp/art KUBEVIRT_PROVIDER=external
[[ "$SYNC_OUT" == false ]] || fail "SYNC_OUT assignment"
[[ "$ARTIFACTS" == /tmp/art ]] || fail "ARTIFACTS assignment"
[[ "$KUBEVIRT_PROVIDER" == external ]] || fail "KUBEVIRT_PROVIDER assignment"
pass "apply_wrapper_make_assignments"

# --- needs_cluster_lock ---
parse_make_targets bazel-build
needs_cluster_lock && fail "bazel-build should not take cluster lock"
parse_make_targets cluster-up
needs_cluster_lock || fail "cluster-up should lock"
parse_make_targets functest-image-build
needs_cluster_lock || fail "functest-image-build currently over-locks (glob functest-*)"
pass "needs_cluster_lock"

# --- ctl_path includes ssh opts ---
KVMAKE_HOST=user@vm
KVMAKE_SSH_OPTS=""
p1=$(ctl_path)
KVMAKE_SSH_OPTS="-p 2222"
p2=$(ctl_path)
[[ "$p1" != "$p2" ]] || fail "ctl_path should change with SSH opts"
pass "ctl_path hashes host+opts"

# --- expand_tilde_prefix ---
got=$(expand_tilde_prefix '~/kubevirt' /home/user)
[[ "$got" == /home/user/kubevirt ]] || fail "tilde slash: $got"
got=$(expand_tilde_prefix '~' /home/user)
[[ "$got" == /home/user ]] || fail "tilde only: $got"
got=$(expand_tilde_prefix /abs/kubevirt /home/user)
[[ "$got" == /abs/kubevirt ]] || fail "absolute: $got"
got=$(expand_tilde_prefix "'~/kubevirt'" /home/user)
[[ "$got" == /home/user/kubevirt ]] || fail "quoted tilde: $got"
got=$(expand_tilde_prefix '/home/user/~/kubevirt' /home/user)
[[ "$got" == /home/user/kubevirt ]] || fail "literal tilde repair: $got"
pass "expand_tilde_prefix"

# --- .git is forwarded, not reverse-synced ---
printf '%s\n' "${RSYNC_EXCLUDES[@]}" | grep -qx -- '--exclude=.git' && fail "forward rsync must copy .git"
pass "forward includes .git"

# --- assert_git_dir_for_remote ---
gitroot=$(mktemp -d)
KUBEVIRT_ROOT=$gitroot
(assert_git_dir_for_remote) >/dev/null 2>&1 && fail "missing .git should fail"
mkdir -p "$gitroot/.git"
assert_git_dir_for_remote || fail "directory .git should pass"
rm -rf "$gitroot/.git"
printf 'gitdir: /tmp/worktree\n' >"$gitroot/.git"
(assert_git_dir_for_remote) >/dev/null 2>&1 && fail "worktree .git file should fail"
rm -rf "$gitroot"
pass "assert_git_dir_for_remote"

# --- local_edits_since ---
tmp=$(mktemp -d)
stamp=$(mktemp)
mkdir -p "$tmp/pkg" "$tmp/.git" "$tmp/bazel-test"
echo old >"$tmp/pkg/a.go"
touch "$stamp"
sleep 1
echo new >"$tmp/pkg/a.go"
echo ignored >"$tmp/bazel-test/x"
echo gitty >"$tmp/.git/HEAD"
found=$(local_edits_since "$stamp" "$tmp")
printf '%s\n' "$found" | grep -q 'pkg/a.go' || fail "should report pkg/a.go"
printf '%s\n' "$found" | grep -q bazel-test && fail "should prune bazel-test"
printf '%s\n' "$found" | grep -q '.git' && fail "should prune .git"
rm -rf "$tmp" "$stamp"
pass "local_edits_since"

# --- Make-discovered environment forwarding ---
makeroot=$(mktemp -d)
cat >"$makeroot/Makefile" <<'EOF'
all:
	@printf '%s\n' "$(KVMAKE_TEST_REFERENCED)" "${KVMAKE_TEST_UNEXPORTED}" "$(DOCKER_HOST)"
EOF
KUBEVIRT_ROOT=$makeroot
TREE_JOB_NAME=kv-test
MAKE_TARGETS=(all)
ABS_FILE_VARS=()
TREE_FILE_VARS=()
KVMAKE_FORWARD_ENV=KVMAKE_TEST_EXPLICIT
ARTIFACTS=
KUBEVIRT_PROVIDER=
KUBECONFIG=
KVMAKE_TEST_UNEXPORTED=local-only
KVMAKE_TEST_EXPLICIT=explicit
KUBEVIRT_TEST_NAMESPACED=namespaced
export KVMAKE_TEST_REFERENCED=discovered
export KVMAKE_TEST_UNRELATED=unrelated
export DOCKER_HOST=unix:///laptop/docker.sock

build_remote_exports
exports=$(printf '%s\n' "${REMOTE_EXPORTS[@]}")
printf '%s\n' "$exports" | grep -qx 'KVMAKE_TEST_REFERENCED=discovered' || fail "Make-referenced exported variable was not forwarded"
printf '%s\n' "$exports" | grep -qx 'KVMAKE_TEST_EXPLICIT=explicit' || fail "KVMAKE_FORWARD_ENV variable was not forwarded"
printf '%s\n' "$exports" | grep -qx 'KUBEVIRT_TEST_NAMESPACED=namespaced' || fail "KUBEVIRT_* variable was not forwarded"
printf '%s\n' "$exports" | grep -q '^KVMAKE_TEST_UNEXPORTED=' && fail "unexported Make-referenced variable was forwarded"
printf '%s\n' "$exports" | grep -q '^KVMAKE_TEST_UNRELATED=' && fail "unrelated exported variable was forwarded"
printf '%s\n' "$exports" | grep -q '^DOCKER_HOST=' && fail "blocked Docker client variable was forwarded"
rm -rf "$makeroot"
unset KVMAKE_TEST_REFERENCED KVMAKE_TEST_UNEXPORTED KVMAKE_TEST_UNRELATED KVMAKE_TEST_EXPLICIT KUBEVIRT_TEST_NAMESPACED DOCKER_HOST
pass "Make-discovered environment forwarding"

echo "all tests passed"
