#!/usr/bin/env bash
# NotchDeck CI: force-pushes this job's *.log files to the ci-logs-<job> branch, one commit with
# no history, so they can be read with `git fetch origin ci-logs-<job>`. Errors come first in
# errors.txt; long logs keep their last 4000 lines.
set -uo pipefail
job=$1
out=$(mktemp -d)
for log in *.log; do
    [[ -f $log ]] || continue
    tail -n 4000 "$log" >"$out/$log"
done
grep -hnE "error:|warning:|failed|Fail|✘|Issue recorded" ./*.log 2>/dev/null | head -n 400 >"$out/errors.txt"
echo "$GITHUB_SHA" >"$out/commit.txt"
cd "$out" || exit 0
git init -q
git config user.name "notchdeck-ci"
git config user.email "notchdeck-ci@users.noreply.github.com"
git add -A
git commit -qm "CI logs for $job at $GITHUB_SHA"
git push -qf "https://x-access-token:${TOKEN}@github.com/${GITHUB_REPOSITORY}.git" HEAD:refs/heads/ci-logs-"$job" ||
    echo "Couldn't publish logs"
