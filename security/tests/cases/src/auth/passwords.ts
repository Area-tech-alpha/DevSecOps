// Casos: senhas hardcoded.
// Regras: devsecops.security.hardcoded-password (Semgrep), generic-password-assignment (Gitleaks)

// ───── Devem ser detectados ─────

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const password = "{{rand:16}}";

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const user = { email: "admin@empresa.com.br", senha: "{{rand:12}}" };

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const DB_PASSWORD = '{{rand:20}}';

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const smtp = { smtp_pass: "{{rand:14}}" };

// Nome com prefixo (padrão de env var / camelCase) é o caso mais comum.
// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const ADMIN_PASSWORD = "{{rand:16}}";

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const adminPassword = "{{rand:16}}";

// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const env = { POSTGRES_PASSWORD: "{{rand:16}}" };

// Chave entre aspas (JSON-like).
// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const seed = { "password": "{{rand:16}}" };

// Mesmo com um label PT-BR na mesma linha, a senha continua detectada.
// ruleid: devsecops.security.hardcoded-password, generic-password-assignment
const form = { titulo: "Alteração de senha", password: "{{rand:16}}" };

// ───── Não devem ser detectados (FPs comuns) ─────

// Labels de auditoria / UI em PT-BR.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const acao = { tipo: "Alteração de senha" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const titulo = "Redefinição de senha do usuário";

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const placeholder = { senha: "Digite sua senha" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const i18n = { password: "Senha" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const atualizacao_senha = "2026-01-01T00:00:00Z";

// Valor vem de variável / constante, não é literal.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const body = { email: "user@local.dev", password: fixtures.password, orgId: org.id };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const dbPass = process.env.DB_PASSWORD;

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const conn = { password: `${process.env.DB_PASSWORD}` };

// Campo vazio / nome do campo.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const empty = { password: "" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const field = { name: "password", type: "password" };

// Nome composto (passwordHash, passwordResetToken) não é a senha em si.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const col = { passwordHash: "varchar(255)" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const pwd = "changeme-local-only";

// Nome de campo / rota como valor (formulários) não é senha.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const fields = { confirmPassword: "confirm_password" };

// ok: devsecops.security.hardcoded-password, generic-password-assignment
const routes = { forgotPassword: "/auth/forgot-password" };
