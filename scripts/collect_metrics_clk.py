"""
collect_metrics_clk.py

Collects HLS metrics for clock constrained solutions and calculates trade-offs.
Generates a combined JSON file and plots (Pareto curve and fastest solution bar chart).

Usage (from project root):
    python scripts/collect_metrics_clk.py <PROJECT_NAME> <COMP_VERSION>

Example:
    python scripts/collect_metrics_clk.py project01_FIR 00_baseline
"""

import argparse
import json
import re
import sys
from pathlib import Path

try:
    import matplotlib.pyplot as plt
except ImportError:
    print("[ERROR] matplotlib non è installato. Esegui 'pip install matplotlib' per generare i grafici.")
    sys.exit(1)


# ---------------------------------------------------------------------------
# Helpers & Parsers (Invariati)
# ---------------------------------------------------------------------------

def _read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return ""

def _first_match(pattern: str, text: str, group: int = 1, flags: int = 0):
    m = re.search(pattern, text, flags)
    return m.group(group).strip() if m else None

def _float(value) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def _int(value) -> int | None:
    try:
        return int(str(value).strip())
    except (TypeError, ValueError):
        return None

def parse_csynth(text: str) -> dict:
    data = {}
    timing_row = re.search(r"\|\s*ap_clk\s*\|\s*([\d.]+)\s*ns\s*\|\s*([\d.]+)\s*ns\s*\|\s*([\d.]+)\s*ns\s*\|", text)
    if timing_row:
        data["clock_target_ns"]      = _float(timing_row.group(1))
        data["clock_estimated_ns"]   = _float(timing_row.group(2))

    lat_row = re.search(r"\|(\s*\d+\s*)\|(\s*\d+\s*)\|([^|]+)\|([^|]+)\|(\s*\d+\s*)\|(\s*\d+\s*)\|([^|]+)\|", text)
    if lat_row:
        data["csynth_latency_min_cycles"] = _int(lat_row.group(1))
        data["csynth_latency_max_cycles"] = _int(lat_row.group(2))

    for label, keys in [
        ("Total",     ("used_bram",  "used_dsp",  "used_ff",  "used_lut")),
        ("Available", ("avail_bram", "avail_dsp", "avail_ff", "avail_lut")),
    ]:
        row = re.search(rf"\|\s*{label}\s*\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|([^|]+)\|", text)
        if row:
            for i, key in enumerate(keys, start=1):
                val = row.group(i).strip()
                data[key] = _int(val) if re.match(r"^\d+$", val) else None
    return data

def parse_compile_log(text: str) -> dict:
    data = {}
    fmax = _first_match(r"Estimated Fmax:\s*([\d.]+)\s*MHz", text)
    if fmax:
        data["fmax_mhz"] = _float(fmax)
    return data

# ---------------------------------------------------------------------------
# Derived metrics & Trade-offs
# ---------------------------------------------------------------------------

def compute_derived_tradeoff(raw: dict) -> dict:
    derived = {}
    clk_est = raw.get("clock_estimated_ns")
    lat_max = raw.get("csynth_latency_max_cycles")

    # T_tot = D_tot * t_clk (Formula dal PDF)
    delay_ns = None
    if lat_max is not None and clk_est is not None:
        delay_ns = round(lat_max * clk_est, 4)
    derived["total_delay_ns"] = delay_ns

    # Costo Totale dell'Area (Normalizzata per ADP)
    area_parts = []
    for used_key, avail_key in [("used_lut", "avail_lut"), ("used_ff", "avail_ff"),
                                ("used_bram", "avail_bram"), ("used_dsp", "avail_dsp")]:
        used, avail = raw.get(used_key), raw.get(avail_key)
        if used is not None and avail and avail > 0:
            area_parts.append(used / avail)

    area_norm = round(sum(area_parts), 6) if area_parts else None
    derived["area_total_norm"] = area_norm

    # Area-Delay Product (ADP)
    if area_norm is not None and delay_ns is not None:
        derived["adp"] = round(area_norm * delay_ns, 6)
    else:
        derived["adp"] = None

    return derived

def find_comp_name(syn_dir: Path) -> str | None:
    for f in sorted(syn_dir.glob("*_csynth.rpt")):
        name = f.stem.removesuffix("_csynth")
        if name:
            return name
    return None

# ---------------------------------------------------------------------------
# Plotting Functions
# ---------------------------------------------------------------------------

def generate_plots(results: dict, out_dir: Path):
    labels = []
    delays = []
    areas = []

    # Dizionario per raggruppare i punti coincidenti: chiave (delay, area) -> lista di clock
    grouped_points = {}

    for clk, data in results.items():
        delay = data["tradeoffs"].get("total_delay_ns")
        area = data["tradeoffs"].get("area_total_norm")
        if delay is not None and area is not None:
            # Salviamo comunque i dati individuali per il grafico a barre (Bar Chart)
            labels.append(clk)
            delays.append(delay)
            areas.append(area)

            # Raggruppiamo per lo scatter plot (Pareto)
            coord = (delay, area)
            if coord not in grouped_points:
                grouped_points[coord] = []
            grouped_points[coord].append(clk)

    if not labels:
        print("[WARN] Nessun dato valido trovato per generare i grafici.")
        return

    # Preparazione liste raggruppate per lo scatter plot
    scatter_delays = []
    scatter_areas = []
    scatter_labels = []

    for (delay, area), clks in grouped_points.items():
        scatter_delays.append(delay)
        scatter_areas.append(area)
        # Ordina numericamente i clock dal minore al maggiore
        sorted_clks = sorted(clks, key=float)
        # Unisce le etichette in modo che compaiano dall'alto verso il basso (es: 5ns, poi 10ns, poi 20ns)
        scatter_labels.append("\n".join([f"{c}ns" for c in sorted_clks]))

    # 1. Pareto Curve (Area vs Delay)
    plt.figure(figsize=(8, 6))
    plt.scatter(scatter_delays, scatter_areas, color='blue', zorder=5)
    for i, label in enumerate(scatter_labels):
        # Aggiungiamo le etichette (più etichette se ci sono punti sovrapposti)
        plt.annotate(label, (scatter_delays[i], scatter_areas[i]),
                     textcoords="offset points", xytext=(0,10), ha='center', fontsize=9)
    plt.margins(0.07)

    plt.title('Design Space Exploration: Pareto Front (Area vs Delay)')
    plt.xlabel('Total Delay $T_{tot}$ (ns)')
    plt.ylabel('Normalized Area $A_{tot}$')
    plt.grid(True, linestyle='--', alpha=0.7)
    pareto_path = out_dir / "pareto_curve.png"
    plt.savefig(pareto_path)
    plt.close()
    print(f"[OK] Grafico di Pareto salvato in {pareto_path}")

    # 2. Fastest Solution Bar Chart
    # Ordiniamo le liste associandole e ordinandole in base al delay (crescente)
    sorted_data = sorted(zip(labels, delays), key=lambda x: x[1])
    sorted_labels = [x[0] for x in sorted_data]
    sorted_delays = [x[1] for x in sorted_data]

    plt.figure(figsize=(10, 6))

    # Inizializza tutti i colori a skyblue e colora di arancione la prima barra (la più veloce)
    colors = ['skyblue'] * len(sorted_labels)
    colors[0] = 'orange'

    bars = plt.bar(sorted_labels, sorted_delays, color=colors, edgecolor='black')
    plt.title('Confronto Total Delay tra vincoli di Clock')
    plt.xlabel('Clock Constraint (ns)')
    plt.ylabel('Total Delay $T_{tot}$ (ns)')
    plt.xticks(rotation=45)

    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2, yval + (max(sorted_delays)*0.01), round(yval, 1), ha='center', va='bottom')

    bar_path = out_dir / "fastest_solution_delay.png"
    plt.savefig(bar_path)
    plt.close()
    print(f"[OK] Istogramma Delay salvato in {bar_path}")


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

def collect_clk_tradeoffs(project: str, version: str, root: Path) -> dict:
    base_dir = root / "reports" / project / f"{version}_clk"

    if not base_dir.exists():
        print(f"[ERROR] Cartella base non trovata: {base_dir}", file=sys.stderr)
        sys.exit(1)

    all_metrics = {}

    # Scorre tutte le sottocartelle <CLK_VAL>
    for clk_dir in sorted(base_dir.iterdir()):
        if not clk_dir.is_dir():
            continue

        clk_val = clk_dir.name
        syn_dir = clk_dir / "hls" / "syn"

        if not syn_dir.exists():
            continue

        comp_name = find_comp_name(syn_dir)
        if not comp_name:
            print(f"[WARN] Impossibile dedurre il component name in {syn_dir}")
            continue

        csynth_text  = _read(syn_dir / f"{comp_name}_csynth.rpt")
        compile_text = _read(syn_dir / "hls_compile.log")

        if not csynth_text:
            continue

        raw = {}
        raw.update(parse_csynth(csynth_text))
        raw.update(parse_compile_log(compile_text))
        tradeoffs = compute_derived_tradeoff(raw)

        all_metrics[clk_val] = {
            "comp_name": comp_name,
            "raw_data": {
                "clock_estimated_ns": raw.get("clock_estimated_ns"),
                "latency_max_cycles": raw.get("csynth_latency_max_cycles"),
                "fmax_mhz": raw.get("fmax_mhz"),
            },
            "resources": {
                "lut":  {"used": raw.get("used_lut"),  "available": raw.get("avail_lut")},
                "ff":   {"used": raw.get("used_ff"),   "available": raw.get("avail_ff")},
                "bram": {"used": raw.get("used_bram"), "available": raw.get("avail_bram")},
                "dsp":  {"used": raw.get("used_dsp"),  "available": raw.get("avail_dsp")},
            },
            "tradeoffs": tradeoffs
        }

    return all_metrics

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Collect HLS metrics and plot trade-offs for varying clock constraints.")
    parser.add_argument("project", help="Project name, e.g. project01_FIR")
    parser.add_argument("version", help="Component version (senza '_clk'), e.g. 00_baseline")
    parser.add_argument("--root", default=".", help="Project root directory")
    args = parser.parse_args()

    root = Path(args.root).resolve()

    print(f"Analisi della cartella: reports/{args.project}/{args.version}_clk/")
    results = collect_clk_tradeoffs(args.project, args.version, root)

    if not results:
        print("[ERROR] Nessuna metrica estratta. Controlla la struttura delle cartelle.")
        sys.exit(1)

    # Setup cartella di output generale per questi risultati
    out_dir = root / "reports" / args.project / f"{args.version}_clk"
    out_dir.mkdir(parents=True, exist_ok=True)

    # 1. Scrittura del file JSON
    json_path = out_dir / "tradeoff_metrics.json"
    json_path.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print(f"[OK] Metriche JSON salvate in {json_path}")

    # 2. Generazione Grafici
    generate_plots(results, out_dir)


if __name__ == "__main__":
    main()