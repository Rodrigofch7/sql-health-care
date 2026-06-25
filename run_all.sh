#!/usr/bin/env bash
#
# run_all.sh — set up and run the entire project end to end:
#   1. start PostgreSQL
#   2. (re)create the healthcare database
#   3. load the schema and synthetic data
#   4. generate all charts via uv (deps install automatically)
#
# Usage:
#   ./run_all.sh
#
# Requirements: PostgreSQL, and uv (https://astral.sh/uv).
# Install uv with:  curl -LsSf https://astral.sh/uv/install.sh | sh

set -euo pipefail

DB="${PGDATABASE:-healthcare}"

# Resolve the repo root (the directory this script lives in) so it works
# no matter where you call it from.
cd "$(dirname "$0")"

echo "==> Checking for uv"
if ! command -v uv >/dev/null 2>&1; then
    echo "ERROR: uv is not installed."
    echo "Install it with:  curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "Then restart your shell and re-run ./run_all.sh"
    exit 1
fi

echo "==> Starting PostgreSQL"
# On WSL/Ubuntu without systemd this is the right command. Harmless if already up.
sudo service postgresql start || true

echo "==> (Re)creating database '$DB'"
dropdb --if-exists "$DB"
createdb "$DB"

echo "==> Loading schema"
psql -d "$DB" -f schema.sql

echo "==> Loading synthetic data"
psql -d "$DB" -f seed.sql

echo "==> Generating charts (uv installs Python deps automatically)"
uv run \
    --with matplotlib \
    --with pandas \
    --with psycopg2-binary \
    data_visualization/generate_charts.py

echo ""
echo "==> All done."
echo "    Database '$DB' is loaded and 7 charts are in data_visualization/."
