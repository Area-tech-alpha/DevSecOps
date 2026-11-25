import { createHash, createCipheriv, randomUUID } from "crypto";

// ruleid: devsecops.security.insecure-crypto
const h1 = createHash("md5").update(x).digest("hex");

// ruleid: devsecops.security.insecure-crypto
const h2 = createHash('sha1').update(x).digest("hex");

// ruleid: devsecops.security.insecure-crypto
const c1 = createCipheriv("des-ede3", key, iv);

// ok: devsecops.security.insecure-crypto
const h3 = createHash("sha256").update(x).digest("hex");

// ok: devsecops.security.insecure-crypto
const c2 = createCipheriv("aes-256-gcm", key, iv);

// ruleid: devsecops.security.insecure-random
const token = Math.random().toString(36).slice(2);

// ok: devsecops.security.insecure-random
const id = randomUUID();
