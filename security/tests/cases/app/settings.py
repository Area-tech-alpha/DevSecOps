import os
import hashlib

# ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
OPENAI_API_KEY = "{{rand:40}}"

# ruleid: devsecops.security.hardcoded-password, generic-password-assignment
DATABASES = {"default": {"PASSWORD": "{{rand:16}}"}}

# ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
API_KEY = os.environ["API_KEY"]

# ok: devsecops.security.hardcoded-password, generic-password-assignment
password = os.getenv("DB_PASSWORD")

# ruleid: devsecops.security.insecure-crypto
digest = hashlib.md5(data).hexdigest()

# ok: devsecops.security.insecure-crypto
digest256 = hashlib.sha256(data).hexdigest()
