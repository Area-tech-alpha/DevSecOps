# Regras de segurança — Alpha DevSecOps

As configs desta pasta são usadas pelo `alpha-security.yaml` em **todos os repos da org**
(Required Workflow via Ruleset). Os repos leem a versão da `main`: uma regra alterada aqui
vale para a org inteira assim que entra na `main`.

| Arquivo | Ferramenta | O que bloqueia |
|---|---|---|
| `semgrep.yml` | Semgrep | regras `severity: ERROR` (as `WARNING` não rodam no CI) |
| `gitleaks.toml` | Gitleaks | qualquer achado, **em todo o histórico git** |
| `extract-direct-deps.sh` | OSV gate | define quais deps são diretas (HIGH/CRITICAL nelas bloqueiam) |
| `osv-scanner.toml` | OSV-Scanner | exceções de vulnerabilidades (`[[IgnoredVulns]]`) |

## Testes das regras

Toda mudança em `security/` precisa passar em:

```bash
python3 security/tests/run_tests.py -v          # tudo
python3 security/tests/run_tests.py semgrep     # semgrep | gitleaks | deps
```

Requer `semgrep`, `gitleaks`, `git`, `jq`. No CI roda o workflow **Security Rules Tests**
(`.github/workflows/security-rules-tests.yml`), só neste repo.

O harness roda Semgrep e Gitleaks **com os mesmos argumentos do `alpha-security.yaml`**
(os `--exclude` são lidos do próprio workflow) sobre um repo falso montado a partir de
`security/tests/cases/`, e aponta:

- **FP (falso positivo)**: achado numa linha que não está marcada como `ruleid`;
- **FN (falso negativo)**: linha marcada como `ruleid` que não foi detectada;
- **anotação desatualizada**: um gap conhecido (`todoruleid`/`todook`) foi corrigido.

### Adicionando um caso

O caminho dentro de `cases/` é o caminho no repo falso. Isso permite testar exclusões
como `src/__tests__/`, `e2e/`, `latest/`. Anote a linha **seguinte**:

```ts
// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const ADMIN_PASSWORD = "{{rand:16}}";

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const label = { tipo: "Alteração de senha" };

// todoruleid: generic-api-key-assignment   ← gap conhecido, não falha o teste
JWT_SECRET={{rand:32}}
```

- Regras `devsecops.*` são do Semgrep; as demais são ids do Gitleaks.
- As regras `generic-*` do Gitleaks deduplicam entre si, então contam como um grupo só.
- **Não commite segredos**, nem falsos: use `{{rand:N}}`, `{{upper:N}}`, `{{lower:N}}` ou
  `{{hex:N}}`. O valor é gerado na hora do teste, sem palavras que as regras ignoram.
- Para nomes que não devem existir no repo (ex.: `.env.production`), use um nome
  qualquer e declare o destino na 1ª linha: `# path: .env.production`.
- Achou um FP/FN num repo da org? Reproduza aqui primeiro (o teste deve falhar) e
  depois corrija a regra.

Casos de `extract-direct-deps.sh` ficam em `security/tests/deps/<caso>/`, com os
arquivos do projeto e um `expected.json`. Arquivos que o OSV leria como lockfile
(`go.mod`, `requirements.txt`, `package-lock.json`) levam o sufixo `.fixture`.
Um arquivo `KNOWN_GAP` marca o caso como gap conhecido.

## Para os devs: como tratar um falso positivo no seu repo

Marque **na linha**, com o id da regra. Assim a exceção fica visível no diff e passa
por review:

```ts
const seed = "valor-que-nao-e-segredo"; // nosemgrep: devsecops.security.hardcoded-password
const seed2 = "valor-que-nao-e-segredo"; // gitleaks:allow
```

Se o achado do Gitleaks está em um **commit antigo** (o scan cobre todo o histórico),
**rotacione a credencial primeiro**: ela já vazou. Depois adicione o fingerprint
(`commit:arquivo:regra:linha`, mostrado no log do Gitleaks) num `.gitleaksignore`
na raiz do repo.

Se a regra estiver errada para todo mundo, abra um PR aqui com o caso de teste.
