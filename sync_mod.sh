#!/usr/bin/env bash
# Copies both mods from this repo into the local Project Zomboid mods folder.
set -euo pipefail

usage() {
	cat <<'EOF'
Usage: ./sync_mod.sh [options]

Mirrors DarkSoulsYouDied and DarkSoulsDeathAudioOnly from this repo into the
Project Zomboid local mods folder, so the game can load them.

Options:
  -n, --dry-run    Show what would change, write nothing
      --no-delete  Keep files in the target that no longer exist in the repo
  -h, --help       Show this help

Environment:
  PZ_MODS_DIR      Mods folder to install into (default: $HOME/Zomboid/mods)

Only one of the two mods may be enabled at a time. Mod Lua loads at boot, so
fully restart Project Zomboid after syncing.
EOF
}

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT="$REPO_DIR/Dark Souls You Died Death Screen/Contents/mods"
MODS_DIR="${PZ_MODS_DIR:-$HOME/Zomboid/mods}"
MOD_IDS=(DarkSoulsYouDied DarkSoulsDeathAudioOnly)

DRY_RUN=0
DELETE=1
while [[ $# -gt 0 ]]; do
	case "$1" in
		-n|--dry-run) DRY_RUN=1 ;;
		--no-delete) DELETE=0 ;;
		-h|--help) usage; exit 0 ;;
		*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
	esac
	shift
done

if [[ ! -d "$SOURCE_ROOT" ]]; then
	echo "error: mod source folder not found: $SOURCE_ROOT" >&2
	exit 1
fi

if ! command -v rsync >/dev/null 2>&1; then
	echo "error: rsync is not installed" >&2
	exit 1
fi

# A mod without 42/mod.info is invisible in the Build 42 mod list.
for id in "${MOD_IDS[@]}"; do
	if [[ ! -f "$SOURCE_ROOT/$id/42/mod.info" ]]; then
		echo "error: $id is missing 42/mod.info, the game would not list it" >&2
		exit 1
	fi
done

if pgrep -f 'projectzomboid' >/dev/null 2>&1; then
	echo "warning: Project Zomboid appears to be running; restart it after syncing" >&2
fi

echo "source: $SOURCE_ROOT"
echo "target: $MODS_DIR"
echo

RSYNC_ARGS=(-a --itemize-changes)
if [[ "$DELETE" == 1 ]]; then
	RSYNC_ARGS+=(--delete)
fi
if [[ "$DRY_RUN" == 1 ]]; then
	RSYNC_ARGS+=(--dry-run)
else
	mkdir -p "$MODS_DIR"
fi

changed=0
for id in "${MOD_IDS[@]}"; do
	target="$MODS_DIR/$id"
	printf '%s -> %s\n' "$id" "$target"
	if [[ "$DRY_RUN" == 0 ]]; then
		mkdir -p "$target"
	fi
	out="$(rsync "${RSYNC_ARGS[@]}" "$SOURCE_ROOT/$id/" "$target/")"
	if [[ -z "$out" ]]; then
		echo "    up to date"
	else
		echo "$out" | sed 's/^/    /'
		changed=1
	fi
done

echo
if [[ "$DRY_RUN" == 1 ]]; then
	echo "dry run: nothing was written"
elif [[ "$changed" == 1 ]]; then
	echo "synced into $MODS_DIR"
	echo "enable exactly one mod in the in-game mod manager, then fully restart Project Zomboid"
else
	echo "already in sync"
fi
