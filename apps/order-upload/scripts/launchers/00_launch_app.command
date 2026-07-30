#!/usr/bin/env zsh
trap 'kill $(jobs -p) 2>/dev/null' INT TERM EXIT

source ~/.env_data_ingestion_apps

APP_DIR="$ORDER_UPLOAD_APP" R -e 'shiny::runApp(Sys.getenv("APP_DIR"), port=3005, launch.browser=FALSE)' &

wait
