#!/usr/bin/env python3
"""Mitigation comparison report for Phase 6 (Meltdown) and Phase 5 (Spectre v1).

Runs each attack under every mitigation configuration and produces:

* a comparison table: leak success rate + IPC/cycle overhead per mitigation
* a leakage-versus-overhead plot (leak = yes/no, y = IPC)
* a summary saved to results/mitigations/{comparison.csv, comparison.svg}

Usage:
  scripts/mitigation_report.py \
      [--tb build/riscv-tests/tb_core.vvp] \
      [--spectre build/riscv-tests/spectre_v1.hex] \
      [--meltdown build/riscv-tests/meltdown.hex] \
      [--out-dir results/mitigations]
"""
import argparse
import csv
import pathlib
import subprocess
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

CONFIGS = [
    ("none", []),
    ("DISABLE_SPEC_FILL", ["+DISABLE_SPEC_FILL"]),
    ("SERIALIZE_BRANCH", ["+SERIALIZE_BRANCH"]),
    ("DISABLE_SPEC_FILL+SERIALIZE_BRANCH", ["+DISABLE_SPEC_FILL", "+SERIALIZE_BRANCH"]),
]


def run(tb, hexfile, extra_vflags, mflags):
    cmd = ["vvp", tb, "+HEX=" + hexfile] + extra_vflags + mflags
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    trap = any(l.startswith("TRAP") for l in out.splitlines())
    magic = None
    for l in out.splitlines():
        if l.startswith("MAGIC "):
            magic = int(l.split()[1], 16)
    expectfill = any(l.startswith("EXPECTFILL PASS") for l in out.splitlines())
    cycles = instret = ipc = None
    for l in out.splitlines():
        if l.startswith("CYCLES="):
            parts = dict(kv.split("=") for kv in l.split())
            cycles = int(parts["CYCLES"])
            instret = int(parts["INSTRET"])
            ipc = float(parts["IPC"])
    return dict(trap=trap, magic=magic, expectfill=expectfill,
                cycles=cycles, instret=instret, ipc=ipc, raw=out)


def spectre_leak(out):
    rows = {}
    for l in out.splitlines():
        if l.startswith("RES "):
            _, i, v = l.split()
            rows[int(i)] = int(v, 16)
    if not rows:
        return False
    n = len(rows) // 257
    if n == 0:
        return False
    sec = rows[0]
    lats = [rows[1 + b] for b in range(256)]
    am = min(range(256), key=lambda b: lats[b])
    other = [lats[b] for b in range(256) if b != sec]
    return am == sec and lats[sec] < min(other)


def meltdown_leak(res):
    return res["trap"] and res["expectfill"]


def attack_matrix(tb, hexfile, kind, extra_vflags):
    """Return list of dicts: config, leak, ipc, cycles, instret."""
    base = None
    results = []
    for name, mflags in CONFIGS:
        res = run(tb, hexfile, extra_vflags, mflags)
        if kind == "spectre":
            leak = spectre_leak(res["raw"]) and res["magic"] is not None
        else:
            leak = meltdown_leak(res)
        entry = dict(config=name, leak=leak, ipc=res["ipc"],
                     cycles=res["cycles"], instret=res["instret"])
        results.append(entry)
        if name == "none":
            base = entry
    # IPC overhead relative to baseline
    if base and base["ipc"]:
        for e in results:
            e["ipc_overhead"] = (e["ipc"] / base["ipc"] - 1.0) * 100.0 if e["ipc"] else 0.0
    else:
        for e in results:
            e["ipc_overhead"] = 0.0
    return results


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--tb", default="build/riscv-tests/tb_core.vvp")
    p.add_argument("--spectre", default="build/riscv-tests/spectre_v1.hex")
    p.add_argument("--meltdown", default="build/riscv-tests/meltdown.hex")
    p.add_argument("--out-dir", default="results/mitigations")
    a = p.parse_args()

    out = pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    spectre = attack_matrix(a.tb, a.spectre, "spectre",
                            ["+TIMEOUT=2000000", "+DUMPADDR=2000", "+DUMPWORDS=1799"])
    meltdown = attack_matrix(a.tb, a.meltdown, "meltdown", ["+expectfill=1420"])

    # ---- comparison table ----
    with open(out / "comparison.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["attack", "mitigation", "leak", "ipc", "ipc_overhead_pct",
                    "cycles", "instret"])
        for name, rows in (("spectre_v1", spectre), ("meltdown", meltdown)):
            for e in rows:
                w.writerow([name, e["config"], "yes" if e["leak"] else "no",
                            e["ipc"], e["ipc_overhead"], e["cycles"], e["instret"]])

    print("Mitigation comparison table:")
    print(f"{'attack':<14} {'mitigation':<32} {'leak':<5} {'ipc':<7} {'overhead%':<10}")
    for name, rows in (("spectre_v1", spectre), ("meltdown", meltdown)):
        for e in rows:
            print(f"{name:<14} {e['config']:<32} {('yes' if e['leak'] else 'no'):<5} "
                  f"{e['ipc']:<7.3f} {e['ipc_overhead']:<10.2f}")

    # ---- leakage-vs-overhead plot ----
    fig, ax = plt.subplots(figsize=(7, 4.2))
    for name, rows, marker in (("spectre_v1", spectre, "o"),
                               ("meltdown", meltdown, "s")):
        xs = [e["ipc_overhead"] for e in rows]
        ys = [1 if e["leak"] else 0 for e in rows]
        labels = [e["config"] for e in rows]
        ax.scatter(xs, ys, marker=marker, s=80, label=name)
        for x, y, lab in zip(xs, ys, labels):
            ax.annotate(lab, (x, y), textcoords="offset points",
                        xytext=(6, 0), fontsize=8)
    ax.axhline(0.5, color="gray", ls="--", lw=0.8)
    ax.set_yticks([0, 1])
    ax.set_yticklabels(["no leak", "leak"])
    ax.set_xlabel("IPC overhead vs baseline (%)")
    ax.set_ylabel("Side-channel leak")
    ax.set_title("Mitigation comparison: leakage vs IPC overhead")
    ax.legend()
    ax.grid(True, alpha=0.25)
    fig.tight_layout()
    fig.savefig(out / "leakage_vs_overhead.svg", metadata={"Date": None})
    plt.close(fig)

    print(f"Wrote {out / 'comparison.csv'} and {out / 'leakage_vs_overhead.svg'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
