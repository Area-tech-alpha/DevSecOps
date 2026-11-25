// Arquivos de teste podem ter credenciais falsas: as duas ferramentas devem ignorar.
// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret
const apiKey = "{{rand:32}}";
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const password = "{{rand:16}}";
// ok: devsecops.security.provider-specific-secret, github-pat
const gh = "ghp_{{rand:36}}";
