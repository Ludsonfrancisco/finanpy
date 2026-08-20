#!/bin/sh
set -e

echo "=== [Finanpy] Running database migrations ==="
python manage.py migrate --noinput

echo "=== [Finanpy] Starting services ==="
exec supervisord -c /app/deploy/supervisord.conf
