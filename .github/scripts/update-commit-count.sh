#!/usr/bin/env bash
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-loic31000}"
CUTOFF_30D="$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)"
UPDATED="$(date -u +%F)"

declare -A UNIQUE_SHAS=()
declare -A RECENT_SHAS=()

REPO_COUNT=0
FAILED_COUNT=0
REPO_TOTAL=0
PUBLIC_REPOS=0
PRIVATE_REPOS=0
ACTIVE_REPOS_30D=0
ACTIVE_AUTHOR_REPOS_30D=0
STARS_TOTAL=0
FORKS_TOTAL=0
BRANCHES_TOTAL=0
BRANCH_SCAN_FAILED=0
PRS_AUTHORED="—"
ISSUES_AUTHORED="—"

mapfile -t REPOS < <(
  gh repo list "$GITHUB_USER" \
    --limit 1000 \
    --json nameWithOwner,defaultBranchRef,isFork,isPrivate,stargazerCount,forkCount,pushedAt \
    --jq '
      .[]
      | select(.isFork == false)
      | select(.defaultBranchRef != null)
      | [
          .nameWithOwner,
          .defaultBranchRef.name,
          (.isPrivate | tostring),
          (.stargazerCount | tostring),
          (.forkCount | tostring),
          (.pushedAt // "")
        ]
      | @tsv
    '
)

for row in "${REPOS[@]}"; do
  IFS=$'\t' read -r repo branch is_private stars forks pushed_at <<< "$row"

  REPO_TOTAL=$((REPO_TOTAL + 1))
  STARS_TOTAL=$((STARS_TOTAL + stars))
  FORKS_TOTAL=$((FORKS_TOTAL + forks))

  if [[ "$is_private" == "true" ]]; then
    PRIVATE_REPOS=$((PRIVATE_REPOS + 1))
  else
    PUBLIC_REPOS=$((PUBLIC_REPOS + 1))
  fi

  if [[ -n "$pushed_at" ]] && { [[ "$pushed_at" == "$CUTOFF_30D" ]] || [[ "$pushed_at" > "$CUTOFF_30D" ]]; }; then
    ACTIVE_REPOS_30D=$((ACTIVE_REPOS_30D + 1))
  fi

  if BRANCH_NAMES="$(
    gh api \
      --paginate \
      "repos/$repo/branches?per_page=100" \
      --jq '.[].name' \
      2>/dev/null
  )"; then
    while IFS= read -r branch_name; do
      if [[ -n "$branch_name" ]]; then
        BRANCHES_TOTAL=$((BRANCHES_TOTAL + 1))
      fi
    done <<< "$BRANCH_NAMES"
  else
    BRANCH_SCAN_FAILED=$((BRANCH_SCAN_FAILED + 1))
  fi

  repo_has_recent=0

  if ! COMMIT_ROWS="$(
    gh api \
      --paginate \
      --method GET \
      "repos/$repo/commits" \
      -f sha="$branch" \
      -f author="$GITHUB_USER" \
      -f per_page=100 \
      --jq '.[] | [.sha, .commit.author.date] | @tsv' \
      2>/dev/null
  )"; then
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi

  REPO_COUNT=$((REPO_COUNT + 1))

  while IFS=$'\t' read -r sha authored_at; do
    if [[ -z "$sha" ]]; then
      continue
    fi

    UNIQUE_SHAS["$sha"]=1

    if [[ -n "$authored_at" ]] && { [[ "$authored_at" == "$CUTOFF_30D" ]] || [[ "$authored_at" > "$CUTOFF_30D" ]]; }; then
      RECENT_SHAS["$sha"]=1
      repo_has_recent=1
    fi
  done <<< "$COMMIT_ROWS"

  if (( repo_has_recent == 1 )); then
    ACTIVE_AUTHOR_REPOS_30D=$((ACTIVE_AUTHOR_REPOS_30D + 1))
  fi
done

TOTAL_COMMITS="${#UNIQUE_SHAS[@]}"
COMMITS_30D="${#RECENT_SHAS[@]}"

if ! PRS_AUTHORED="$(
  gh api \
    --method GET \
    search/issues \
    -f q="author:$GITHUB_USER is:pr" \
    -f per_page=1 \
    --jq '.total_count' \
    2>/dev/null
)"; then
  PRS_AUTHORED="—"
fi

if ! ISSUES_AUTHORED="$(
  gh api \
    --method GET \
    search/issues \
    -f q="author:$GITHUB_USER is:issue" \
    -f per_page=1 \
    --jq '.total_count' \
    2>/dev/null
)"; then
  ISSUES_AUTHORED="—"
fi

cd "$GITHUB_WORKSPACE"
mkdir -p assets

cat > assets/commit-count.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="340" height="200" viewBox="0 0 340 200">
  <style>* { font-family: 'Segoe UI', Ubuntu, "Helvetica Neue", Sans-Serif; }</style>
  <rect x="1" y="1" width="338" height="198" rx="5" ry="5" fill="#0d1117" stroke="#2e343b" stroke-width="1"/>
  <text x="30" y="40" font-size="22" fill="#0366d6">Total Commits</text>
  <text x="30" y="112" font-size="46" font-weight="700" fill="#40c463">$TOTAL_COMMITS</text>
  <text x="30" y="145" font-size="14" fill="#77909c">Public + Private</text>
  <text x="30" y="170" font-size="12" fill="#77909c">Default branches · unique commits</text>
  <text x="310" y="185" text-anchor="end" font-size="10" fill="#77909c">updated $UPDATED</text>
</svg>
SVG

cat > assets/activity-stats.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="340" height="200" viewBox="0 0 340 200">
  <style>* { font-family: 'Segoe UI', Ubuntu, "Helvetica Neue", Sans-Serif; }</style>
  <rect x="1" y="1" width="338" height="198" rx="5" ry="5" fill="#0d1117" stroke="#2e343b" stroke-width="1"/>
  <text x="30" y="38" font-size="22" fill="#0366d6">Recent Activity</text>

  <text x="30" y="78" font-size="13" fill="#77909c">Commits · 30d</text>
  <text x="155" y="78" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$COMMITS_30D</text>
  <text x="185" y="78" font-size="13" fill="#77909c">Repos · 30d</text>
  <text x="310" y="78" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$ACTIVE_AUTHOR_REPOS_30D</text>

  <text x="30" y="122" font-size="13" fill="#77909c">PRs authored</text>
  <text x="155" y="122" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$PRS_AUTHORED</text>
  <text x="185" y="122" font-size="13" fill="#77909c">Issues authored</text>
  <text x="310" y="122" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$ISSUES_AUTHORED</text>

  <text x="30" y="166" font-size="12" fill="#77909c">GitHub-attributed activity · visible to token</text>
  <text x="310" y="185" text-anchor="end" font-size="10" fill="#77909c">updated $UPDATED</text>
</svg>
SVG

cat > assets/repository-stats.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg" width="340" height="200" viewBox="0 0 340 200">
  <style>* { font-family: 'Segoe UI', Ubuntu, "Helvetica Neue", Sans-Serif; }</style>
  <rect x="1" y="1" width="338" height="198" rx="5" ry="5" fill="#0d1117" stroke="#2e343b" stroke-width="1"/>
  <text x="30" y="38" font-size="22" fill="#0366d6">Repository Overview</text>
  <text x="30" y="72" font-size="13" fill="#77909c">Tracked repos</text>
  <text x="155" y="72" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$REPO_TOTAL</text>
  <text x="185" y="72" font-size="13" fill="#77909c">Branches</text>
  <text x="310" y="72" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$BRANCHES_TOTAL</text>
  <text x="30" y="105" font-size="13" fill="#77909c">Public</text>
  <text x="155" y="105" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$PUBLIC_REPOS</text>
  <text x="185" y="105" font-size="13" fill="#77909c">Private</text>
  <text x="310" y="105" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$PRIVATE_REPOS</text>
  <text x="30" y="138" font-size="13" fill="#77909c">Stars</text>
  <text x="155" y="138" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$STARS_TOTAL</text>
  <text x="185" y="138" font-size="13" fill="#77909c">Forks</text>
  <text x="310" y="138" text-anchor="end" font-size="17" font-weight="700" fill="#40c463">$FORKS_TOTAL</text>
  <text x="30" y="166" font-size="12" fill="#77909c">Non-forks visible to the stats token</text>
  <text x="310" y="185" text-anchor="end" font-size="10" fill="#77909c">updated $UPDATED</text>
</svg>
SVG

echo "Profile stats generated successfully."
echo "Total unique commits: $TOTAL_COMMITS"
echo "Commits in last 30 days: $COMMITS_30D"
echo "Repositories: $REPO_TOTAL ($PUBLIC_REPOS public / $PRIVATE_REPOS private)"
echo "Repositories pushed in last 30 days: $ACTIVE_REPOS_30D"
echo "Repositories with attributed commits in last 30 days: $ACTIVE_AUTHOR_REPOS_30D"
echo "Stars: $STARS_TOTAL"
echo "Forks: $FORKS_TOTAL"
echo "Branches across tracked repositories: $BRANCHES_TOTAL"
echo "Repositories skipped during branch scan: $BRANCH_SCAN_FAILED"
echo "PRs authored: $PRS_AUTHORED"
echo "Issues authored: $ISSUES_AUTHORED"
echo "Repositories processed for commit stats: $REPO_COUNT"
echo "Repositories skipped after API error: $FAILED_COUNT"
