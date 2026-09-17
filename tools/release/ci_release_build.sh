#!/usr/bin/env bash
# Run the release workflow's BUILD path locally, with act, and check the binary that comes out.
#
# The point is that nothing here is a transcription. Two releases shipped broken because the
# release workflow and the local build did different things, and the only checks anybody ran were
# the local ones. A hand-written replay of the workflow has exactly that defect one level up: it
# can drift from release.yml the same way release.yml drifted from mise.toml. So this runs
# .github/workflows/release.yml itself, from the file, in a container.
#
# It runs guard + corpus + binaries (linux/amd64). The release job is deliberately out: it creates
# a GitHub release, signs it and pushes attestations, none of which belongs on a laptop.
#
# What it still does not prove, and what tools/release/verify_published_vm.sh is for: that the
# artifact GitHub actually published is this one. act is a simulation of the runner, not the runner.
#
# Usage: tools/release/ci_release_build.sh [vX.Y.Z]     (default: v0.0.0-act, any release-shaped tag)
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.." || exit 1

TAG=${1:-v0.0.0-act.1}
# act has no built-in image for ubuntu-24.04 and SKIPS the job rather than failing, which reads as
# a clean run and proves nothing. The mapping is mandatory, and the caller is told when it is used.
IMAGE=${ACT_UBUNTU_IMAGE:-catthehacker/ubuntu:act-24.04}

work=$(mktemp -d)
# The runner container writes the artifacts as root through the bind mount, so a plain rm leaves a
# directory of Permission denied behind at every run. Hand them back before removing them.
# shellcheck disable=SC2329  # invoked by the trap below
cleanup() {
  if [ -d "$work/artifacts" ]; then
    docker run --rm -v "$work/artifacts:/a" "$IMAGE" \
      chown -R "$(id -u):$(id -g)" /a >/dev/null 2>&1 || true
  fi
  rm -rf "$work"
}
trap cleanup EXIT INT TERM

# The version mise.toml pins, not whatever an already-open shell has on its PATH: a shim resolved
# before the pin was added keeps serving the old binary for the life of that shell.
ACT=$(mise which act 2>/dev/null || command -v act)
[ -x "$ACT" ] || { echo "act is not installed (mise install)" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "docker is not reachable; act needs it" >&2; exit 2; }

# act's own artifact server has to speak the protocol actions/upload-artifact@v7 uses. Before
# 0.2.89 it answered `unknown field "mime_type"` and the corpus job failed on the upload, so the
# build step this script exists to exercise was never reached.
av=$("$ACT" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [ "$(printf '%s\n0.2.89\n' "$av" | sort -V | head -1)" != "0.2.89" ]; then
  echo "act $av is too old for actions/upload-artifact@v7 (need 0.2.89+); run: mise install" >&2
  exit 2
fi

# The guard job refuses a tag that is not release-shaped, and refuses to run at all on a private
# repository, so the event has to carry both.
cat > "$work/event.json" <<EVENT
{
  "ref": "refs/tags/$TAG",
  "ref_name": "$TAG",
  "ref_type": "tag",
  "repository": {
    "name": "pavois",
    "full_name": "stephrobert/pavois",
    "private": false,
    "default_branch": "main",
    "owner": { "login": "stephrobert" }
  },
  "pusher": { "name": "stephrobert" }
}
EVENT

docker image inspect "$IMAGE" >/dev/null 2>&1 \
  || { echo "missing runner image $IMAGE (docker pull $IMAGE)" >&2; exit 2; }

# act copies the WORKING TREE, including files git does not hold; GitHub checks out the commit.
# The first green run here exercised tools/release/embed_reference.sh while it was still untracked,
# so it proved something about a script the real runner would not have found. A dirty tree makes
# this check say more than it knows, which is the failure mode the whole file exists to avoid.
dirty=$(git status --porcelain)
if [ -n "$dirty" ]; then
  echo "the working tree is not clean, and act would build THAT rather than the commit:" >&2
  printf '%s\n' "$dirty" | head -10 >&2
  echo "commit or stash first (ACT_ALLOW_DIRTY=1 to override, knowing what it costs)" >&2
  [ "${ACT_ALLOW_DIRTY:-}" = "1" ] || exit 2
fi

# The artifact hop, and ONLY the artifact hop, is replaced by a local stub.
#
# act's own artifact server rejects what actions/upload-artifact@v7 sends
# (`unknown field "mime_type"`), so the corpus job dies on the upload and the build step this exists
# to exercise is never reached. Stubbing the two actions keeps release.yml itself unmodified, which
# is the whole point: the defect being guarded against lived in a step the local path never ran, so
# a rewritten copy of the workflow would reintroduce exactly that risk.
#
# The pinned SHAs are read from the workflow rather than written here, so bumping a pin does not
# silently turn the stub off and send the run back to the broken server.
UP=$(grep -oE 'actions/upload-artifact@[0-9a-f]{40}' .github/workflows/release.yml | head -1)
DL=$(grep -oE 'actions/download-artifact@[0-9a-f]{40}' .github/workflows/release.yml | head -1)
[ -n "$UP" ] && [ -n "$DL" ] || { echo "could not read the artifact action pins from release.yml" >&2; exit 2; }
mkdir -p "$work/artifacts"
chmod 0777 "$work/artifacts"   # the runner container writes as its own user

echo "== running .github/workflows/release.yml under act $av ($TAG, linux/amd64, $IMAGE)"
echo "   artifact transport stubbed: $UP, $DL"
"$ACT" push \
  --workflows .github/workflows/release.yml \
  --job binaries \
  --eventpath "$work/event.json" \
  --platform "ubuntu-24.04=$IMAGE" \
  --matrix "goos:linux" --matrix "goarch:amd64" \
  --local-repository "$UP=$PWD/tools/release/act-stubs/upload-artifact" \
  --local-repository "$DL=$PWD/tools/release/act-stubs/download-artifact" \
  --container-options "-v $work/artifacts:/tmp/act-artifacts" \
  --pull=false \
  > "$work/act.log" 2>&1
rc=$?
# A skipped job exits zero. Nothing running is the failure mode this whole script exists to avoid.
if grep -q 'Skipping unsupported platform' "$work/act.log"; then
  echo "act skipped the job instead of running it (platform mapping rejected):" >&2
  grep 'Skipping unsupported platform' "$work/act.log" | head -3 >&2
  exit 1
fi
grep -E '^\[Release/' "$work/act.log" | grep -viE 'docker (pull|create|run|exec|cp)|^\s*$' | tail -30
if [ "$rc" -ne 0 ]; then
  echo
  echo "act failed (exit $rc). Last lines:"
  tail -25 "$work/act.log"
  exit 1
fi

art=$(find "$work/artifacts" -name 'pavois-linux-amd64' -type f | head -1)
[ -n "$art" ] || art=$(find "$work" -name 'pavois-linux-amd64' -type f | head -1)
[ -n "$art" ] || { echo "act produced no pavois-linux-amd64 artifact"; tail -20 "$work/act.log"; exit 1; }
# Copied out before being made executable: the runner container wrote it through the bind mount, so
# it is owned by root and this user cannot chmod it in place. It arrives as 0644 because the upload
# stub normalises modes exactly as actions/upload-artifact v4+ does, which is also what a user gets
# from a release asset: the install instructions say chmod for that reason.
bin="$work/pavois-from-workflow"
if ! cp "$art" "$bin"; then
  echo "could not take a copy of the artifact act produced" >&2
  exit 1
fi
chmod +x "$bin"
echo
echo "== the guard, on the binary the WORKFLOW produced ($(stat -c%s "$bin") bytes)"
bash --noprofile --norc tools/release/standalone_binary.sh "$bin"
