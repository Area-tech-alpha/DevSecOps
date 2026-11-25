// Casos: tokens detectados pelo FORMATO do valor (independe do nome da variável).
// Regras: devsecops.security.provider-specific-secret (Semgrep) + regras por provedor (Gitleaks)

// ───── Devem ser detectados ─────

// ruleid: devsecops.security.provider-specific-secret, aws-access-key
const awsId = "AKIA{{upper:16}}";

// ruleid: devsecops.security.provider-specific-secret, github-pat
const gh = "ghp_{{rand:36}}";

// ruleid: devsecops.security.provider-specific-secret, github-pat
const ghFine = "github_pat_{{rand:22}}_{{rand:59}}";

// ruleid: devsecops.security.provider-specific-secret, stripe-secret
const stripe = "sk_live_{{rand:32}}";

// ruleid: devsecops.security.provider-specific-secret, slack-token
const slack = "xoxb-{{lower:12}}-{{lower:24}}";

// O nome "twilioSid" também cai na regra por nome de variável.
// ruleid: devsecops.security.provider-specific-secret, twilio-api-key, devsecops.security.hardcoded-api-key, generic-api-key-assignment
const twilioSid = "AC{{hex:32}}";

// ruleid: devsecops.security.provider-specific-secret, sendgrid-api-key
const sg = "SG.{{rand:22}}.{{rand:43}}";

// ruleid: devsecops.security.provider-specific-secret, openai-api-key
const openai = "sk-proj-{{rand:48}}";

// ruleid: devsecops.security.provider-specific-secret, webhook-signing-secret
const whsec = "whsec_{{rand:32}}";

// ruleid: devsecops.security.provider-specific-secret, hardcoded-jwt
const jwt = "eyJ{{rand:30}}.eyJ{{rand:60}}.{{rand:43}}";

// Nome de variável inocente não esconde o token.
// ruleid: devsecops.security.provider-specific-secret, github-pat
const value = "ghp_{{rand:36}}";

// Variável com "test" no nome continua sendo um token real.
// ruleid: devsecops.security.provider-specific-secret, github-pat
const TEST_TOKEN = "ghp_{{rand:36}}";

// ───── Não devem ser detectados ─────

// Chave de exemplo oficial da documentação da AWS.
// ok: devsecops.security.provider-specific-secret, aws-access-key
const awsDocs = "AKIAIOSFODNN7EXAMPLE";

// Chaves de teste do Stripe não são credenciais de produção.
// ok: devsecops.security.provider-specific-secret, stripe-secret, openai-api-key
const stripeTest = "sk_test_{{rand:32}}";

// Hash SHA-256 em maiúsculas contendo "AC" no meio não é SID do Twilio.
// ok: devsecops.security.provider-specific-secret, twilio-api-key
const checksum = "9F{{upper:4}}AC{{hex:32}}";

// Classe CSS / identificador com "sk-" não é chave OpenAI.
// ok: devsecops.security.provider-specific-secret, openai-api-key
const cls = "task-list-item-container-wrapper";

// ok: devsecops.security.provider-specific-secret, github-pat
const placeholderToken = "ghp_your_token_here";
