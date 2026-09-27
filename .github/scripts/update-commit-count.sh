#!/usr/bin/env bash
set -euo pipefail

GITHUB_USER="${GITHUB_USER:-loic31000}"

declare -A UNIQUE_SHAS=()

REPO_COUNT=0
FAILED_COUNT=0

# Récupère les dépôts accessibles au token :
# - publics
# - privés
# - appartenant à loic31000
# - ignore les forks
# - récupère leur branche par défaut
mapfile -t REPOS < <(
  gh repo list "$GITHUB_USER" \
    --limit 1000 \
    --json nameWithOwner,defaultBranchRef,isFork \
    --jq '
      .[]
      | select(.isFork == false)
      | select(.defaultBranchRef != null)
      | [.nameWithOwner, .defaultBranchRef.name]
      | @tsv
    '
)

for row in "${REPOS[@]}"; do

  IFS=$'\t' read -r repo branch <<< "$row"

  # Récupère uniquement les commits :
  # - présents sur la branche par défaut
  # - attribués par GitHub au compte loic31000
  #
  # Le filtre "author=loic31000" permet à GitHub de gérer
  # lui-même les adresses e-mail liées au compte.
  if ! SHAS="$(
    gh api \
      --paginate \
      --method GET \
      "repos/$repo/commits" \
      -f sha="$branch" \
      -f author="$GITHUB_USER" \
      -f per_page=100 \
      --jq '.[].sha' \
      2>/dev/null
  )"; then

    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi

  REPO_COUNT=$((REPO_COUNT + 1))

  while IFS= read -r sha; do
    if [[ -n "$sha" ]]; then
      UNIQUE_SHAS["$sha"]=1
    fi
  done <<< "$SHAS"

done

TOTAL="${#UNIQUE_SHAS[@]}"
UPDATED="$(date -u +%F)"

cd "$GITHUB_WORKSPACE"

mkdir -p assets

cat > assets/commit-count.svg <<SVG
<svg xmlns="http://www.w3.org/2000/svg"
     width="340"
     height="200"
     viewBox="0 0 340 200">

  <style>
    * {
      font-family: 'Segoe UI', Ubuntu, "Helvetica Neue", Sans-Serif;
    }
  </style>

  <rect
      x="1"
      y="1"
      width="338"
      height="198"
      rx="5"
      ry="5"
      fill="#0d1117"
      stroke="#2e343b"
      stroke-width="1" />

  <text
      x="30"
      y="40"
      font-size="22"
      fill="#0366d6">
    Total Commits
  </text>

  <text
      x="30"
      y="112"
      font-size="46"
      font-weight="700"
      fill="#40c463">
    $TOTAL
  </text>

  <text
      x="30"
      y="145"
      font-size="14"
      fill="#77909c">
    Public + Private
  </text>

  <text
      x="30"
      y="170"
      font-size="12"
      fill="#77909c">
    Default branches · unique commits
  </text>

  <text
      x="310"
      y="185"
      text-anchor="end"
      font-size="10"
      fill="#77909c">
    updated $UPDATED
  </text>

</svg>
SVG

echo "Commit counter generated successfully."
echo "Total unique commits: $TOTAL"
echo "Repositories processed: $REPO_COUNT"
echo "Repositories skipped after API error: $FAILED_COUNT"
