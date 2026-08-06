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

## More

- [`docs/commands.md`](docs/commands.md) — manual push, undoing a failed run
- [`docs/genscript_uploader.html`](docs/genscript_uploader.html) — code walkthrough
