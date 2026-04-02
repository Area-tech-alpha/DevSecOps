# 🛡️ Guia: Atualização de Pacotes com Vulnerabilidades Críticas

> Documento de referência para resolver alertas de segurança em projetos Node.js/npm/pnpm.

---

## 📋 Índice

1. [Entendendo o Alerta](#1-entendendo-o-alerta)
2. [Diagnóstico: Dependência Direta vs Transitiva](#2-diagnóstico-dependência-direta-vs-transitiva)
3. [Cenário A — Dependência Direta](#3-cenário-a--dependência-direta)
4. [Cenário B — Dependência Transitiva (Indireta)](#4-cenário-b--dependência-transitiva-indireta)
5. [Usando Overrides para Forçar Versões](#5-usando-overrides-para-forçar-versões)
6. [Verificação Pós-Atualização](#6-verificação-pós-atualização)
7. [Caso Prático Completo](#7-caso-prático-completo)
8. [Comandos de Referência Rápida](#8-comandos-de-referência-rápida)
9. [Quando NÃO Atualizar](#9-quando-não-atualizar)
10. [Security Gate Híbrido (CI/CD)](#10-security-gate-híbrido-cicd)

---

## 1. Entendendo o Alerta

Cada vulnerabilidade possui uma estrutura padrão:

```
• GHSA-XXXX-XXXX-XXXX   ← Identificador único no GitHub Advisory Database
  🎯 Alvo: pacote@versão   ← Pacote e versão vulnerável instalada
  🚨 Ameaça: descrição     ← O que um atacante pode explorar
  💉 Fix: versão corrigida  ← Versão mínima que resolve o problema
```

### Níveis de severidade (CVSS)

| Nível      | Score   | Ação recomendada                     |
|------------|---------|--------------------------------------|
| Critical   | 9.0–10  | Corrigir **imediatamente**           |
| High       | 7.0–8.9 | Corrigir em **24–48h**               |
| Medium     | 4.0–6.9 | Corrigir no próximo **sprint/ciclo** |
| Low        | 0.1–3.9 | Avaliar e agendar                    |

> **Dica:** Consulte detalhes completos de qualquer GHSA em `https://github.com/advisories/GHSA-XXXX-XXXX-XXXX`

---

## 2. Diagnóstico: Dependência Direta vs Transitiva

Antes de sair rodando `npm install`, você precisa saber **de onde vem** o pacote vulnerável. Isso define completamente a estratégia de correção.

### Passo 1 — Rodar o audit

```bash
# npm
npm audit

# pnpm
pnpm audit
```

### Passo 2 — Descobrir a cadeia de dependência

```bash
# npm: mostra a árvore de quem depende do pacote vulnerável
npm ls minimatch

# pnpm
pnpm ls minimatch --depth Infinity
```

**Saída de exemplo:**

```
meu-projeto@1.0.0
├── eslint@8.50.0
│   └── minimatch@3.1.2        ← transitiva (vem pelo eslint)
└── minimatch@9.0.5            ← direta (está no seu package.json)
```

### Interpretação

| Situação | Significado | Estratégia |
|----------|-------------|------------|
| Aparece no seu `package.json` | **Dependência direta** — você controla | Atualize direto |
| Aparece apenas como sub-dependência | **Dependência transitiva** — outro pacote controla | Use overrides ou atualize o pacote pai |

---

## 3. Cenário A — Dependência Direta

Quando o pacote vulnerável está **no seu `package.json`**, a correção é simples:

### npm

```bash
# Atualizar para a versão corrigida (respeitando semver)
npm install pacote@^versao-corrigida

# Exemplos reais:
npm install effect@^3.20.0
npm install flatted@^3.4.2
npm install next@^15.0.8
npm install tar@^7.5.11
```

### pnpm

```bash
pnpm update effect@>=3.20.0
pnpm update flatted@>=3.4.2
pnpm update next@>=15.0.8
pnpm update tar@>=7.5.11
```

### Após instalar

1. Verifique se a versão nova foi instalada: `npm ls pacote`
2. Rode os testes: `npm test`
3. Faça smoke test manual na aplicação
4. Commit com mensagem descritiva:
   ```bash
   git commit -m "security: atualiza pacote@versão — corrige GHSA-XXXX-XXXX-XXXX"
   ```

---

## 4. Cenário B — Dependência Transitiva (Indireta)

Este é o cenário mais comum e mais frustrante. O pacote vulnerável **não está no seu `package.json`** — ele vem como sub-dependência de outro pacote.

### Estratégia 1: Atualizar o pacote pai

Às vezes, o pacote pai já lançou uma versão que usa a versão corrigida da sub-dependência.

```bash
# Verificar se há updates disponíveis para o pacote pai
npm outdated eslint    # exemplo: eslint depende de minimatch

# Se houver versão nova, atualize
npm install eslint@latest
```

### Estratégia 2: `npm audit fix`

O npm pode resolver algumas vulnerabilidades automaticamente:

```bash
# Tenta corrigir sem breaking changes
npm audit fix

# Tenta corrigir mesmo com breaking changes (⚠️ pode quebrar coisas)
npm audit fix --force
```

> ⚠️ **Cuidado com `--force`**: ele pode fazer major upgrades que quebram sua aplicação. Sempre revise o que ele vai fazer antes de aceitar.

### Estratégia 3: Overrides (próxima seção)

Quando o pacote pai não atualizou a sub-dependência, você pode **forçar** a versão via overrides.

---

## 5. Usando Overrides para Forçar Versões

Overrides permitem que você **substitua a versão de qualquer sub-dependência** na árvore inteira do projeto, independente do que os pacotes pais pedem.

### npm (package.json)

Adicione o campo `overrides` no seu `package.json`:

```json
{
  "name": "meu-projeto",
  "version": "1.0.0",
  "dependencies": {
    "eslint": "^8.50.0",
    "next": "^15.5.9"
  },
  "overrides": {
    "minimatch": "^10.2.3",
    "flatted": "^3.4.2",
    "picomatch": "^4.0.4",
    "tar": "^7.5.11"
  }
}
```

### pnpm (package.json ou .npmrc)

No pnpm, o equivalente se chama `pnpm.overrides`:

```json
{
  "pnpm": {
    "overrides": {
      "minimatch": ">=10.2.3",
      "flatted": ">=3.4.2",
      "picomatch": ">=4.0.4",
      "tar": ">=7.5.11"
    }
  }
}
```

### Overrides seletivos (apenas para um pacote pai específico)

Se você quer forçar a versão apenas quando o pacote vem por uma cadeia específica:

```json
{
  "overrides": {
    "eslint": {
      "minimatch": "^10.2.3"
    }
  }
}
```

### Após configurar overrides

```bash
# Limpar cache e reinstalar
rm -rf node_modules package-lock.json   # npm
npm install

# Ou para pnpm:
rm -rf node_modules pnpm-lock.yaml
pnpm install

# Verificar que a versão correta foi instalada
npm ls minimatch
```

> ⚠️ **Riscos dos overrides:** Você está forçando uma versão que o pacote pai pode não suportar. Isso pode causar:
> - Erros de runtime se a API do pacote mudou entre major versions
> - Comportamento inesperado em edge cases
> - Falha silenciosa em funcionalidades que dependem da versão antiga
>
> **Sempre rode os testes após aplicar overrides.**

---

## 6. Verificação Pós-Atualização

### Checklist completo

```bash
# 1. Verificar que não há mais vulnerabilidades
npm audit
# ou
pnpm audit

# 2. Confirmar versões instaladas dos pacotes atualizados
npm ls effect flatted minimatch picomatch tar next preact

# 3. Rodar testes automatizados
npm test

# 4. Build de produção (detecta erros de tipagem e imports)
npm run build

# 5. Smoke test local
npm run dev
# → Testar os fluxos principais da aplicação manualmente
```

### Se algo quebrar

1. **Leia o changelog** do pacote que foi atualizado (no GitHub ou npm)
2. **Procure breaking changes** entre a versão antiga e a nova
3. **Ajuste seu código** para a nova API, se necessário
4. Se for uma dependência transitiva via override, considere:
   - Remover o override e aguardar o pacote pai atualizar
   - Abrir uma issue/PR no repositório do pacote pai
   - Procurar um pacote alternativo que não tenha a vulnerabilidade

---

## 7. Caso Prático Completo

Vamos resolver as vulnerabilidades do relatório de exemplo, passo a passo.

### Passo 1 — Classificar por tipo

**Dependências que provavelmente são diretas** (verificar no `package.json`):
- `effect@3.16.12`
- `next@15.5.9`
- `preact@10.27.1`

**Dependências que provavelmente são transitivas:**
- `flatted@3.3.3`
- `minimatch@3.1.2` / `minimatch@9.0.5`
- `picomatch@2.3.1` / `picomatch@4.0.3`
- `tar@7.4.3`

### Passo 2 — Confirmar com `npm ls`

```bash
npm ls effect flatted minimatch picomatch tar next preact
```

### Passo 3 — Atualizar dependências diretas

```bash
npm install effect@^3.20.0 next@^15.5.10 preact@^10.26.10
```

> **Nota sobre `next`:** O alerta pede `>=15.0.8`, mas você já tem `15.5.9`. Verifique se existe uma versão `15.5.x` ou `15.6.x` com o patch. Pode ser que a `15.5.9` já contenha o fix — consulte o advisory para confirmar.

### Passo 4 — Configurar overrides para transitivas

Adicione ao `package.json`:

```json
{
  "overrides": {
    "flatted": "^3.4.2",
    "minimatch": "^10.2.3",
    "picomatch": "^4.0.4",
    "tar": "^7.5.11"
  }
}
```

### Passo 5 — Reinstalar

```bash
rm -rf node_modules package-lock.json
npm install
```

### Passo 6 — Verificar

```bash
npm audit
npm test
npm run build
```

### Passo 7 — Commit

```bash
git add package.json package-lock.json
git commit -m "security: corrige 19 vulnerabilidades críticas (GHSA-*)"
```

---

## 8. Comandos de Referência Rápida

| Objetivo | npm | pnpm |
|----------|-----|------|
| Listar vulnerabilidades | `npm audit` | `pnpm audit` |
| Corrigir automaticamente | `npm audit fix` | `pnpm audit --fix` |
| Corrigir com force | `npm audit fix --force` | — |
| Ver árvore de dependência | `npm ls pacote` | `pnpm ls pacote --depth Infinity` |
| Instalar versão específica | `npm install pacote@^X.Y.Z` | `pnpm add pacote@^X.Y.Z` |
| Ver versões disponíveis | `npm view pacote versions` | `pnpm view pacote versions` |
| Ver pacotes desatualizados | `npm outdated` | `pnpm outdated` |
| Limpar cache | `npm cache clean --force` | `pnpm store prune` |
| Verificar integridade | `npm ci` | `pnpm install --frozen-lockfile` |

---

## 9. Quando NÃO Atualizar

Nem toda vulnerabilidade precisa de ação imediata. Avalie:

### ✅ Atualize imediatamente se:
- A vulnerabilidade é **Critical** ou **High**
- O pacote é acessível a **input de usuário** (ex: parsers, servidores HTTP)
- O pacote é usado em **produção** (não apenas em dev/build)
- Existe **exploit público** (verifique no advisory)

### ⏸️ Pode esperar se:
- O pacote é apenas uma **devDependency** que nunca processa input externo
- A vulnerabilidade requer **condições muito específicas** que não se aplicam ao seu uso
- O pacote está em um **script de build** que roda apenas localmente
- O override quebraria funcionalidades críticas sem alternativa viável

### 🔍 Para avaliar o risco real:

1. Abra o advisory: `https://github.com/advisories/GHSA-XXXX-XXXX-XXXX`
2. Leia a seção "Impact" — quem é afetado?
3. Verifique se o seu uso do pacote se encaixa no cenário de exploit
4. Considere o conceito de **exploitability**: mesmo que a vulnerabilidade exista, ela é atingível no seu contexto?

---

## 10. Security Gate Híbrido (CI/CD)

O pipeline `alpha-security` utiliza uma estratégia de **duas camadas** para lidar com vulnerabilidades, separando o tratamento entre dependências diretas e transitivas.

### Arquitetura do Gate

```
┌─────────────────────────────────────────────────┐
│              OSV Scanner (scan completo)         │
│         Escaneia TUDO — diretas + transitivas    │
└─────────────────┬───────────────────────────────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
 ┌──────────────┐   ┌──────────────────┐
 │   DIRETAS     │   │   TRANSITIVAS     │
 │  HIGH/CRIT    │   │   HIGH/CRIT       │
 │               │   │                   │
 │  🔴 BLOCK     │   │  🟡 WARNING       │
 │  Pipeline     │   │  Loga, mas        │
 │  falha        │   │  não bloqueia     │
 └──────────────┘   └──────────────────┘
```

### Como funciona

1. **Extrai dependências diretas** do `package.json` (campos `dependencies` e `devDependencies`)
2. **Classifica cada vulnerabilidade** encontrada pelo OSV como:
   - **Direta** — nome do pacote aparece no `package.json` → tratada como responsabilidade do projeto
   - **Transitiva** — não aparece no `package.json` → responsabilidade do pacote pai
3. **Aplica o gate**:
   - Diretas HIGH/CRITICAL → `exit 1` (pipeline falha)
   - Transitivas HIGH/CRITICAL → log detalhado + link para overrides (pipeline continua)

### Fallback para projetos sem `package.json`

Para projetos Go, Python ou sem `package.json`, **todas** as vulnerabilidades são tratadas como diretas (modo seguro). Isso garante que projetos não-Node mantêm o comportamento de bloqueio completo.

### Por que NÃO ignorar transitivas completamente

| Fator | Risco |
|-------|-------|
| Transitivas rodam no mesmo processo | ReDOS, prototype pollution, etc. afetam seu app igual |
| Supply chain attacks | A maioria (event-stream, ua-parser-js, colors.js) foram em **transitivas** |
| O bundle final contém tudo | No `npm run build`, não existe separação — tudo é código que roda |
| Profundidade ≠ Segurança | Uma transitiva nível 5 que parseia input do usuário é mais perigosa que uma direta que gera logs |

### Corrigindo transitivas que aparecem como WARNING

Quando o pipeline mostrar um WARNING para transitiva, use **overrides** no `package.json`:

```json
{
  "overrides": {
    "pacote-transitivo": "^versao-corrigida"
  }
}
```

> Veja a [seção 5](#5-usando-overrides-para-forçar-versões) para detalhes completos sobre overrides.

### Customizando o comportamento

Para **bloquear transitivas também** (modo paranóico), remova a classificação e trate tudo como direta passando um array vazio `[]` no `direct-deps.json`. Isso é o equivalente ao comportamento anterior do gate.

---

## 📎 Referências

- [npm audit docs](https://docs.npmjs.com/cli/v10/commands/npm-audit)
- [GitHub Advisory Database](https://github.com/advisories)
- [npm overrides](https://docs.npmjs.com/cli/v10/configuring-npm/package-json#overrides)
- [pnpm overrides](https://pnpm.io/package_json#pnpmoverrides)
- [Node.js Security Best Practices](https://nodejs.org/en/learn/getting-started/security-best-practices)
- [OSV Scanner Config](https://google.github.io/osv-scanner/configuration/)

---

> **Última atualização:** 2026-04-02

