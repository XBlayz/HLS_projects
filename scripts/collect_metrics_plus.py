"""
collect_metrics.py

Collects HLS + Vivado metrics for a given project/version and writes them
to a JSON file under reports/<PROJECT_NAME>/<COMP_VERSION>/metrics.json.

Usage (from project root):
    python scripts/collect_metrics.py <PROJECT_NAME> <COMP_VERSION>

Example:
    python scripts/collect_metrics.py project01_FIR 00_baseline
"""

import argparse
import json
import re
import sys
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _read(path: Path) -> str:
    """Read a text file, returning empty string if not found."""
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def _first_match(pattern: str, text: str, group: int = 1, flags: int = 0):
    """Return the first regex capture group or None."""
    m = re.search(pattern, text, flags)
    return m.group(group).strip() if m else None


def _float(value) -> float | None:
    """Safe float conversion."""
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value) -> int | None:
    """Safe int conversion (strips whitespace)."""
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None


def _na(value) -> int | None:
    """Convert cosim cell: return None if 'NA', else int."""
    s = str(value).strip()
    return None if s == "NA" else _int(s)


def _latency_cell(s: str) -> int | None:
    """
    Convert a latency table cell that may contain '?' (variable latency)
    or '-' (not applicable) to int or None.
    """
    s = s.strip()
    return None if s in ("?", "-") else _int(s)


# ---------------------------------------------------------------------------
# Parsers
# ---------------------------------------------------------------------------

def parse_csynth(text: str) -> dict:
    """
    Extract from <COMP_NAME>_csynth.rpt:
      - clock target / estimated / uncertainty
      - latency min/max cycles  (None when variable, i.e. '?')
      - interval min/max cycles (None when variable)
      - pipeline type
      - loop detail: per-loop trip count, iteration latency, II, pipelined flag
      - utilization (LUT, FF, BRAM, DSP) used and available
    """
    data = {}

    # ---- Timing -----------------------------------------------------------
    # |ap_clk  |  10.00 ns|  6.210 ns|     2.70 ns|
    timing_row = re.search(
        r"\|\s*ap_clk\s*\|\s*([\d.]+)\s*ns\s*\|\s*([\d.]+)\s*ns\s*\|\s*([\d.]+)\s*ns\s*\|",
        text
    )
    if timing_row:
        data["clock_target_ns"]      = _float(timing_row.group(1))
        data["clock_estimated_ns"]   = _float(timing_row.group(2))
        data["clock_uncertainty_ns"] = _float(timing_row.group(3))

    # ---- Latency summary + pipeline type ----------------------------------
    # Cells may contain digits or '?' (variable latency); must not match
    # utilization table rows (which contain only digits).
    # Row format: |  67|  67| ... |  68|  68|   no|
    #         or: |   ?|   ?| ... |   ?|   ?|   no|
    CELL = r"\s*(\?|\d+)\s*"
    lat_row = re.search(
        r"^\s*\|" + CELL + r"\|" + CELL + r"\|[^|]+\|[^|]+\|"
        + CELL + r"\|" + CELL + r"\|([^|]+)\|",
        text, re.MULTILINE
    )
    if lat_row:
        data["csynth_latency_min_cycles"] = _latency_cell(lat_row.group(1))
        data["csynth_latency_max_cycles"] = _latency_cell(lat_row.group(2))
        data["interval_min_cycles"]       = _latency_cell(lat_row.group(3))
        data["interval_max_cycles"]       = _latency_cell(lat_row.group(4))
        data["pipeline_type"]             = lat_row.group(5).strip()

    # ---- Loop detail ------------------------------------------------------
    # | Loop Name|  min  |  max  | Iter Lat | II achieved | II target | Trip | Pipelined|
    # |- L1      |      ?|      ?|         ?|           -|           -|  128|        no|
    # | + L2     |      ?|      ?|         6|           -|           -|    ?|        no|
    LCELL = r"\s*(\?|-|\d+)\s*"
    loop_pat = re.compile(
        r"^\s*\|\s*[-+]?\s*(\w+)\s*\|"  # loop name (L1, L2, ...)
        + LCELL + r"\|"                 # latency min
        + LCELL + r"\|"                 # latency max
        + LCELL + r"\|"                 # iteration latency
        + LCELL + r"\|"                 # II achieved
        + LCELL + r"\|"                 # II target
        + LCELL + r"\|"                 # trip count
        + r"\s*(\w+)\s*\|",            # pipelined
        re.MULTILINE
    )
    loops = []
    for m in loop_pat.finditer(text):
        loops.append({
            "name":           m.group(1),
            "lat_min_cycles": _latency_cell(m.group(2)),
            "lat_max_cycles": _latency_cell(m.group(3)),
            "iter_lat":       _latency_cell(m.group(4)),
            "II":             _latency_cell(m.group(5)),
            "trip_count":     _latency_cell(m.group(7)),
            "pipelined":      m.group(8).strip() == "yes",
        })
    if loops:
        data["loops"] = loops

    # ---- Utilization summary ----------------------------------------------
    # Column order in csynth.rpt: BRAM_18K | DSP | FF | LUT | URAM
    for label, keys in [
        ("Total",     ("used_bram",  "used_dsp",  "used_ff",  "used_lut")),
        ("Available", ("avail_bram", "avail_dsp", "avail_ff", "avail_lut")),
    ]:
        row = re.search(
            rf"\|\s*{label}\s*\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|",
            text
        )
        if row:
            for i, key in enumerate(keys, start=1):
                val = row.group(i).strip()
                data[key] = _int(val) if re.match(r"^\d+$", val) else None

    return data


def parse_cosim(text: str) -> dict:
    """
    Extract from <COMP_NAME>_cosim.rpt (Verilog row, ignores VHDL/NA rows):
      - cosim_latency_min/avg/max cycles
      - cosim_interval_min/avg/max cycles
      - cosim_total_exec_cycles
      - cosim_status
    """
    data = {}

    # Match the Verilog data row (first non-NA row)
    # |   Verilog|      Pass|   67|   67|   67|   68|   68|   68|   2039|
    verilog_row = re.search(
        r"\|\s*Verilog\s*\|\s*(\w+)\s*\|"
        r"\s*(\w+)\s*\|\s*(\w+)\s*\|\s*(\w+)\s*\|"
        r"\s*(\w+)\s*\|\s*(\w+)\s*\|\s*(\w+)\s*\|"
        r"\s*(\w+)\s*\|",
        text
    )
    if verilog_row:
        data["cosim_status"]              = verilog_row.group(1)
        data["cosim_latency_min_cycles"]  = _na(verilog_row.group(2))
        data["cosim_latency_avg_cycles"]  = _na(verilog_row.group(3))
        data["cosim_latency_max_cycles"]  = _na(verilog_row.group(4))
        data["cosim_interval_min_cycles"] = _na(verilog_row.group(5))
        data["cosim_interval_avg_cycles"] = _na(verilog_row.group(6))
        data["cosim_interval_max_cycles"] = _na(verilog_row.group(7))
        data["cosim_total_exec_cycles"]   = _na(verilog_row.group(8))

    return data


def parse_compile_log(text: str) -> dict:
    """
    Extract Estimated Fmax from hls_compile.log.
      INFO: [HLS 200-789] **** Estimated Fmax: 161.03 MHz
    """
    data = {}
    fmax = _first_match(r"Estimated Fmax:\s*([\d.]+)\s*MHz", text)
    if fmax:
        data["fmax_mhz"] = _float(fmax)
    return data


def parse_power_report(text: str) -> dict:
    """
    Extract static and dynamic power from Vivado power report (.txt).
      | Total On-Chip Power (W)  | 0.104 |
      | Dynamic (W)              | 0.001 |
      | Device Static (W)        | 0.103 |
    """
    data = {}

    total   = _first_match(r"Total On-Chip Power \(W\)\s*\|\s*([\d.]+)", text)
    dynamic = _first_match(r"Dynamic \(W\)\s*\|\s*([\d.]+)", text)
    static  = _first_match(r"Device Static \(W\)\s*\|\s*([\d.]+)", text)

    if total:
        data["power_total_w"]   = _float(total)
    if dynamic:
        data["power_dynamic_w"] = _float(dynamic)
    if static:
        data["power_static_w"]  = _float(static)

    return data


def parse_verbose_sched(text: str) -> dict:
    """
    Extract FSM info from <COMP_NAME>.verbose.sched.rpt:
      - num_fsm_states
      - critical_path_ns: per-state worst-case delay (max across all states)
    """
    data = {}

    # * Number of FSM states : 9
    m = re.search(r"\* Number of FSM states\s*:\s*(\d+)", text)
    if m:
        data["num_fsm_states"] = _int(m.group(1))

    # State N <SV = X> <Delay = Y.YY>
    state_delays = [
        _float(d)
        for d in re.findall(r"^State\s+\d+\s*<SV\s*=\s*\d+>\s*<Delay\s*=\s*([\d.]+)>", text, re.MULTILINE)
    ]
    if state_delays:
        data["critical_path_max_ns"] = max(state_delays) # pyright: ignore[reportArgumentType]
        data["critical_path_per_state_ns"] = state_delays

    return data


# ---------------------------------------------------------------------------
# Derived metrics
# ---------------------------------------------------------------------------

def _latency_ns(cycles: int | None, clk_ns: float | None) -> float | None:
    """Convert cycles to ns, or None if either input is missing."""
    if cycles is not None and clk_ns:
        return round(cycles * clk_ns, 4)
    return None


def compute_derived(raw: dict) -> dict:
    """Compute all derived / elaborated metrics from raw parsed values."""
    derived = {}

    clk_target   = raw.get("clock_target_ns")
    clk_est      = raw.get("clock_estimated_ns")
    pipeline_type = raw.get("pipeline_type", "no")
    is_pipelined  = pipeline_type not in ("no", None, "")

    # Fmax: prefer compile-log value, fall back to 1/clk_estimated
    fmax = raw.get("fmax_mhz")
    if fmax is None and clk_est and clk_est > 0:
        fmax = round(1000.0 / clk_est, 4)
    derived["fmax_mhz"] = fmax

    # Minimum achievable clock period (ns)
    derived["min_clock_period_ns"] = round(1000.0 / fmax, 4) if fmax else None

    # Use cosim latency when available, fall back to csynth
    lat_max = (
        raw.get("cosim_latency_max_cycles")
        or raw.get("csynth_latency_max_cycles")
    )
    lat_min = (
        raw.get("cosim_latency_min_cycles")
        or raw.get("csynth_latency_min_cycles")
    )
    ii_min = raw.get("interval_min_cycles")

    # II: "-" sentinel when not pipelined
    derived["II"] = ii_min if is_pipelined else "-"

    # Latency expressed with both clock values
    derived["latency_max_at_target_ns"]    = _latency_ns(lat_max, clk_target)
    derived["latency_max_at_estimated_ns"] = _latency_ns(lat_max, clk_est)
    derived["latency_min_at_target_ns"]    = _latency_ns(lat_min, clk_target)
    derived["latency_min_at_estimated_ns"] = _latency_ns(lat_min, clk_est)

    # Total execution time (cosim total cycles × clocks)
    total_exec_cycles = raw.get("cosim_total_exec_cycles")
    derived["total_exec_at_target_ns"]    = _latency_ns(total_exec_cycles, clk_target)
    derived["total_exec_at_estimated_ns"] = _latency_ns(total_exec_cycles, clk_est)

    # Normalised area = Σ(used_i / avail_i)
    area_parts = []
    for used_key, avail_key in [
        ("used_lut",  "avail_lut"),
        ("used_ff",   "avail_ff"),
        ("used_bram", "avail_bram"),
        ("used_dsp",  "avail_dsp"),
    ]:
        used  = raw.get(used_key)
        avail = raw.get(avail_key)
        if used is not None and avail and avail > 0:
            area_parts.append(used / avail)
    area_norm = round(sum(area_parts), 6) if area_parts else None
    derived["area_total_norm"] = area_norm

    # Power
    p_total = raw.get("power_total_w")

    # Single-operation latency: II×clk (pipelined) or lat_max×clk (sequential)
    op_cycles = ii_min if is_pipelined else lat_max
    single_op_est_ns = _latency_ns(op_cycles, clk_est)

    # Energy per operation [J] — use estimated clock
    derived["energy_per_op_j"] = (
        round(p_total * single_op_est_ns * 1e-9, 12)
        if p_total is not None and single_op_est_ns is not None
        else None
    )

    # Total energy [J] — use estimated clock × total_exec_cycles
    exec_est_ns = derived.get("total_exec_at_estimated_ns")
    derived["energy_total_j"] = (
        round(p_total * exec_est_ns * 1e-9, 12)
        if p_total is not None and exec_est_ns is not None
        else None
    )

    # ADP = area_norm × total_exec_at_estimated_ns
    derived["adp"] = (
        round(area_norm * exec_est_ns, 6)
        if area_norm is not None and exec_est_ns is not None
        else None
    )

    # EDP = energy_total × total_exec_at_estimated_ns
    e_total = derived.get("energy_total_j")
    derived["edp"] = (
        e_total * exec_est_ns
        if e_total is not None and exec_est_ns is not None
        else None
    )

    # ---- Loop-level derived metrics ---------------------------------------
    loops_raw = raw.get("loops", [])
    loops_derived = []
    for lp in loops_raw:
        ld = dict(lp)  # copy raw fields
        # Iteration latency in ns (at target and estimated clock)
        ld["iter_lat_at_target_ns"]    = _latency_ns(lp.get("iter_lat"), clk_target)
        ld["iter_lat_at_estimated_ns"] = _latency_ns(lp.get("iter_lat"), clk_est)
        # Loop throughput: iterations per ns (= 1 / iter_lat_est_ns), when not None
        iter_lat_est = ld["iter_lat_at_estimated_ns"]
        ld["throughput_iter_per_ns"] = (
            round(1.0 / iter_lat_est, 6) if iter_lat_est else None
        )
        loops_derived.append(ld)
    if loops_derived:
        derived["loops"] = loops_derived

    return derived


# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

def find_comp_name(reports_dir: Path) -> str | None:
    """
    Infer <COMP_NAME> from the first *_csynth.rpt file found in hls/syn/.
    """
    syn_dir = reports_dir / "hls" / "syn"
    for f in sorted(syn_dir.glob("*_csynth.rpt")):
        name = f.stem.removesuffix("_csynth")
        if name:
            return name
    return None


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def collect(project: str, version: str, root: Path) -> dict:
    reports_dir = root / "reports" / project / version
    if not reports_dir.exists():
        print(f"[ERROR] Reports directory not found: {reports_dir}", file=sys.stderr)
        sys.exit(1)

    comp_name = find_comp_name(reports_dir)
    if comp_name is None:
        print(
            f"[ERROR] Cannot infer component name from *_csynth.rpt in "
            f"{reports_dir / 'hls' / 'syn'}",
            file=sys.stderr,
        )
        sys.exit(1)

    syn_dir   = reports_dir / "hls" / "syn"
    sim_dir   = reports_dir / "hls" / "sim"
    power_dir = reports_dir / "vivado" / "power"

    # Read source files
    csynth_text  = _read(syn_dir   / f"{comp_name}_csynth.rpt")
    cosim_text   = _read(sim_dir   / f"{comp_name}_cosim.rpt")
    compile_text = _read(syn_dir   / "hls_compile.log")
    power_text   = _read(power_dir / f"{comp_name}_post-synth_power_report.txt")
    sched_text   = _read(syn_dir   / f"{comp_name}.verbose.sched.rpt")

    if not csynth_text:
        print(
            f"[ERROR] Missing {comp_name}_csynth.rpt in {syn_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    if not cosim_text:
        print(
            f"[WARN] Missing {comp_name}_cosim.rpt in {sim_dir} — "
            "cosim latency will be sourced from csynth",
            file=sys.stderr,
        )

    # Parse
    raw = {}
    raw.update(parse_csynth(csynth_text))
    raw.update(parse_cosim(cosim_text))
    raw.update(parse_compile_log(compile_text))
    raw.update(parse_power_report(power_text))
    raw.update(parse_verbose_sched(sched_text))

    # Derived
    derived = compute_derived(raw)

    return {
        "project": project,
        "version": version,
        "comp":    comp_name,

        # ------------------------------------------------------------------ #
        # PRIMARY METRICS  — raw values collected from report files           #
        # ------------------------------------------------------------------ #
        "primary": {
            "clock": {
                "target_ns":      raw.get("clock_target_ns"),
                "estimated_ns":   raw.get("clock_estimated_ns"),
                "uncertainty_ns": raw.get("clock_uncertainty_ns"),
            },
            "csynth_latency": {
                "min_cycles": raw.get("csynth_latency_min_cycles"),
                "max_cycles": raw.get("csynth_latency_max_cycles"),
            },
            "cosim": {
                "status":              raw.get("cosim_status"),
                "latency_min_cycles":  raw.get("cosim_latency_min_cycles"),
                "latency_avg_cycles":  raw.get("cosim_latency_avg_cycles"),
                "latency_max_cycles":  raw.get("cosim_latency_max_cycles"),
                "interval_min_cycles": raw.get("cosim_interval_min_cycles"),
                "interval_avg_cycles": raw.get("cosim_interval_avg_cycles"),
                "interval_max_cycles": raw.get("cosim_interval_max_cycles"),
                "total_exec_cycles":   raw.get("cosim_total_exec_cycles"),
            },
            "pipeline_type": raw.get("pipeline_type"),
            "interval": {
                "min_cycles": raw.get("interval_min_cycles"),
                "max_cycles": raw.get("interval_max_cycles"),
            },
            "resources": {
                "lut":  {"used": raw.get("used_lut"),  "available": raw.get("avail_lut")},
                "ff":   {"used": raw.get("used_ff"),   "available": raw.get("avail_ff")},
                "bram": {"used": raw.get("used_bram"), "available": raw.get("avail_bram")},
                "dsp":  {"used": raw.get("used_dsp"),  "available": raw.get("avail_dsp")},
            },
            "power_w": {
                "static":  raw.get("power_static_w"),
                "dynamic": raw.get("power_dynamic_w"),
                "total":   raw.get("power_total_w"),
            },
            # Per-loop raw data from csynth loop detail table
            "loops": raw.get("loops", []),
            # FSM structure from verbose schedule report
            "fsm": {
                "num_states":               raw.get("num_fsm_states"),
                "critical_path_max_ns":     raw.get("critical_path_max_ns"),
                "critical_path_per_state_ns": raw.get("critical_path_per_state_ns"),
            },
        },

        # ------------------------------------------------------------------ #
        # FINAL METRICS  — elaborated / derived quantities                    #
        # ------------------------------------------------------------------ #
        "final": {
            "fmax_mhz":            derived.get("fmax_mhz"),
            "min_clock_period_ns": derived.get("min_clock_period_ns"),
            "II":                  derived.get("II"),
            "latency": {
                "max_at_target_ns":    derived.get("latency_max_at_target_ns"),
                "max_at_estimated_ns": derived.get("latency_max_at_estimated_ns"),
                "min_at_target_ns":    derived.get("latency_min_at_target_ns"),
                "min_at_estimated_ns": derived.get("latency_min_at_estimated_ns"),
            },
            "total_execution_time": {
                "at_target_ns":    derived.get("total_exec_at_target_ns"),
                "at_estimated_ns": derived.get("total_exec_at_estimated_ns"),
            },
            "area_total_norm":  derived.get("area_total_norm"),
            "energy_per_op_j":  derived.get("energy_per_op_j"),
            "energy_total_j":   derived.get("energy_total_j"),
            "adp":              derived.get("adp"),
            "edp":              derived.get("edp"),
            # Per-loop derived metrics (latency in ns, throughput)
            "loops": derived.get("loops", []),
        },
    }


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Collect HLS + Vivado metrics into a JSON file."
    )
    parser.add_argument("project", help="Project name, e.g. project01_FIR")
    parser.add_argument("version", help="Component version, e.g. 00_baseline")
    parser.add_argument(
        "--root",
        default=".",
        help="Project root directory (default: current working directory)",
    )
    parser.add_argument(
        "--output",
        default=None,
        help=(
            "Output JSON path. "
            "Defaults to reports/<PROJECT>/<VERSION>/<VERSION>.json"
        ),
    )
    args = parser.parse_args()

    root    = Path(args.root).resolve()
    metrics = collect(args.project, args.version, root)

    if args.output:
        out_path = Path(args.output)
    else:
        out_path = root / "reports" / args.project / args.version / f"{args.version}.json"

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(f"[OK] Metrics written to {out_path}")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
