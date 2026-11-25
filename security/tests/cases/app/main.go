package main

import "os"

// ruleid: devsecops.security.hardcoded-api-key, generic-api-key-assignment, generic-high-entropy-secret
var apiKey = "{{rand:32}}"

// ok: devsecops.security.hardcoded-api-key, generic-api-key-assignment
var apiKeyEnv = os.Getenv("API_KEY")

func main() {}
