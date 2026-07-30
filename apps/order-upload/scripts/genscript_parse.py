"""Parse a GenScript order CSV and build every Benchling payload — no network.
Companion to genscript_upload.py, which pushes what this module constructs.
"""

import re
import sys
from pathlib import Path

import pandas as pd

from benchling_sdk.helpers.serialization_helpers import fields as bench_fields
from benchling_sdk.models import (
    AaSequenceBulkCreate,
    BoxCreate,
    ContainerCreate,
    ContainerQuantity,
    ContainerQuantityUnits,
    CustomEntityBulkCreate,
    Measurement,
    MultipleContainersTransfer,
    NamingStrategy,
)

from benchling_io import log

# sanaviatest schema IDs. Add a prod block once the schemas exist there.
SCHEMAS = {
    "lot":       "ts_Ujb6ziH3Im",
    "sequence":  "ts_kLIAY8MT8d",
    "container": "consch_bSrmOjEq",
}

# Box schema per GenScript "Box Type"; an unknown type is rejected in validate_tubes.
BOX_SCHEMAS = {
    "9x9": "boxsch_rWBXv6rL",
    "2x5": "boxsch_vFkhVowRki",
}

# "Box 23/23" is mislabeled 2x5 in the source but is really a 9x9 (holds 26 tubes).
BOX_TYPE_OVERRIDES = {
    "Box 23/23": "9x9",
}

# Lowercase is deliberate — must match the tenant's "Reagent Supplier" dropdown option.
SUPPLIER = "Genscript"
CONTAINER_TYPE = "Eppendorf"

# The four column-parallel per-tube columns, exploded on ` | `.
PER_TUBE_COLUMNS = ["Box Name", "Box Type", "Position", "Volume(ml)"]


def to_float(v) -> float | None:
    if v is None or (isinstance(v, float) and pd.isna(v)) or v == "":
        return None
    return float(v)


def empty_to_none(v):
    return v if v not in (None, "") else None


def split_pipe(s) -> list[str]:
    s = (s or "").strip()
    return [part.strip() for part in s.split("|")] if s else []


def normalize_pos(p: str) -> str:
    """Lowercase + rewrite j->i (GenScript's 9x9 labels row 9 "J", skipping "I")."""
    return p.strip().lower().replace("j", "i")


# GenScript row letters skip "I".
_ROW_LETTERS = [c for c in "ABCDEFGHJKLMNOPQRSTUVWXYZ" if c != "I"]


def grid_positions(box_type: str) -> set[str] | None:
    """Valid normalized positions for an "RxC" box type, else None."""
    m = re.fullmatch(r"(\d+)x(\d+)", box_type)
    if not m:
        return None
    rows, cols = int(m.group(1)), int(m.group(2))
    return {normalize_pos(f"{L}{c}")
            for L in _ROW_LETTERS[:rows] for c in range(1, cols + 1)}


# CSV column -> Benchling Lot field, transform, required. Required cols (identity + QC)
# must be present; the rest are optional. Derived/constant/Sequence fields: lot_fields_for.
LOT_FIELDS: list[tuple[str, str, callable, bool]] = [
    ("Name",                          "Protein Name",                    empty_to_none, True),
    ("Order ID",                      "Order number",                    empty_to_none, True),
    ("Lot No",                        "Lot number",                      empty_to_none, True),
    ("Merge Date",                    "Date received",                   empty_to_none, True),
    ("Type",                          "Type",                            empty_to_none, True),
    ("Ship Temp (Deg. Cels.)",        "Ship Temp (Deg. Cels.)",          to_float,      True),
    ("Cal. M.W.(KDa)",                "Cal. M.W.(KDa)",                  to_float,      True),
    ("Theoretical pI",                "Theoretical pI",                  to_float,      True),
    ("Extinction Coefficients",       "Extinction Coefficients",         to_float,      True),
    ("Purification",                  "Purification",                    empty_to_none, True),
    ("Buffer",                        "Buffer",                          empty_to_none, True),
    ("Concentration(mg/ml)",          "Concentration (mg/mL)",           to_float,      True),
    ("Purity by SEC-HPLC(%)",         "Purity % >= (SEC-HPLC)",          to_float,      True),
    ("Purity by CE-SDS under NR(%)",  "Purity % >= (SDS-PAGE under NR)", to_float,      True),
    ("Endotoxin Level(EU/mg)",        "Endotoxin level (EU/mg)",         to_float,      True),
    ("Total(mg)",                     "Total amount (mg)",               to_float,      True),
    ("Size-Volume(ml)",               "Size volume (mL)",                empty_to_none, False),
    ("Unit(Tube)",                    "Units (tubes)",                   empty_to_none, False),
    ("no_of_seqs",                    "Number of sequences",             to_float,      False),
    ("no_expected_seqs",              "Number of expected sequences",    to_float,      False),
    ("assembly_id",                   "Assembly ID",                     empty_to_none, False),
    ("assembly_type",                 "Assembly type",                   empty_to_none, False),
    ("assembly_type_alias",           "Assembly type alias",             empty_to_none, False),
    ("target1",                       "Target1",                         empty_to_none, False),
    ("target1_alias",                 "Target1 alias",                   empty_to_none, False),
    ("target1_antigen",               "Target1 antigen",                 empty_to_none, False),
    ("target2",                       "Target2",                         empty_to_none, False),
    ("target2_alias",                 "Target2 alias",                   empty_to_none, False),
    ("target2_antigen",               "Target2 antigen",                 empty_to_none, False),
]

LOT_CONSTANT_FIELDS = {"Supplier": SUPPLIER}

# Required fields above + structural columns (tubes, first two sequences).
REQUIRED_CSV_COLUMNS = (
    [csv for csv, _, _, req in LOT_FIELDS if req]
    + PER_TUBE_COLUMNS + ["sequence 1", "sequence 2"]
)

# Read as strings (ids, delimited values); numeric columns go through to_float.
_TEXT_COLS = tuple(
    [csv for csv, _, t, _ in LOT_FIELDS if t is empty_to_none]
    + PER_TUBE_COLUMNS
    + ["sequence 1", "sequence 2", "sequence 3", "sequence 4"]
)


def seq_name_for(row, n: int) -> str:
    return f"{row['Name']}_seq{n}"


def box_key(tube: dict) -> tuple:
    """(box, type, merge) — identifies and dedups a box."""
    return (tube["box"], tube["btype"], tube["merge"])


def box_full_name(tube: dict, order_id_prefix: str) -> str:
    return f"{order_id_prefix} {tube['box']}_{tube['btype']}_{tube['merge']}"


def lot_fields_for(row, seq_ids: list, tubes: list[dict]) -> dict:
    """LOT_FIELDS (present columns) + Supplier + derived count/volume + seq links.
    Box/position live on the containers, not the lot."""
    out = {b: tx(row[csv]) for csv, b, tx, _ in LOT_FIELDS if csv in row.index}
    out.update(LOT_CONSTANT_FIELDS)
    out["Number of units"] = float(len(tubes))
    out["Volume (mL)"] = round(
        sum(float(t["vol"]) for t in tubes if t["vol"] not in (None, "")), 4)
    for i, sid in enumerate(seq_ids, start=1):
        out[f"Sequence{i}"] = sid  # None dropped by make_fields()
    return out


def read_csv(path: Path) -> pd.DataFrame:
    df_head = pd.read_csv(path, nrows=0)
    text_cols = [c for c in _TEXT_COLS if c in df_head.columns]  # present text cols -> str
    df = pd.read_csv(path, dtype={c: str for c in text_cols})
    missing = [c for c in REQUIRED_CSV_COLUMNS if c not in df.columns]
    if missing:
        sys.exit(f"[LOCAL_PARSE] ERROR: CSV missing required columns: {missing}")
    for col in text_cols:
        df[col] = df[col].fillna("").astype(str).str.strip()
    return df.reset_index(drop=True)


def make_fields(d: dict):
    return bench_fields({k: {"value": v} for k, v in d.items() if v is not None})


def build_tubes(df: pd.DataFrame) -> list[list[dict]]:
    """Per row, explode the ` | `-delimited per-tube columns into {box, btype, pos,
    vol, merge} dicts. Applies BOX_TYPE_OVERRIDES; exits on ragged rows."""
    out: list[list[dict]] = []
    overridden = 0
    for i, row in df.iterrows():
        boxes = split_pipe(row["Box Name"])
        types = split_pipe(row["Box Type"])
        poss  = split_pipe(row["Position"])
        vols  = split_pipe(row["Volume(ml)"])
        lens = {len(boxes), len(types), len(poss), len(vols)}
        if len(lens) != 1:
            sys.exit(f"[LOCAL_PARSE] ERROR: row {i} (Lot {row['Lot No']!r}): per-tube columns "
                     f"have unequal lengths — Box Name={len(boxes)}, Box Type={len(types)}, "
                     f"Position={len(poss)}, Volume(ml)={len(vols)}")
        if not boxes:
            sys.exit(f"[LOCAL_PARSE] ERROR: row {i} (Lot {row['Lot No']!r}) has no tube/box data")
        tubes = []
        for k in range(len(boxes)):
            btype = BOX_TYPE_OVERRIDES.get(boxes[k], types[k])
            if btype != types[k]:
                overridden += 1
            tubes.append({
                "box":   boxes[k],
                "btype": btype,
                "pos":   normalize_pos(poss[k]),
                "vol":   vols[k],
                "merge": row["Merge Date"],
            })
        out.append(tubes)
    if overridden:
        log("LOCAL_PARSE", f"applied {overridden} box-type override(s) {BOX_TYPE_OVERRIDES} "
            f"to fix mislabeled source box(es)")
    return out


def flatten(tubes_by_row: list[list[dict]]) -> list[tuple[int, dict]]:
    """Flatten to (row_index, tube) pairs in row-major order."""
    return [(i, t) for i, tubes in enumerate(tubes_by_row) for t in tubes]


def validate_tubes(tubes_by_row: list[list[dict]]) -> None:
    """Fail fast, before any Benchling write, on structural problems."""
    flat = [t for _, t in flatten(tubes_by_row)]
    problems: list[str] = []

    # every box type resolves to a schema
    unknown = sorted({t["btype"] for t in flat} - BOX_SCHEMAS.keys())
    if unknown:
        problems.append(f"box type(s) with no schema in BOX_SCHEMAS: {unknown} "
                        f"(known: {sorted(BOX_SCHEMAS)})")

    # each box name maps to a single type
    type_by_box: dict[str, set] = {}
    for t in flat:
        type_by_box.setdefault(t["box"], set()).add(t["btype"])
    mixed = {b: sorted(s) for b, s in type_by_box.items() if len(s) > 1}
    if mixed:
        problems.append(f"box(es) mapped to >1 type: {mixed}")

    # each position is valid for its box's grid
    bad_pos: dict[tuple, set] = {}
    for t in flat:
        grid = grid_positions(t["btype"])
        if grid is not None and t["pos"] not in grid:
            bad_pos.setdefault((t["box"], t["btype"]), set()).add(t["pos"])
    if bad_pos:
        problems.append("position(s) outside the box grid: " + "; ".join(
            f"{b} ({bt}): {sorted(p)}" for (b, bt), p in bad_pos.items()))

    # no two tubes claim the same (box, type, merge, position)
    seen: dict[tuple, int] = {}
    for t in flat:
        seen[box_key(t) + (t["pos"],)] = seen.get(box_key(t) + (t["pos"],), 0) + 1
    collisions = [k for k, n in seen.items() if n > 1]
    if collisions:
        problems.append(f"{len(collisions)} box position(s) claimed by >1 tube, "
                        f"e.g. {collisions[:5]}")

    if problems:
        sys.exit("[LOCAL_PARSE] ERROR: tube validation failed:\n  - " + "\n  - ".join(problems))


def build_sequence_payloads(df: pd.DataFrame, registry_id: str) -> tuple[list, list[int]]:
    """(flat payloads in row-major order, per-row seq counts). Each row yields 2..4
    payloads; a missing/empty `sequence N` column ends the row."""
    payloads: list = []
    counts: list[int] = []
    for _, row in df.iterrows():
        row_count = 0
        for n in (1, 2, 3, 4):
            col = f"sequence {n}"
            if col not in row.index:
                break
            aa = (row[col] or "").strip()
            if not aa:
                break
            name = seq_name_for(row, n)
            payloads.append(AaSequenceBulkCreate(
                name=name,
                amino_acids=aa,
                registry_id=registry_id,
                schema_id=SCHEMAS["sequence"],
                naming_strategy=NamingStrategy.NEW_IDS,
                fields=make_fields({
                    "Order ID":        row["Order ID"],
                    "Sequence Number": n,
                    "Name":            name,
                }),
            ))
            row_count += 1
        counts.append(row_count)
    return payloads, counts


def seq_offsets(counts: list[int]) -> list[int]:
    """offsets[i+1] - offsets[i] = number of seqs for row i."""
    offsets = [0]
    for c in counts:
        offsets.append(offsets[-1] + c)
    return offsets


def row_seq_ids(sequence_ids: list[str], offsets: list[int], i: int) -> list:
    """Row i's seq ids, right-padded to 4 with None."""
    ids = list(sequence_ids[offsets[i] : offsets[i + 1]])
    while len(ids) < 4:
        ids.append(None)
    return ids


def build_lot_payloads(df: pd.DataFrame, registry_id: str, sequence_ids: list[str],
                       offsets: list[int], tubes_by_row: list[list[dict]]) -> list:
    return [
        CustomEntityBulkCreate(
            name=row["Lot No"],
            registry_id=registry_id,
            schema_id=SCHEMAS["lot"],
            naming_strategy=NamingStrategy.NEW_IDS,
            fields=make_fields(lot_fields_for(
                row, row_seq_ids(sequence_ids, offsets, i), tubes_by_row[i])),
        )
        for i, row in df.iterrows()
    ]


def build_box_payloads(tubes_by_row: list[list[dict]], order_id_prefix: str,
                       location_id: str) -> list:
    """One (box_key, BoxCreate) per unique box, first-seen order. Name/schema/location
    are baked in here so the push side needs no schema knowledge."""
    seen: set = set()
    out: list = []
    for _, tube in flatten(tubes_by_row):
        key = box_key(tube)
        if key in seen:
            continue
        seen.add(key)
        out.append((key, BoxCreate(
            name=box_full_name(tube, order_id_prefix),
            schema_id=BOX_SCHEMAS[tube["btype"]],
            parent_storage_id=location_id,
        )))
    return out


def build_container_payloads(flat: list[tuple[int, dict]], df: pd.DataFrame,
                             box_id_by_key: dict, container_type_id: str) -> list:
    return [
        ContainerCreate(
            name=df.iloc[i]["Lot No"],
            schema_id=SCHEMAS["container"],
            parent_storage_id=f"{box_id_by_key[box_key(t)]}:{t['pos']}",
            fields=make_fields({"LL1": "", "LL2": "", "Type": container_type_id}),
        )
        for i, t in flat
    ]


def build_transfer_requests(flat: list[tuple[int, dict]], df: pd.DataFrame,
                            lot_ids: list[str], container_ids: list[str]) -> list:
    return [
        MultipleContainersTransfer(
            destination_container_id=container_ids[j],
            source_entity_id=lot_ids[i],
            transfer_quantity=ContainerQuantity(
                units=ContainerQuantityUnits.ML,
                value=float(t["vol"]),
            ),
            source_concentration=Measurement(
                value=float(df.iloc[i]["Concentration(mg/ml)"]),
                units="mg/mL",
            ),
        )
        for j, (i, t) in enumerate(flat)
    ]
