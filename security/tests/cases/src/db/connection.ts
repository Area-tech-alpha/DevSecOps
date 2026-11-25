// Casos: connection strings.
// Regras: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string (Semgrep)
//         connection-string-with-credentials (Gitleaks)

// ───── Devem ser detectados ─────

// ruleid: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const DATABASE_URL = "postgresql://app_user:{{rand:16}}@db.prod.internal:5432/app";

// ruleid: devsecops.security.connection-string-by-uri, connection-string-with-credentials
const client = new MongoClient("mongodb+srv://svc:{{rand:18}}@cluster0.ab1cd.mongodb.net/prod");

// ruleid: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const redis_url = "rediss://default:{{rand:24}}@cache.prod.internal:6380";

// ruleid: devsecops.security.connection-string-by-uri, connection-string-with-credentials
const amqp = connect("amqps://worker:{{rand:20}}@mq.prod.internal/vhost");

// ───── Não devem ser detectados ─────

// Ambiente local / docker.
// ok: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const local = { database_url: "postgresql://postgres:postgres@localhost:5432/dev" };

// ok: devsecops.security.connection-string-by-uri, connection-string-with-credentials
const dockerDb = "postgres://app:app@host.docker.internal:5432/app";

// Montada com variáveis de ambiente (template literal).
// ok: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const db_url = `postgresql://${process.env.DB_USER}:${process.env.DB_PASS}@${process.env.DB_HOST}:5432/app`;

// ok: devsecops.security.connection-string-by-uri, connection-string-with-credentials
const uri = `mongodb://${user}:${encodeURIComponent(pass)}@${host}/db`;

// URL sem credenciais não é segredo.
// ok: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const REDIS_URL = "redis://cache.internal:6379/0";

// URL pública do Supabase não é segredo (vai para o browser).
// ok: devsecops.security.hardcoded-connection-string
const supabase_url = "https://abcdefghijkl.supabase.co";

// Lida do ambiente.
// ok: devsecops.security.connection-string-by-uri, devsecops.security.hardcoded-connection-string, connection-string-with-credentials
const fromEnv = process.env.DATABASE_URL;

// Placeholder em docs/código.
// ok: devsecops.security.connection-string-by-uri, connection-string-with-credentials
const example = "postgresql://user:password@example.com:5432/db";
