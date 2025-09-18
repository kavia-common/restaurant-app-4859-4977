#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f db_connection.txt ]; then
  echo "db_connection.txt not found. Please run startup.sh first to setup PostgreSQL and connection info."
  exit 1
fi

if [ ! -f schema.sql ]; then
  echo "schema.sql not found."
  exit 1
fi

CONN_CMD="$(head -n1 db_connection.txt)"
if [ -z "$CONN_CMD" ]; then
  echo "Empty db_connection.txt"
  exit 1
fi

echo "Applying schema using: $CONN_CMD -f schema.sql"
# shellcheck disable=SC2086
$CONN_CMD -v ON_ERROR_STOP=1 -f schema.sql

echo "✓ Schema applied successfully."
