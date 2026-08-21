#!/bin/sh
set -eu
python manage.py prepare_deploy
exec supervisord -c /app/deploy/supervisord.conf
