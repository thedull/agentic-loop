#!/usr/bin/env bash
# mkspec.sh DIR ID STATUS [PROFILE] — a minimal, valid spec file for gate tests.
mkdir -p "$1"
printf -- '---\nid: %s\ntitle: T%s\nstatus: %s\nprofile: %s\ncreated: 2026-08-11\nclaimed_by:\nbranch:\npr:\n---\n\n# Spec %s — T%s\n\n## Brief (the delegation contract)\n\n- **objective**: a fixture\n- **input_paths**: `README.md`\n\n## Acceptance\n\n1. It SHALL be a fixture.\n' "$2" "$2" "$3" "${4:-standard}" "$2" "$2" > "$1/$2-t.md"
