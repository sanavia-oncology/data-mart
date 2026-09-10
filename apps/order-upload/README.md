# Order Upload

## Setup

Needs Python 3.11+ and R already installed. Run every command below in order:

```bash
# 1. Get the repo
git clone https://github.com/sanavia-oncology/data-mart.git
cd data-mart/apps/order-upload

# 2. R packages
R -e 'install.packages(c("shiny","bslib","DT","jsonlite","processx"), repos="https://cloud.r-project.org")'

# 3. Set App Credentials
cp .env.example ~/.env_benchling
open -e ~/.env_benchling         # set BENCHLING_TEST_TENANT_URL + BENCHLING_TEST_API_KEY
ln -sf ~/.env_benchling .env

# 4. Python env
python3 -m venv benchling-python-env
./benchling-python-env/bin/pip install -r requirements.txt

# 5. Start it
./scripts/run.sh 5041   # → http://127.0.0.1:5041
```

Orders-root configuration is internal — ask the team.

Steps 3 and 4 are what `scripts/launchers/02_update.command` runs after it reclones.

## Push from the command line

```bash
./scripts/genscript_upload_order.sh --csv examples/<merged_order>.csv --env test --location loc_xxxxxxxxxxxx
```

`--help` for the full options.

## Background S3 sync

Needs AWS CLI v2 (`brew install awscli`). A developer with SSO mints one key
per Mac:

```bash
./scripts/aws/provision_laptop.sh --host SAN-LT-04 --owner "Brendan Buehler" --user brendan.buehler   # -> ~/.order-upload/minted/san-lt-04/aws-creds
./scripts/aws/provision_laptop.sh                    # this Mac: writes ~/.order-upload/aws-creds
```

Send the file privately (AirDrop, or the Passwords app's shared groups). On
the scientist's Mac, save it next to the start launcher and double-click:

```
scripts/gs_orders_sync_start.command    start; comes back at every login
scripts/gs_orders_sync_stop.command     stop
```

Both run from anywhere. Start moves `aws-creds` into `~/.order-upload/`, reads
`GS_ORDERS_DIR` from `~/.env_data_mart_order_upload`, and takes the bucket from
the key file. Log: `~/Library/Logs/order-upload/gs_orders_sync.log`. `--dev`
mints against the dev bucket. Policy: `scripts/aws/common.sh`, published with
`scripts/aws/publish_policy.sh`. Revoke commands print when a key is minted.
Deletes in the prod bucket are refused for everyone by
`scripts/aws/bucket-no-delete-policy.json`; edit that policy first to delete.

## More

- [`docs/commands.md`](docs/commands.md) — manual push, undoing a failed run
- [`docs/genscript_uploader.html`](docs/genscript_uploader.html) — code walkthrough
