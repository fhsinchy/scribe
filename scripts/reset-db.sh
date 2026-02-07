#!/bin/sh
set -eu

echo "Stopping app..."
docker compose stop app

echo "Resetting database..."
docker compose exec db psql -U postgres -c "DROP DATABASE IF EXISTS social_scribe;"
docker compose exec db psql -U postgres -c "CREATE DATABASE social_scribe;"

echo "Starting app..."
docker compose start app

echo "Waiting for app to start..."
sleep 5

echo "Running migrations..."
docker compose exec app /app/bin/migrate

echo "Done! Database has been reset and migrated."
