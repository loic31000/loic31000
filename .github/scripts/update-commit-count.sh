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
     width="520"
     height="110"
     viewBox="0 0 520 110">

  <rect
      x="1"
      y="1"
      width="518"
      height="108"
      rx="8"
      fill="#0D1117"
      stroke="#30363D"
      stroke-width="2" />

  <text
      x="28"
      y="35"
      fill="#8B949E"
      font-family="Segoe UI, Ubuntu, Arial, sans-serif"
      font-size="15">
    DEFAULT-BRANCH COMMITS
  </text>

  <text
      x="28"
      y="81"
      fill="#00FF41"
      font-family="Segoe UI, Ubuntu, Arial, sans-serif"
      font-size="38"
      font-weight="700">
    $TOTAL
  </text>

  <text
      x="492"
      y="57"
      text-anchor="end"
      fill="#8B949E"
      font-family="Segoe UI, Ubuntu, Arial, sans-serif"
      font-size="12">
    PUBLIC + PRIVATE
  </text>

  <text
      x="492"
      y="79"
      text-anchor="end"
      fill="#8B949E"
      font-family="Segoe UI, Ubuntu, Arial, sans-serif"
      font-size="11">
    updated $UPDATED
  </text>

</svg>
SVG

echo "Commit counter generated successfully."
echo "Total unique commits: $TOTAL"
echo "Repositories processed: $REPO_COUNT"
echo "Repositories skipped after API error: $FAILED_COUNT"
