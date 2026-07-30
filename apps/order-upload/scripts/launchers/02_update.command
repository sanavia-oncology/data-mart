#!/usr/bin/env zsh
REPO_URL="https://github.com/sanavia-oncology/data-mart.git"

source ~/.env_data_ingestion_apps
APP="${ORDER_UPLOAD_APP:?ORDER_UPLOAD_APP not set}"
REPO="${APP%/apps/order-upload}"

rm -rf "$REPO"
git clone "$REPO_URL" "$REPO"

cd "$APP" || exit 1
ln -sf ~/.env_benchling .env
python3 -m venv benchling-python-env
./benchling-python-env/bin/pip install -r requirements.txt
