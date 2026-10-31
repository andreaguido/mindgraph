"""
agreement.py — Three-way annotation agreement pipeline.

Copied from benchmark_agreement.py (Climate Change Narratives project). The
metrics are unchanged; only path handling was adapted (relative paths resolve
against the current working directory; the run log is written next to the
output folder).

Compares cause-narrative edges and nodes across the model ("GPT"), H1, and H2
on a common benchmark sample. All pairs are restricted to the same set of
participants (those present in all three sources) to avoid sample-selection
bias.

Inputs: the model JSON is the output of src/dag_coder.py (a list of
{participant_code, narrative, analysis: {nodes, edges}}); human cause CSVs are
semicolon-delimited participant_code;source;target, one row per edge and an
empty source/target row for an empty DAG (the output of annotation_app/).

Usage (from the repository root):
    py -3.14 src/agreement.py \\
        --gpt-cause-json examples/turnover/agreement_demo/model.json \\
        --h1-cause examples/turnover/agreement_demo/coder_A.csv \\
        --h2-cause examples/turnover/agreement_demo/coder_B.csv \\
        --h1-label A --h2-label B --out-dir outputs/agreement_demo \\
        --taxonomy taxonomies/turnover_taxonomy_illustrative.txt
"""

import argparse
import csv
import re
import datetime
import json
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Set, Tuple

# ── Types ──────────────────────────────────────────────────────────────────────
Edge    = Tuple[str, str]
EdgeMap = Dict[str, Set[Edge]]   # participant → set of (source, target)


# ── Metrics ────────────────────────────────────────────────────────────────────
def _safe(n: float, d: float) -> float:
    return 0.0 if d == 0 else n / d


def _metrics(n11: int, n10: int, n01: int, n00: int) -> dict:
    N  = n11 + n10 + n01 + n00
    po = _safe(n11 + n00, N)
    p_a = _safe(n11 + n10, N)
    p_b = _safe(n11 + n01, N)
    pe  = p_a * p_b + (1 - p_a) * (1 - p_b)
    kap = _safe(po - pe, 1 - pe) if pe != 1 else 0.0
    ppa = _safe(2 * n11, 2 * n11 + n10 + n01)
    npa = _safe(2 * n00, 2 * n00 + n10 + n01)
    return {
        "N": N, "n11": n11, "n10": n10, "n01": n01, "n00": n00,
        "Po":    round(po,  4),
        "PABAK": round(2 * po - 1, 4),
        "kappa": round(kap, 4),
        "PPA":   round(ppa, 4),
        "NPA":   round(npa, 4),
    }


# ── Path helper ────────────────────────────────────────────────────────────────
def _resolve(path: str, root: Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else root / p


# ── Loaders ────────────────────────────────────────────────────────────────────
def load_cause_csv(path: Path) -> EdgeMap:
    """Human cause annotation CSV → {participant: set of (source, target)}."""
    edges: EdgeMap = {}
    with path.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter=";"):
            pid = (row.get("participant_code") or "").strip()
            src = (row.get("source") or "").strip()
            tgt = (row.get("target") or "").strip()
            if not pid:
                continue
            if pid not in edges:
                edges[pid] = set()
            if src and tgt:
                edges[pid].add((src, tgt))
    return edges


def load_gpt_cause_json(path: Path) -> EdgeMap:
    """GPT narrative_analyses.json → {participant: set of (source, target)}."""
    data    = json.loads(path.read_text(encoding="utf-8"))
    results = data if isinstance(data, list) else data.get("results", [])
    edges: EdgeMap = {}
    for item in results:
        pid = (item.get("participant_code") or "").strip()
        if not pid:
            continue
        edges.setdefault(pid, set())
        for e in (item.get("analysis") or {}).get("edges") or []:
            if isinstance(e, dict):
                src = str(e.get("source", "")).strip()
                tgt = str(e.get("target", "")).strip()
                if src and tgt:
                    edges[pid].add((src, tgt))
    return edges


# ── Agreement: cause ───────────────────────────────────────────────────────────
def _union_universe(ea: Set[Edge], eb: Set[Edge]) -> Set[Edge]:
    nodes: Set[str] = set()
    for s, t in ea | eb:
        nodes.add(s)
        nodes.add(t)
    return {(s, t) for s in nodes for t in nodes if s != t}


def _union_universe_3(ea: Set[Edge], eb: Set[Edge], ec: Set[Edge]) -> Set[Edge]:
    nodes: Set[str] = set()
    for s, t in ea | eb | ec:
        nodes.add(s)
        nodes.add(t)
    return {(s, t) for s in nodes for t in nodes if s != t}


def fleiss_kappa_cause(ea: EdgeMap, eb: EdgeMap, ec: EdgeMap, participants: List[str]) -> dict:
    """Fleiss' kappa for 3 binary raters on cause edges (binary: edge present/absent)."""
    k = 3
    N = 0
    P_bar_sum = 0.0
    n1_total = 0

    for pid in participants:
        sa = ea.get(pid, set())
        sb = eb.get(pid, set())
        sc = ec.get(pid, set())
        for edge in _union_universe_3(sa, sb, sc):
            n1 = int(edge in sa) + int(edge in sb) + int(edge in sc)
            n0 = k - n1
            P_bar_sum += (n1 * (n1 - 1) + n0 * (n0 - 1)) / (k * (k - 1))
            n1_total += n1
            N += 1

    if N == 0:
        return {"n_raters": k, "n_participants": len(participants),
                "N_items": 0, "P_bar": 0.0, "P_e_bar": 0.0, "fleiss_kappa": 0.0}

    P_bar  = P_bar_sum / N
    p1     = n1_total / (N * k)
    P_e    = p1 ** 2 + (1 - p1) ** 2
    kappa  = _safe(P_bar - P_e, 1 - P_e) if P_e != 1 else 0.0

    return {
        "n_raters":      k,
        "n_participants": len(participants),
        "N_items":       N,
        "P_bar":         round(P_bar, 4),
        "P_e_bar":       round(P_e,   4),
        "fleiss_kappa":  round(kappa,  4),
    }


def cause_pair(ea: EdgeMap, eb: EdgeMap, participants: List[str]) -> Tuple[dict, List[dict]]:
    totals = dict(n11=0, n10=0, n01=0, n00=0)
    by_resp: List[dict] = []
    for pid in participants:
        sa = ea.get(pid, set())
        sb = eb.get(pid, set())
        universe = _union_universe(sa, sb)
        n11 = n10 = n01 = n00 = 0
        for edge in universe:
            in_a, in_b = edge in sa, edge in sb
            if in_a and in_b:   n11 += 1
            elif in_a:          n10 += 1
            elif in_b:          n01 += 1
            else:               n00 += 1
        for k in ("n11", "n10", "n01", "n00"):
            totals[k] += locals()[k]
        by_resp.append({"participant_code": pid, **_metrics(n11, n10, n01, n00)})
    return _metrics(**totals), by_resp


def cause_disputes(ea: EdgeMap, eb: EdgeMap, participants: List[str], top_n: int = 30) -> List[dict]:
    counter: Dict[Edge, dict] = defaultdict(lambda: {"present": 0, "disagree": 0})
    for pid in participants:
        sa = ea.get(pid, set())
        sb = eb.get(pid, set())
        for edge in _union_universe(sa, sb):
            counter[edge]["present"] += 1
            if (edge in sa) ^ (edge in sb):
                counter[edge]["disagree"] += 1
    rows = [
        {"source": e[0], "target": e[1],
         "n_seen": c["present"], "n_disagree": c["disagree"],
         "disagree_rate": round(_safe(c["disagree"], c["present"]), 4)}
        for e, c in counter.items()
    ]
    return sorted(rows, key=lambda r: (-r["disagree_rate"], -r["n_disagree"]))[:top_n]


# ── Agreement: cause nodes ─────────────────────────────────────────────────────
CAUSE_NODE_UNIVERSE: Set[str] = {str(i) for i in range(1, 23)} | {"24", "25", "26"}


def _nodes(edges: Set[Edge]) -> Set[str]:
    return {n for e in edges for n in e}


def node_pair(ea: EdgeMap, eb: EdgeMap, participants: List[str]) -> Tuple[dict, List[dict]]:
    """Agreement on which causal factors are mentioned, fixed 25-factor universe."""
    totals = dict(n11=0, n10=0, n01=0, n00=0)
    by_resp: List[dict] = []
    for pid in participants:
        na = _nodes(ea.get(pid, set()))
        nb = _nodes(eb.get(pid, set()))
        n11 = n10 = n01 = n00 = 0
        for node in CAUSE_NODE_UNIVERSE:
            in_a, in_b = node in na, node in nb
            if in_a and in_b:   n11 += 1
            elif in_a:          n10 += 1
            elif in_b:          n01 += 1
            else:               n00 += 1
        for k in ("n11", "n10", "n01", "n00"):
            totals[k] += locals()[k]
        by_resp.append({"participant_code": pid, **_metrics(n11, n10, n01, n00)})
    return _metrics(**totals), by_resp


def fleiss_kappa_node(ea: EdgeMap, eb: EdgeMap, ec: EdgeMap, participants: List[str]) -> dict:
    """Fleiss' kappa for 3 binary raters on node presence, fixed 25-factor universe."""
    k = 3
    N = 0
    P_bar_sum = 0.0
    n1_total = 0

    for pid in participants:
        na = _nodes(ea.get(pid, set()))
        nb = _nodes(eb.get(pid, set()))
        nc = _nodes(ec.get(pid, set()))
        for node in CAUSE_NODE_UNIVERSE:
            n1 = int(node in na) + int(node in nb) + int(node in nc)
            n0 = k - n1
            P_bar_sum += (n1 * (n1 - 1) + n0 * (n0 - 1)) / (k * (k - 1))
            n1_total += n1
            N += 1

    if N == 0:
        return {"n_raters": k, "n_participants": len(participants),
                "N_items": 0, "P_bar": 0.0, "P_e_bar": 0.0, "fleiss_kappa": 0.0}

    P_bar = P_bar_sum / N
    p1    = n1_total / (N * k)
    P_e   = p1 ** 2 + (1 - p1) ** 2
    kappa = _safe(P_bar - P_e, 1 - P_e) if P_e != 1 else 0.0

    return {
        "n_raters":       k,
        "n_participants": len(participants),
        "N_items":        N,
        "P_bar":          round(P_bar, 4),
        "P_e_bar":        round(P_e,   4),
        "fleiss_kappa":   round(kappa,  4),
    }


# ── Output ─────────────────────────────────────────────────────────────────────
def _write(path: Path, rows: List[dict], fields: List[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields, delimiter=";", extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)


def _append_log(log_path: Path, script: str, inputs: dict, output_path: str, n_items: int) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().isoformat(timespec="seconds")
    inputs_md = "\n".join(f"  - **{k}**: {v}" for k, v in inputs.items())
    entry = f"\n## {ts} — {script}\n\n- **Inputs**:\n{inputs_md}\n- **Output**: {output_path}\n- **Items**: {n_items}\n"
    with log_path.open("a", encoding="utf-8") as f:
        f.write(entry)


METRIC_FIELDS = ["N", "n11", "n10", "n01", "n00", "Po", "PABAK", "kappa", "PPA", "NPA"]


def _print_table(title: str, rows: List[dict], cols: List[Tuple[str, int]]) -> None:
    print(f"\n{'=' * 70}")
    print(f"  {title}")
    print(f"{'=' * 70}")
    header = "  ".join(f"{label:<{w}}" for label, w in cols)
    print(header)
    print("-" * 70)
    for row in rows:
        line = "  ".join(f"{str(row.get(label, '')):<{w}}" for label, w in cols)
        print(line)


# ── Main ───────────────────────────────────────────────────────────────────────
def main() -> None:
    today = datetime.date.today().strftime("%Y-%m-%d")
    parser = argparse.ArgumentParser(
        description="Three-way annotation agreement on cause DAGs: GPT vs H1 vs H2."
    )
    root = Path.cwd()

    parser.add_argument("--gpt-cause-json",  required=True,  help="Model output JSON (src/dag_coder.py)")
    parser.add_argument("--h1-cause",         required=True,  help="H1 cause edges CSV")
    parser.add_argument("--h2-cause",         required=True,  help="H2 cause edges CSV")
    parser.add_argument("--h1-label",         default="H1",   help="Label for H1 (default: H1)")
    parser.add_argument("--h2-label",         default="H2",   help="Label for H2 (default: H2)")
    parser.add_argument("--out-dir",          default="outputs/agreement")
    parser.add_argument("--taxonomy",         default=None,
                        help="Taxonomy .txt; node universe = its factor IDs (#N). Default: the 25 climate factors")
    args = parser.parse_args()

    if args.taxonomy:
        global CAUSE_NODE_UNIVERSE
        ids = re.findall(r"^#(\d+)\b", _resolve(args.taxonomy, root).read_text(encoding="utf-8"), flags=re.M)
        if not ids:
            parser.error(f"No factor IDs (#N) found in {args.taxonomy}")
        CAUSE_NODE_UNIVERSE = set(ids)
        print(f"Node universe: {len(ids)} factors from {args.taxonomy}")

    h1, h2  = args.h1_label, args.h2_label
    out_dir = _resolve(args.out_dir, root) / today

    # ── Cause ──────────────────────────────────────────────────────────────────
    print("Loading cause annotations…")
    gpt_cause = load_gpt_cause_json(_resolve(args.gpt_cause_json, root))
    h1_cause  = load_cause_csv(_resolve(args.h1_cause, root))
    h2_cause  = load_cause_csv(_resolve(args.h2_cause, root))

    cause_3way = sorted(set(gpt_cause) & set(h1_cause) & set(h2_cause))
    cause_hh   = sorted(set(h1_cause)  & set(h2_cause))

    excl = len(set(h1_cause) | set(h2_cause)) - len(cause_hh)
    print(f"  GPT: {len(gpt_cause)} | {h1}: {len(h1_cause)} | {h2}: {len(h2_cause)}")
    print(f"  Common (3-way): {len(cause_3way)}  |  Human-human: {len(cause_hh)}"
          + (f"  |  {excl} excluded (not in both humans)" if excl else ""))

    cause_pairs = [
        (f"GPT vs {h1}", gpt_cause, h1_cause, cause_3way),
        (f"GPT vs {h2}", gpt_cause, h2_cause, cause_3way),
        (f"{h1} vs {h2}", h1_cause, h2_cause, cause_hh),
    ]

    cause_summary_rows: List[dict] = []
    cause_by_response_rows: List[dict] = []

    for label, ea, eb, pids in cause_pairs:
        edge_summary, edge_by_resp = cause_pair(ea, eb, pids)
        node_summary, node_by_resp = node_pair(ea, eb, pids)
        cause_summary_rows.append({"level": "edge", "pair": label, "n_participants": len(pids), **edge_summary})
        cause_summary_rows.append({"level": "node", "pair": label, "n_participants": len(pids), **node_summary})
        for row in edge_by_resp:
            cause_by_response_rows.append({"level": "edge", "pair": label, **row})
        for row in node_by_resp:
            cause_by_response_rows.append({"level": "node", "pair": label, **row})

    dispute_rows = cause_disputes(h1_cause, h2_cause, cause_hh)

    fleiss_edge = {**fleiss_kappa_cause(gpt_cause, h1_cause, h2_cause, cause_3way), "level": "edge"}
    fleiss_node = {**fleiss_kappa_node(gpt_cause, h1_cause, h2_cause, cause_3way), "level": "node"}

    _write(out_dir / "cause_agreement.csv",
           cause_summary_rows,
           ["level", "pair", "n_participants"] + METRIC_FIELDS)
    _write(out_dir / "cause_by_response.csv",
           cause_by_response_rows,
           ["level", "pair", "participant_code"] + METRIC_FIELDS)
    _write(out_dir / "cause_top_disputes.csv",
           dispute_rows,
           ["source", "target", "n_seen", "n_disagree", "disagree_rate"])
    _write(out_dir / "cause_fleiss.csv",
           [fleiss_edge, fleiss_node],
           ["level", "n_raters", "n_participants", "N_items", "P_bar", "P_e_bar", "fleiss_kappa"])

    # ── Console summary ────────────────────────────────────────────────────────
    for level in ("edge", "node"):
        _print_table(
            f"CAUSE AGREEMENT — {level.upper()}",
            [{"Pair": r["pair"], "N": r["n_participants"],
              "Po": r["Po"], "kappa": r["kappa"], "PPA": r["PPA"], "NPA": r["NPA"]}
             for r in cause_summary_rows if r["level"] == level],
            [("Pair", 20), ("N", 4), ("Po", 6), ("kappa", 6), ("PPA", 6), ("NPA", 6)],
        )
    fk_edge, fk_node = fleiss_edge["fleiss_kappa"], fleiss_node["fleiss_kappa"]
    print(f"\n  Fleiss' kappa (3-way, GPT+{h1}+{h2}):")
    print(f"    edge: {fk_edge}  [{fleiss_edge['N_items']} binary items]")
    print(f"    node: {fk_node}  [{fleiss_node['N_items']} binary items]")

    print(f"\nOutputs written to: {out_dir}")

    log_inputs = {
        "gpt_cause_json": args.gpt_cause_json,
        f"{h1}_cause":    args.h1_cause,
        f"{h2}_cause":    args.h2_cause,
    }
    _append_log(
        out_dir.parent / "run_log.md",
        script="benchmark_agreement",
        inputs=log_inputs,
        output_path=str(out_dir),
        n_items=len(cause_3way),
    )
    print(f"  cause_agreement.csv      ({len(cause_pairs)} pairs × 2 levels = {len(cause_summary_rows)} rows)")
    print(f"  cause_by_response.csv    ({len(cause_by_response_rows)} rows)")
    print(f"  cause_top_disputes.csv   (top {len(dispute_rows)} contested edges, {h1} vs {h2})")
    print(f"  cause_fleiss.csv         (edge={fk_edge}, node={fk_node})")


if __name__ == "__main__":
    main()
