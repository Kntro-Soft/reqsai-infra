#!/usr/bin/env bash
# Release candidates for the Gitflow release flow (model C, tag at the end).
#
# A push to release/X.Y.Z or hotfix/X.Y.Z builds ONCE and stores the result as a GitHub pre-release
# vX.Y.Z-rc.N on that commit. Its asset candidate.json records the version, commit, git tree hash, build number,
# image digest and the SHA-256 of every asset, plus the stage the candidate passed (pending until the automatic
# verification or the staging deploy succeeds). When the release pull request is merged, production looks the
# candidate up by tree hash: main only ships bytes that were tested on the release branch, and the final tag
# vX.Y.Z is created after production succeeded.
#
# Commands (GH_TOKEN and GITHUB_REPOSITORY must be set; run from the repository root):
#   candidate.sh branch <branch> <version-file>    X.Y.Z of release/X.Y.Z or hotfix/X.Y.Z; checks the version file
#   candidate.sh version <version-file>            X.Y.Z from VERSION, package.json or build.gradle.kts
#   candidate.sh next <version> <commit>           "<N> <reused>": the rc of this commit, or the next free N
#   candidate.sh create <candidate.json> [asset..] create the pre-release (re-uploads the assets if it exists)
#   candidate.sh mark <tag> <stage> [json]         record the stage the candidate passed (and extra fields)
#   candidate.sh find <version> <tree>             candidate.json of the newest approved rc with that tree
#   candidate.sh fetch <tag> <dir>                 download the assets of a release and check their SHA-256
#   candidate.sh final <candidate.json> <commit> [asset..]   publish vX.Y.Z on the main commit
#   candidate.sh pr <head> <base> <title> <body-file>        open or update a pull request
#   candidate.sh automerge <pr-url>                turn on auto-merge (merge commit) when the repository allows it
#   candidate.sh notes <candidate.json>            print the release notes of a candidate
#
# pr and automerge run with a token of the GitHub App reqsai-release-bot (organization variable RELEASE_APP_ID,
# secret RELEASE_APP_PRIVATE_KEY): a pull request opened with GITHUB_TOKEN starts no pull_request workflows, so
# its CI would never report. Every other command runs with the workflow's GITHUB_TOKEN.
set -euo pipefail

repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is not set}"
server="${GITHUB_SERVER_URL:-https://github.com}"
semver='^[0-9]+\.[0-9]+\.[0-9]+$'

die() {
  echo "::error::$*" >&2
  exit 1
}

read_version() {
  local file="$1" version
  [[ -f "$file" ]] || die "Version file $file not found"
  case "$file" in
    *package.json) version=$(jq -r '.version // empty' "$file") ;;
    *.gradle.kts) version=$(sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' "$file" | head -n 1) ;;
    *) version=$(tr -d '[:space:]' <"$file") ;;
  esac
  [[ "$version" =~ $semver ]] || die "$file holds '$version', expected X.Y.Z"
  echo "$version"
}

tag_exists() {
  gh api "repos/$repo/git/ref/tags/$1" >/dev/null 2>&1
}

cmd_branch() {
  local branch="${1:?branch}" file="${2:?version file}" kind name version
  kind="${branch%%/*}"
  name="${branch#*/}"
  if [[ "$kind" != release && "$kind" != hotfix ]] || [[ ! "$name" =~ $semver ]]; then
    die "Name the branch release/X.Y.Z or hotfix/X.Y.Z (got $branch)"
  fi
  version=$(read_version "$file")
  if [[ "$version" != "$name" ]]; then
    die "$file says $version but the branch is $branch: commit 'chore(release): $name' setting the version to $name"
  fi
  if tag_exists "v$name"; then
    die "v$name is already released; a fix to a published version is a new version (hotfix/X.Y.Z+1)"
  fi
  echo "$name"
}

cmd_next() {
  local version="${1:?version}" commit="${2:?commit}" max=0 reused=false n ref sha
  while read -r ref sha; do
    [[ -n "$ref" ]] || continue
    n="${ref##*-rc.}"
    [[ "$n" =~ ^[0-9]+$ ]] || continue
    if [[ "$sha" == "$commit" ]]; then
      echo "$n true"
      return
    fi
    if ((n > max)); then max=$n; fi
  done < <(gh api "repos/$repo/git/matching-refs/tags/v$version-rc." --jq '.[] | "\(.ref) \(.object.sha)"')
  echo "$((max + 1)) $reused"
}

cmd_notes() {
  local json="${1:?candidate.json}"
  jq -r --arg server "$server" '
    def row($k; $v): if ($v // "") == "" then empty else "| \($k) | \($v) |" end;
    [
      "Release candidate **\(.candidate)** of `\(.repository)` (version \(.version), build \(.build)).",
      "",
      "| | |",
      "| --- | --- |",
      row("Commit"; "[`\(.commit)`](\($server)/\(.repository)/commit/\(.commit)) on `\(.branch)`"),
      row("Tree"; "`\(.tree)`"),
      row("Built by"; .run_url),
      row("Image"; (if .digest then "`\(.image)@\(.digest)`" else null end)),
      row("Staging"; .staging_url),
      row("Stage"; "**\(.stage)**" + (if .stage_url then " · \(.stage_url)" else "" end)),
      "",
      (if (.assets // {}) | length > 0 then
        "| Asset | SHA-256 |\n| --- | --- |\n" + ([.assets | to_entries[] | "| `\(.key)` | `\(.value)` |"] | join("\n"))
       else empty end),
      "",
      "Production ships this candidate only from a `main` commit whose tree is `\(.tree)`, without rebuilding."
    ] | join("\n")' "$json"
}

cmd_create() {
  local json="${1:?candidate.json}" tag dir
  shift
  tag=$(jq -r .tag "$json")
  dir=$(mktemp -d)
  cp "$json" "$dir/candidate.json"
  cmd_notes "$json" >"$dir/notes.md"
  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "$tag already exists: re-uploading its assets" >&2
    gh release upload "$tag" --repo "$repo" --clobber "$dir/candidate.json" "$@"
    gh release edit "$tag" --repo "$repo" --notes-file "$dir/notes.md" >/dev/null
  else
    gh release create "$tag" --repo "$repo" --prerelease --target "$(jq -r .commit "$json")" \
      --title "$tag" --notes-file "$dir/notes.md" "$dir/candidate.json" "$@" >/dev/null
  fi
  rm -rf "$dir"
  echo "$server/$repo/releases/tag/$tag"
}

cmd_mark() {
  local tag="${1:?tag}" stage="${2:?stage}" extra="${3:-}" dir
  [[ -n "$extra" ]] || extra='{}'
  dir=$(mktemp -d)
  gh release download "$tag" --repo "$repo" --pattern candidate.json --dir "$dir/old"
  jq --arg stage "$stage" --arg url "${STAGE_URL:-}" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson extra "$extra" \
    '. + {stage: $stage, stage_url: (if $url == "" then null else $url end), stage_at: $at} + $extra' \
    "$dir/old/candidate.json" >"$dir/candidate.json"
  cmd_notes "$dir/candidate.json" >"$dir/notes.md"
  gh release upload "$tag" --repo "$repo" --clobber "$dir/candidate.json"
  gh release edit "$tag" --repo "$repo" --notes-file "$dir/notes.md" >/dev/null
  cat "$dir/candidate.json"
  rm -rf "$dir"
}

cmd_find() {
  local version="${1:?version}" tree="${2:?tree}" tag json pending=""
  while read -r tag; do
    [[ -n "$tag" ]] || continue
    json=$(gh release download "$tag" --repo "$repo" --pattern candidate.json --output - 2>/dev/null) || continue
    [[ "$(jq -r .tree <<<"$json")" == "$tree" ]] || continue
    if [[ "$(jq -r .stage <<<"$json")" == pending ]]; then
      pending="${pending:+$pending, }$tag"
      continue
    fi
    jq -c . <<<"$json"
    return
  done < <(gh api --paginate "repos/$repo/releases?per_page=100" \
    --jq ".[] | select(.prerelease and (.tag_name | startswith(\"v$version-rc.\"))) | .tag_name" \
    | sort -t. -k4,4nr)
  if [[ -n "$pending" ]]; then
    die "$pending match this tree but never passed verification/staging; re-run the release workflow of that candidate"
  fi
  die "No release candidate v$version-rc.N has tree $tree: main differs from the tested candidate. Push the change to the release branch to build a new rc, then merge it again."
}

cmd_fetch() {
  local tag="${1:?tag}" dir="${2:?dir}" name sum
  mkdir -p "$dir"
  gh release download "$tag" --repo "$repo" --dir "$dir" --clobber
  while read -r name sum; do
    [[ -n "$name" ]] || continue
    [[ -f "$dir/$name" ]] || die "$tag has no asset $name"
    [[ "$(sha256sum "$dir/$name" | cut -d' ' -f1)" == "$sum" ]] || die "$name of $tag does not match its SHA-256"
    echo "$name: sha256 $sum (verified)" >&2
  done < <(jq -r '(.assets // {}) | to_entries[] | "\(.key) \(.value)"' "$dir/candidate.json")
}

changelog_section() {
  [[ -f CHANGELOG.md ]] || return 0
  awk -v v="$1" '
    $0 ~ "^## \\[" v "\\]" { on = 1; next }
    on && /^## / { exit }
    on { print }' CHANGELOG.md
}

cmd_final() {
  local json="${1:?candidate.json}" commit="${2:?commit}" version tag dir section
  shift 2
  version=$(jq -r .version "$json")
  tag="v$version"
  dir=$(mktemp -d)
  jq --arg commit "$commit" --arg run "$server/$repo/actions/runs/${GITHUB_RUN_ID:-0}" \
    '. + {released_commit: $commit, released_by: $run}' "$json" >"$dir/candidate.json"
  section=$(changelog_section "$version")
  # GitHub refuses release notes over 125000 characters (reqsai-api 1.2.0 carried its whole history).
  if ((${#section} > 100000)); then
    section="${section:0:100000}"
    section="${section%$'\n'*}"$'\n\n'"…truncated: the full list is in [CHANGELOG.md]($server/$repo/blob/$commit/CHANGELOG.md)."
  fi
  {
    echo "Promoted to production from candidate **$(jq -r .candidate "$json")** without rebuilding."
    echo
    echo "- Released commit: \`$commit\` (tree \`$(jq -r .tree "$json")\`)"
    echo "- Candidate commit: \`$(jq -r .commit "$json")\` on \`$(jq -r .branch "$json")\`"
    jq -r 'if .digest then "- Image: `\(.image)@\(.digest)`" else empty end' "$json"
    jq -r 'if .production_url then "- Production: \(.production_url)" else empty end' "$json"
    jq -r '(.assets // {}) | to_entries[] | "- `\(.key)` sha256 `\(.value)`"' "$json"
    echo
    if [[ -n "$section" ]]; then
      echo "## Changes"
      echo "$section"
    else
      gh api "repos/$repo/releases/generate-notes" -f tag_name="$tag" -f target_commitish="$commit" --jq .body
    fi
  } >"$dir/notes.md"
  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    echo "$tag already exists: re-uploading its assets" >&2
    gh release upload "$tag" --repo "$repo" --clobber "$dir/candidate.json" "$@"
  else
    gh release create "$tag" --repo "$repo" --target "$commit" --title "$tag" --latest \
      --notes-file "$dir/notes.md" "$dir/candidate.json" "$@" >/dev/null
  fi
  rm -rf "$dir"
  echo "$server/$repo/releases/tag/$tag"
}

cmd_pr() {
  local head="${1:?head}" base="${2:?base}" title="${3:?title}" body="${4:?body file}" number ahead url
  ahead=$(gh api "repos/$repo/compare/$base...$head" --jq .ahead_by)
  if [[ "$ahead" == 0 ]]; then
    echo "$base already contains $head: no pull request needed." >&2
    return
  fi
  number=$(gh pr list --repo "$repo" --head "$head" --base "$base" --state open --json number --jq '.[0].number // empty')
  if [[ -n "$number" ]]; then
    gh pr edit "$number" --repo "$repo" --title "$title" --body-file "$body" >/dev/null
    echo "$server/$repo/pull/$number"
    return
  fi
  if ! url=$(gh pr create --repo "$repo" --head "$head" --base "$base" --title "$title" --body-file "$body"); then
    die "reqsai-release-bot could not open $head → $base. Check that the GitHub App is installed on $repo with Pull requests: read and write."
  fi
  echo "$url"
}

cmd_automerge() {
  local url="${1:?pull request URL}"
  if gh pr merge "$url" --repo "$repo" --auto --merge >/dev/null 2>&1; then
    echo "auto-merge on: it merges itself, with a merge commit, once approved and green"
    return
  fi
  echo "::warning title=Auto-merge not available::Auto-merge could not be turned on for $url (Settings → General → Allow auto-merge is off, or the pull request is already mergeable). Merge it by hand with a merge commit." >&2
  echo "merge it by hand, with a merge commit"
}

command="${1:-}"
shift || true
case "$command" in
  branch) cmd_branch "$@" ;;
  version) read_version "${1:?version file}" ;;
  next) cmd_next "$@" ;;
  create) cmd_create "$@" ;;
  mark) cmd_mark "$@" ;;
  find) cmd_find "$@" ;;
  fetch) cmd_fetch "$@" ;;
  final) cmd_final "$@" ;;
  pr) cmd_pr "$@" ;;
  automerge) cmd_automerge "$@" ;;
  notes) cmd_notes "$@" ;;
  *) die "Unknown command '$command' (branch, version, next, create, mark, find, fetch, final, pr, automerge, notes)" ;;
esac
