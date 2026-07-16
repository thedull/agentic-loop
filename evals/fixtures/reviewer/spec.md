# Spec: user lookup endpoint

Add `get_user(username)` returning the user row from the `users` table.

Acceptance (RFC-2119):
- MUST parameterize all SQL (no string interpolation of user input).
- MUST return None for a missing user, not raise.
