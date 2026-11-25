# Diretório tests/ é ignorado pelas duas ferramentas.
# ok: devsecops.security.hardcoded-password, generic-password-assignment
password = "{{rand:16}}"
# ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
API_KEY = "{{rand:32}}"
