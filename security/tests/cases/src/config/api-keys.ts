// Casos: chaves de API / tokens / secrets atribuídos por NOME de variável.
// Regras: devsecops.security.hardcoded-api-key (Semgrep)
//         generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret (Gitleaks)

// ───── Devem ser detectados ─────

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret
const apiKey = "{{rand:32}}";

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret
export const API_KEY = '{{rand:40}}';

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
let jwtSecret = "{{lower:24}}";

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const config = { clientSecret: "{{rand:30}}" };

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const headers = { auth_token: `{{rand:28}}` };

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const STRIPE_SECRET = "{{lower:20}}";

// Prefixo "test" no NOME da variável não pode esconder um segredo real.
// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret
const TEST_API_KEY = "{{rand:32}}";

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
const GOOGLE_API_KEY = "{{rand:39}}";

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const stripeSecretKey = "{{rand:32}}";

// Chave só com maiúsculas E dígitos continua sendo chave.
// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
const LICENSE_API_KEY = "{{upper:32}}";

// Chave em JSON-like (chave entre aspas) — comum em objetos de config.
// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
const settings = { "api_key": "{{rand:32}}" };

// ───── Não devem ser detectados ─────

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const apiKeyFromEnv = process.env.API_KEY;

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const opts = { apiKey: process.env.OPENAI_API_KEY ?? "" };

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const opts2 = { apiKey: `${process.env.API_KEY}` };

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const api_key = "your-api-key-here-0000000000";

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const secretKey = "REPLACE_WITH_REAL_SECRET";

// Valor curto demais para ser credencial.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const accessToken = "abc123";

// Nome do header / da variável, não o valor.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const AUTH_HEADER = { access_token: "Authorization" };

// Texto de UI com espaços não é segredo.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const labels = { apiKey: "Informe a chave de API do parceiro" };

// Lido de um secret manager.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const signingSecret = configService.get("SIGNING_SECRET");

// Comparação/uso, não atribuição de literal.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
if (req.headers["x-api-key"] !== apiKeyFromEnv) throw new Error("unauthorized");

// Valor é o NOME da env var / header (MAIÚSCULO, sem dígitos), não a chave .
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const PARTNER_API_KEY = "PARTNER_INTEGRATION_KEY";

// Placeholder em PT-BR.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const
const APP_SECRET = "qualquer-string-secreta";

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
const cfg = { apiKey: "sua-chave-de-api-aqui" };
