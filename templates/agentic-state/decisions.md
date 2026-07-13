# DECISIONS (append-only)

<!-- Orchestrator-only writer; ALL workers read this before acting.
One decision per line: what was decided and the one-line why.
This is what keeps parallel workers coherent — a worker that doesn't know
"we chose approach A" will confidently build for approach B. -->
