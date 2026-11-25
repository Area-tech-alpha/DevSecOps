// Como o dev marca um falso positivo (documentado no README):

// Semgrep: comentário nosemgrep na mesma linha. Gitleaks continua pegando.
// ok: devsecops.security.hardcoded-password
// ruleid: generic-password-assignment
const password = "{{rand:16}}"; // nosemgrep: devsecops.security.hardcoded-password

// Gitleaks: comentário gitleaks:allow na mesma linha. Semgrep continua pegando.
// ok: generic-password-assignment
// ruleid: devsecops.security.hardcoded-password
const senha = "{{rand:16}}"; // gitleaks:allow

// As duas ferramentas.
// ok: devsecops.security.hardcoded-password, generic-password-assignment
const pwd = "{{rand:16}}"; // nosemgrep gitleaks:allow
