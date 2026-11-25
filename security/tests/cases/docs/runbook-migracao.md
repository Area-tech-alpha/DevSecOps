# Runbook de migração

Prosa citando variáveis não é segredo:

<!-- ok: devsecops.security.hardcoded-connection-string, devsecops.security.connection-string-by-uri, connection-string-with-credentials -->
Banco: a connection string do serviço principal, passada como DATABASE_URL.

<!-- ok: devsecops.security.hardcoded-connection-string, connection-string-with-credentials -->
Defina `DATABASE_URL="postgresql://<usuario>:<senha>@<host>:5432/<db>"` no provedor de deploy.

```bash
# ok: devsecops.security.hardcoded-connection-string, connection-string-with-credentials
docker compose run --rm -e DATABASE_URL="$DATABASE_URL" app node scripts/migrate.js
```

Roteiro de teste com nome + valor fictício: regras por NOME
não rodam em Markdown.

```bash
# ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
curl -d '{"accessToken": "EAAB{{rand:30}}", "userId": "1234"}' http://localhost:3000/integrations/connections
```

<!-- ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment -->
Adicione ao `.env` de teste: `PARTNER_APP_SECRET="{{rand:24}}"`.

Mas token com FORMATO de provedor continua sendo detectado em docs pelo Semgrep:

<!-- ruleid: devsecops.security.provider-specific-secret -->
<!-- todoruleid: github-pat -->
Token usado no deploy: ghp_{{rand:36}}

Credencial real colada num doc é vazamento como qualquer outro.
Hoje o Gitleaks ignora docs/*.md (allowlist global) e só o Semgrep pega.

```bash
# ruleid: devsecops.security.connection-string-by-uri
# todoruleid: connection-string-with-credentials
psql "postgresql://admin:{{rand:18}}@db.prod.internal:5432/app"
```
