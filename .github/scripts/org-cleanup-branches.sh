#!/usr/bin/env bash
# ============================================================
# Apaga, em todos os repos da org, branches sem commit há mais
# de $DAYS dias, exceto:
#   - main, develop e a branch padrão do repo
#   - branches usadas por PR aberto (head ou base)
#   - branches com proteção do GitHub
#
# ⚠️  ESTE REPO É PÚBLICO: o log e o summary do Actions podem ser
#     lidos por qualquer pessoa. No CI este script imprime SOMENTE
#     totais — nunca nome de repo, branch, SHA ou conta.
#
# Detalhes (repo/branch/SHA) só aparecem rodando localmente, por
# um admin autenticado, com VERBOSE=1:
#
#     DRY_RUN=true VERBOSE=1 ORG=Area-tech-alpha DAYS=3 \
#       bash .github/scripts/org-cleanup-branches.sh
#
# Restaurar uma branch apagada: o GitHub registra cada deleção na
# Activity do próprio repo (privada para repos privados):
#
#     gh api "repos/<org>/<repo>/activity?activity_type=branch_deletion" \
#       --jq '.[] | "\(.timestamp) \(.ref) \(.before)"'
#     gh api -X POST repos/<org>/<repo>/git/refs \
#       -f ref=refs/heads/<branch> -f sha=<before>
#
# Ou pela UI: https://github.com/<org>/<repo>/activity
# ============================================================
set -uo pipefail  # sem -e: erros são tratados e contados abaixo

: "${ORG:?defina ORG}"
DAYS="${DAYS:-3}"
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-0}"
SUMMARY="${GITHUB_STEP_SUMMARY:-/dev/null}"

if [ "${GITHUB_ACTIONS:-}" = "true" ] && [ "$VERBOSE" != "0" ]; then
  echo "ERRO: VERBOSE não é permitido no Actions (o log deste repo é público)."
  exit 1
fi
if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ]; then
  echo "ERRO: DAYS precisa ser um inteiro >= 1."
  exit 1
fi

# Detalhe só no modo local. Nada que passe por aqui vai para o log do CI.
detail() { [ "$VERBOSE" != "0" ] && echo "$@" >&2; return 0; }

# Extrai só o código HTTP de um erro do gh (a mensagem crua contém a URL,
# que tem o nome do repo).
http_code() { grep -oE 'HTTP [0-9]{3}' <<< "$1" | head -n1 || true; }

declare -A ERR_KINDS=()
count_error() {
  local kind="$1"
  ERR_KINDS["$kind"]=$(( ${ERR_KINDS["$kind"]:-0} + 1 ))
}

urlenc() { printf '%s' "$1" | jq -sRr @uri | sed 's|%2F|/|g'; }

CUTOFF=$(date -d "${DAYS} days ago" +%s)
KEEP="^(main|develop)$"
TOTAL_DELETED=0
TOTAL_ERRORS=0
TOTAL_REPOS=0
TOTAL_REPOS_SKIPPED=0
REPOS_TOUCHED=0

echo "========================================"
echo " Org Branch Cleanup — $(date -u '+%Y-%m-%d %H:%M UTC')"
echo " Threshold: ${DAYS} dias | Dry run: ${DRY_RUN}"
echo "========================================"

# Valida o token sem imprimir a conta dona dele.
if ! gh api user --silent 2>/dev/null; then
  echo "ERRO: token inválido ou sem permissão."
  exit 1
fi

if ! repos=$(gh api "orgs/$ORG/repos?per_page=100&type=all" --paginate \
      --jq '.[] | select(.archived == false) | .name' 2>/dev/null); then
  echo "ERRO ao listar repos da org."
  exit 1
fi

for repo in $repos; do
  ((TOTAL_REPOS++))
  deleted_here=0

  if ! default_branch=$(gh api "repos/$ORG/$repo" --jq '.default_branch' 2>&1) || [ -z "$default_branch" ]; then
    count_error "ler branch padrão ($(http_code "$default_branch"))"
    detail "  ⚠ $repo: não consegui ler a branch padrão — pulado"
    ((TOTAL_REPOS_SKIPPED++)); continue
  fi

  # Se a listagem de PRs falhar, o repo é pulado — nunca apagar sem saber.
  if ! open_pr_refs=$(gh api "repos/$ORG/$repo/pulls?state=open&per_page=100" --paginate \
        --jq ".[] | (select(.head.repo.full_name == \"$ORG/$repo\") | .head.ref), .base.ref" 2>&1); then
    count_error "listar PRs abertos ($(http_code "$open_pr_refs"))"
    detail "  ⚠ $repo: falha ao listar PRs abertos — pulado"
    ((TOTAL_REPOS_SKIPPED++)); continue
  fi

  if ! branches=$(gh api "repos/$ORG/$repo/branches?per_page=100" --paginate \
        --jq '.[] | select(.protected | not) | .name' 2>&1); then
    count_error "listar branches ($(http_code "$branches"))"
    detail "  ⚠ $repo: falha ao listar branches — pulado"
    ((TOTAL_REPOS_SKIPPED++)); continue
  fi

  for branch in $branches; do
    [ "$branch" == "$default_branch" ] && continue
    [[ "$branch" =~ $KEEP ]] && continue
    grep -qxF -- "$branch" <<< "$open_pr_refs" && continue

    enc=$(urlenc "$branch")
    if ! info=$(gh api "repos/$ORG/$repo/branches/$enc" \
          --jq '"\(.commit.sha) \(.commit.commit.committer.date)"' 2>&1); then
      count_error "ler branch ($(http_code "$info"))"
      detail "  ✗ erro lendo $repo/$branch"
      ((TOTAL_ERRORS++)); continue
    fi
    sha=${info%% *}
    last_ts=$(date -d "${info#* }" +%s 2>/dev/null) || continue
    [ "$last_ts" -ge "$CUTOFF" ] && continue
    age_days=$(( ( $(date +%s) - last_ts ) / 86400 ))

    if [ "$DRY_RUN" == "true" ]; then
      detail "  [DRY RUN] $repo/$branch (${age_days}d) sha=$sha"
      ((TOTAL_DELETED++)); deleted_here=1
    elif result=$(gh api -X DELETE "repos/$ORG/$repo/git/refs/heads/$enc" 2>&1); then
      detail "  ✓ apagada: $repo/$branch (${age_days}d) sha=$sha"
      ((TOTAL_DELETED++)); deleted_here=1
    else
      count_error "apagar branch ($(http_code "$result"))"
      detail "  ✗ erro apagando $repo/$branch"
      ((TOTAL_ERRORS++))
    fi
  done
  [ "$deleted_here" -eq 1 ] && ((REPOS_TOUCHED++))
done

if [ "$DRY_RUN" == "true" ]; then ACTION="Seriam apagadas"; MODE="Simulação (dry run)"; else ACTION="Apagadas"; MODE="Execução real"; fi

echo ""
echo "========================================"
echo " ${ACTION}: ${TOTAL_DELETED} branches em ${REPOS_TOUCHED} repos"
echo " Repos verificados: ${TOTAL_REPOS} | pulados por erro: ${TOTAL_REPOS_SKIPPED} | erros em branches: ${TOTAL_ERRORS}"
for kind in "${!ERR_KINDS[@]}"; do
  echo "   - falha ao ${kind}: ${ERR_KINDS[$kind]}"
done
echo "========================================"

{
  echo "## Org Branch Cleanup — ${MODE}"
  echo ""
  echo "| | |"
  echo "|---|---|"
  echo "| Threshold | ${DAYS} dias sem commit |"
  echo "| ${ACTION} | ${TOTAL_DELETED} branches em ${REPOS_TOUCHED} repos |"
  echo "| Repos verificados | ${TOTAL_REPOS} (pulados por erro: ${TOTAL_REPOS_SKIPPED}) |"
  echo "| Erros em branches | ${TOTAL_ERRORS} |"
  echo ""
  echo "> Este repo é público: nomes de repos, branches e SHAs não são exibidos aqui."
  echo "> Para ver o que foi apagado e restaurar, use a **Activity** de cada repo"
  echo "> (\`/activity?activity_type=branch_deletion\`) ou rode o script localmente com"
  echo "> \`VERBOSE=1\` — instruções no cabeçalho de \`.github/scripts/org-cleanup-branches.sh\`."
} >> "$SUMMARY"

[ "$TOTAL_ERRORS" -eq 0 ] && [ "$TOTAL_REPOS_SKIPPED" -eq 0 ]
