// Diretório com "e2e" no nome (users-e2e/) é tratado como teste pelas duas
// ferramentas: credenciais de usuários de e2e não bloqueiam.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const r = await call(adminToken, "POST", "/users", { password: "{{lower:8}}", fullName: "Fulano E2E" });
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const body = { password: fixtures.password };
