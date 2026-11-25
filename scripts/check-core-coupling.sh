#!/usr/bin/env bash
# The core is compiled into both apps, so a change under core/ has to be released by both
# macOS and Android. Change files live in .changeset/*.md with a `package: type` front matter.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! git diff --quiet --cached core/ 2>/dev/null || [ -n "${KNOPE_CHECK_CORE:-}" ]; then
  :
fi

# packages named by the change files
files=(.changeset/*.md)
if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
  exit 0
fi
packages=$(grep -hE '^(macos|android)[[:space:]]*:' "${files[@]}" | cut -d: -f1 | sort -u || true)

# does any change file mention the core?
core_changed=0
for f in "${files[@]}"; do
  if grep -qE '^core[[:space:]]*:|core/' "$f"; then core_changed=1; fi
done
if [ "$core_changed" = "0" ]; then
  exit 0
fi

for required in macos android; do
  if ! echo "$packages" | grep -qx "$required"; then
    echo "core changed but .changeset has no '$required' change file (see AGENTS.md: versions)" >&2
    exit 1
  fi
done
