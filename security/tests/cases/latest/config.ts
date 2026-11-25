// "latest/" não é diretório de teste: segredos aqui DEVEM ser detectados.
// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-secret-const, generic-high-entropy-secret
const apiKey = "{{rand:32}}";
// ruleid: devsecops.security.provider-specific-secret, github-pat
const gh = "ghp_{{rand:36}}";
