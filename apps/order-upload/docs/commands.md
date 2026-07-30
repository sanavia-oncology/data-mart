# Commands reference

Every command you might need, in one place. For a normal upload you only need
the **one command** in the main [`README`](../README.md) — reach for this page
when you want the manual form, or when a run failed and you need to undo it.

All commands run against the **test tenant only**, from the app directory
(`apps/order-upload/`).

---

## Push an order (one command)

The everyday path. `scripts/genscript_upload_order.sh` fast-forwards the checkout,
activates `benchling-python-env`, upgrades dependencies, then runs the uploader
with whatever arguments you pass:

```bash
./scripts/genscript_upload_order.sh --csv examples/<merged_order>.csv --env test --location loc_xxxxxxxxxxxx
```

- `--csv` — the merged order CSV from Sanavia, **as-is** (no trim, no rename).
- `--env test` — the tenant to write to.
- `--location loc_…` — the Benchling Location id where new boxes get placed. Grab
  it from the freezer/shelf URL in the Benchling UI.

Pass `--help` to print the uploader's options. Per-phase progress prints
to the console. The Benchling tenant is the record; a finished push also stamps
the order into `logs/status-<env>.json`, the local status mirror the orders app
reads (see `genscript_status_cache.py`). Cleanup un-stamps it the same way.

---

## Push an order (manual)

Same upload, without the wrapper — use this if you've already activated the env
and just want to run the Python directly:

```bash
source benchling-python-env/bin/activate
python scripts/genscript_order_uploader.py \
    --csv examples/<merged_order>.csv \
    --env test \
    --location loc_xxxxxxxxxxxx
```

The arguments mean the same thing as above.

---

## Undo a push (cleanup)

You only need this when a push failed partway through, or you want to redo an
order from scratch. Point it at the order id — it rediscovers every entity for
that order straight from the tenant, **including any sequences orphaned by a
failed run**:

```bash
python scripts/dev-tools/cleanup_run.py --order-id U0000AAAA0 --env test
```

What it does:

- Archives **Containers** + **Boxes**.
- Renames, then archives **Lots** + **Sequences** — registry names have to be
  released before they can be reused; storage names don't.
- Pass `--yes` to skip the confirmation prompt.

---

**Want to understand what a run actually does?** Open
[`genscript_uploader.html`](genscript_uploader.html) in a browser for the code
walkthrough.
