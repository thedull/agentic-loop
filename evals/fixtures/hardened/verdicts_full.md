# Hardened review

## OWASP sweep
- injection: checked — no instance found (`scripts/x.sh:1`)
- broken-access-control: checked — no instance found (`scripts/x.sh:1`)
- cryptographic-failures: checked — no instance found (`scripts/x.sh:1`)
- ssrf: checked — no instance found (`scripts/x.sh:1`)
- insecure-deserialization: checked — no instance found (`scripts/x.sh:1`)
- security-misconfiguration: checked — no instance found (`scripts/x.sh:1`)
- vulnerable-dependencies: checked — no instance found (`scripts/x.sh:1`)
- identification-and-auth-failures: checked — no instance found (`scripts/x.sh:1`)
- software-and-data-integrity-failures: checked — no instance found (`scripts/x.sh:1`)
- logging-and-monitoring-failures: checked — no instance found (`scripts/x.sh:1`)
- prompt-injection: checked — no instance found (`scripts/x.sh:1`)
- excessive-agency: checked — no instance found (`scripts/x.sh:1`)

## Trust boundaries
- boundary: user input -> parser
  - abuse: a 2GB body exhausts memory before the length check (`scripts/x.sh:12`)
