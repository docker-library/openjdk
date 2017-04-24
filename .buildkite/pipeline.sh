#!/usr/bin/env bash
set +x

# Pull Requests
cat <<EOF
steps:
  - label: ':docker: Release images'
    command: bin/openjdk release
EOF