#!/usr/bin/env bash
# Extrai nomes de dependências DIRETAS de produção para o gate OSV.
# Saída: JSON array em stdout (ex.: ["express","pg"])
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

names=()

if [ -f package.json ] && jq -e . package.json >/dev/null 2>&1; then
  # Apenas dependencies (prod) — devDependencies não bloqueiam
  while IFS= read -r dep; do
    [ -n "$dep" ] && names+=("$dep")
  done < <(jq -r '(.dependencies // {}) | keys[]' package.json 2>/dev/null || true)

elif [ -f package-lock.json ] && jq -e . package-lock.json >/dev/null 2>&1; then
  lock_ver=$(jq -r '.lockfileVersion // 1' package-lock.json)
  if [ "${lock_ver:-1}" -ge 2 ]; then
    while IFS= read -r dep; do
      [ -n "$dep" ] && names+=("$dep")
    done < <(jq -r '(.packages[""].dependencies // {}) | keys[]' package-lock.json 2>/dev/null || true)
  else
    while IFS= read -r dep; do
      [ -n "$dep" ] && names+=("$dep")
    done < <(jq -r '(.dependencies // {}) | keys[]' package-lock.json 2>/dev/null || true)
  fi

elif [ -f go.mod ]; then
  in_block=0
  while IFS= read -r line; do
    # Remove leading/trailing spaces
    line=$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    [ -z "$line" ] && continue

    if [[ "$line" =~ ^"require (" || "$line" =~ ^"require(" ]]; then
      in_block=1
      continue
    fi

    if [ "$in_block" -eq 1 ]; then
      if [[ "$line" =~ ^")" ]]; then
        in_block=0
        continue
      fi
      if [[ "$line" =~ "// indirect" ]]; then
        continue
      fi
      dep=$(echo "$line" | awk '{print $1}')
      [ -n "$dep" ] && names+=("$dep")
    else
      if [[ "$line" =~ ^"require " ]]; then
        if [[ "$line" =~ "// indirect" ]]; then
          continue
        fi
        dep=$(echo "$line" | awk '{print $2}')
        [ -n "$dep" ] && names+=("$dep")
      fi
    fi
  done < go.mod

elif [ -f requirements.txt ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line=$(echo "$line" | tr -d '[:space:]')
    [ -z "$line" ] && continue
    dep="${line%%[<>=!~;[]*}"
    dep="${dep%%@*}"
    [ -n "$dep" ] && names+=("$dep")
  done < requirements.txt
fi

if [ "${#names[@]}" -eq 0 ]; then
  echo '[]'
  exit 0
fi

# Print all unique items, mapped to lowercase for robust matching
printf '%s\n' "${names[@]}" | sort -u | jq -R -s 'split("\n") | map(select(length > 0) | ascii_downcase)'
