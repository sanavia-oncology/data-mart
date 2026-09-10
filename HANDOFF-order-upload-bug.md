# Order Upload — Brendan's "no locations / Benchling unreachable" bug

## Root cause (confirmed)
The Shiny app was running while `02_update.command` did `rm -rf $REPO`.
The updater only kills port 3005; his instance survived on another port
(README documents `run.sh` default **5041**).

The surviving R process then has a deleted inode as its cwd:

  getwd()      -> NULL          (verified in R on macOS)
  app_dir      -> "/"           (config.R:53, normalizePath(paste0(getwd(), "/")))
  cfg$py       -> "//benchling-python-env/bin/python"   -> does not exist
  process$new  -> throws "cannot start processx process (system error 2)"

Symptoms all follow:
- locations dropdown silently empty  (server.R:46 swallows the error)
- "Could not start the Benchling check" (server.R:80)
- "Benchling unreachable" + Upload/dropdown hidden (sync_ok FALSE -> server.R:177, 375)
- "7 orders found" still works: orders_dir is an ABSOLUTE path from
  ~/.env_data_mart_order_upload, so it is unaffected by the broken cwd.

Ruled out: Benchling is reachable (both tenants answer HTTP 401);
genscript_locations.py runs fine and returns real locations;
his venv python exists and runs (Python 3.14.3).

## Immediate fix for Brendan
Quit the app completely and relaunch. No code change needed.

## Fixes to make
1. config.R:53 — getwd() can be NULL; app_dir silently becomes "/".
   Use a real app-dir source and fail loudly instead of composing "/".
2. 02_update.command — kills one hardcoded port (3005); shipped version has
   no 3004. run.sh default 5041 is never killed. SIGTERM only, no verify,
   no SIGKILL escalation, `sleep 1` is a guess, and `rm -rf` runs
   unconditionally even if the kill failed. 01_force_kill.command has the
   same single-port blind spot and is not actually a force kill (no -9).
3. server.R:196 — "Benchling unreachable" is shown for local launch
   failures that never touched the network. Wrong diagnosis, cost hours.
4. server.R:46 — locations launch error is swallowed; surface it.
5. server.R:462-470 — tenant switch never re-fetches locations (loc_proc is
   only ever created at line 46). After switching to prod you are shown
   TEST-tenant loc_ IDs. Real bug, independent of Brendan's machine.

## Security
Live TEST and PROD API keys were pasted in plaintext screenshots into chat.
Revoke and reissue both.

## UPDATE — reproduced locally (Aug 27)
Replica of origin/main in scratch, real venv, real creds, 7 fixture orders, launched
exactly like Brendan's launcher. Deleted-cwd theory is OUT: his PIDs (21225/21226) are
adjacent => both launched together after the 15:27 update => fresh processes.

Harness (calls the app's own py_locations_async/py_status_async, keeps the error it discards):
  baseline            -> works, 81 locations
  processx missing    -> FAIL  "there is no package called 'processx'"
  stale GENSCRIPT_PY  -> FAIL  "cannot start processx process '<path>' (system error 2)"
  R tempdir deleted   -> FAIL  same message, misleadingly names python
  cwd deleted         -> FAIL  cfg$py = //benchling-python-env/bin/python

All four give IDENTICAL screens to Brendan's: empty location box at startup; after
Refresh: "—" column, "Benchling unreachable", dropdown + Upload hidden, toast
"Could not start the Benchling check". R console prints NOTHING (error swallowed at
server.R:46 and :77).

Most likely on his machine: processx not installed. It is the only README package that
is (a) not loaded at startup and (b) not a Shiny dependency, so the app runs normally
until the first Benchling call. Fix:
  R -e 'install.packages("processx", repos="https://cloud.r-project.org")'
then quit + relaunch. If already installed -> check GENSCRIPT_PY in
~/.env_data_mart_order_upload and shell env.

Code fix when allowed: keep conditionMessage(e) at server.R:46/:77, show it, log it.
Stop saying "Benchling unreachable" for failures that never touched the network.
