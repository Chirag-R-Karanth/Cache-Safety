# Cache-Safety dashboard — Phase 8.
#
# Streamlit + Plotly dashboard for the Spectre v1 / Meltdown demonstration.
#
# Reads live probe data from the PYNQ overlay (host/pynq_overlay.py). When no
# PYNQ board/bitstream is present the overlay falls back to mock mode and
# replays the saved experiment artifacts under results/, so the dashboard
# still renders offline.
#
# Run:
#   streamlit run host/dashboard.py
#
# Plotly-only offline export (no Streamlit required):
#   python3 host/dashboard.py --export results/mitigations/leakage_vs_overhead.html
from __future__ import annotations

import argparse
import pathlib
import sys

import plotly.graph_objects as go
import plotly.io as pio

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from host.pynq_overlay import PynqOverlay  # noqa: E402


# ---------------------------------------------------------------- figure helpers
def signature_figure(latencies: list[int], secret: int = 183) -> go.Figure:
    """Probe-latency signature: dip at the secret byte."""
    xs = list(range(256))
    fig = go.Figure()
    fig.add_trace(
        go.Scatter(
            x=xs,
            y=latencies,
            mode="lines",
            name="reload latency (cycles)",
            line=dict(color="#3556a8", width=1.2),
        )
    )
    fig.add_trace(
        go.Scatter(
            x=[secret],
            y=[latencies[secret]],
            mode="markers",
            name=f"secret = {secret} (fastest)",
            marker=dict(color="#c62828", size=10, symbol="circle"),
        )
    )
    fig.add_annotation(
        x=secret,
        y=latencies[secret],
        text=f"{latencies[secret]} cyc",
        showarrow=True,
        arrowhead=2,
        ax=60,
        ay=-40,
        font=dict(color="#c62828"),
    )
    fig.update_layout(
        title="Spectre v1 Flush+Reload signature (trial 0)",
        xaxis_title="Probe byte value b (probe[b] line)",
        yaxis_title="Reload latency (mcycle)",
        xaxis=dict(range=[-4, 259]),
        height=420,
        margin=dict(l=60, r=20, t=60, b=60),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    )
    return fig


def mitigation_figure(rows: list[dict]) -> go.Figure:
    """Leakage-vs-overhead scatter: x = IPC overhead %, y = leak yes/no."""
    fig = go.Figure()
    for name, marker, color in (
        ("Spectre v1", "circle", "#3556a8"),
        ("Meltdown", "square", "#c62828"),
    ):
        sub = [r for r in rows if r["attack"] == name]
        xs = [r["ipc_overhead_pct"] for r in sub]
        ys = [1 if r["leak"] == "yes" else 0 for r in sub]
        fig.add_trace(
            go.Scatter(
                x=xs,
                y=ys,
                mode="markers+text",
                name=name,
                text=[r["mitigation"] for r in sub],
                textposition="top center",
                textfont=dict(size=9),
                marker=dict(symbol=marker, size=12, color=color),
            )
        )
    fig.add_hline(y=0.5, line_dash="dash", line_color="gray", opacity=0.5)
    fig.update_layout(
        title="Mitigation comparison: leakage vs IPC overhead",
        xaxis_title="IPC overhead vs baseline (%)",
        yaxis_title="Side-channel leak",
        yaxis=dict(tickmode="array", tickvals=[0, 1], ticktext=["no", "yes"]),
        height=420,
        margin=dict(l=60, r=20, t=60, b=60),
        legend=dict(orientation="h", yanchor="bottom", y=1.02, xanchor="right", x=1),
    )
    return fig


# ----------------------------------------------------------------------- Streamlit
def run_streamlit() -> None:
    try:
        import streamlit as st  # type: ignore
    except ImportError:  # pragma: no cover - streamlit always present here
        print("streamlit not installed; use --export instead", file=sys.stderr)
        sys.exit(2)

    st.set_page_config(page_title="Cache-Safety — Spectre/Meltdown dashboard",
                       layout="wide")
    st.title("Cache-Safety — Spectre v1 & Meltdown demonstration")
    st.caption("Educational project. Synthetic victim/secret only — do not target "
               "real machines or real secrets.")

    overlay = PynqOverlay()
    summary = overlay.summary()
    st.markdown(f"**Overlay mode:** `{summary['mode']}`  |  "
                f"bitstream: `{summary['bitstream']}`")

    # ---- Spectre v1 signature ----
    st.subheader("Spectre v1 — Flush+Reload signature (trial 0)")
    timings = overlay.read_probe_timings(base=0x1000, count=256)
    # secret from saved recovery.csv if available
    secret = 183
    rec_path = ROOT / "results" / "spectre" / "recovery.csv"
    if rec_path.exists():
        try:
            import csv
            with open(rec_path, newline="") as f:
                for row in csv.DictReader(f):
                    if int(row["trial"]) == 0:
                        secret = int(row["secret"])
                        break
        except (OSError, KeyError, ValueError):
            pass
    st.plotly_chart(signature_figure(timings, secret), use_container_width=True)
    st.markdown(f"The dip at probe byte `{secret}` (≈5 cycles vs ≈12 cycles for all "
                f"other candidates) is the Flush+Reload signal: a squashed wrong-path "
                f"load refilled `probe[{secret}]`, leaking the secret through the cache.")

    # ---- Mitigations ----
    st.subheader("Phase 7 — Mitigation comparison (leakage vs IPC overhead)")
    comp_path = ROOT / "results" / "mitigations" / "comparison.csv"
    rows: list[dict] = []
    if comp_path.exists():
        import csv
        with open(comp_path, newline="") as f:
            rows = list(csv.DictReader(f))
    if rows:
        st.plotly_chart(mitigation_figure(rows), use_container_width=True)
        st.dataframe(
            rows,
            column_config={
                "leak": st.column_config.TextColumn("Leak"),
                "ipc_overhead_pct": st.column_config.NumberColumn("IPC overhead %", format="%.2f"),
            },
            hide_index=True,
            use_container_width=True,
        )
        st.markdown("`DISABLE_SPEC_FILL` removes the speculative-fill primitive and "
                    "stops both attacks at ~0% IPC overhead; `SERIALIZE_BRANCH` stops "
                    "Meltdown but not Spectre v1 (wrong-path load already in flight).")
    else:
        st.info("Run `python3 scripts/mitigation_report.py` to regenerate "
                "`results/mitigations/comparison.csv`.")

    # ---- artifacts ----
    st.subheader("Saved experiment artifacts")
    arts = overlay.saved_artifacts()
    cols = st.columns(len(arts))
    for col, (label, path) in zip(cols, arts.items()):
        with col:
            if path.exists():
                st.markdown(f"**{label}**")
                if path.suffix == ".svg":
                    st.image(str(path))
                else:
                    st.write(str(path))
            else:
                st.markdown(f"**{label}** — not found")

    st.markdown("---")
    st.markdown("See `docs/results.md` for per-phase charts and interpretations.")


# ---------------------------------------------------------------- offline export
def export_html(out: pathlib.Path) -> None:
    """Export a self-contained HTML dashboard (no Streamlit required)."""
    overlay = PynqOverlay()
    timings = overlay.read_probe_timings(base=0x1000, count=256)
    secret = 183
    rec_path = ROOT / "results" / "spectre" / "recovery.csv"
    if rec_path.exists():
        import csv
        with open(rec_path, newline="") as f:
            for row in csv.DictReader(f):
                if int(row["trial"]) == 0:
                    secret = int(row["secret"])
                    break
    comp_path = ROOT / "results" / "mitigations" / "comparison.csv"
    rows: list[dict] = []
    if comp_path.exists():
        import csv
        with open(comp_path, newline="") as f:
            rows = list(csv.DictReader(f))

    html = (
        "<html><head><meta charset='utf-8'><title>Cache-Safety Dashboard</title>"
        "<style>body{font-family:sans-serif;margin:24px;} "
        "h1{color:#1a237e;} h2{color:#3556a8;} "
        ".card{border:1px solid #ddd;border-radius:8px;padding:16px;margin:16px 0;} "
        "table{border-collapse:collapse;width:100%;} "
        "th,td{border:1px solid #ddd;padding:6px;text-align:left;} "
        "th{background:#e8eaf6;}</style></head><body>"
        "<h1>Cache-Safety — Spectre v1 &amp; Meltdown dashboard</h1>"
        f"<p><b>Overlay mode:</b> {overlay.summary()['mode']}</p>"
        "<div class='card'><h2>Spectre v1 — Flush+Reload signature (trial 0)</h2>"
        + pio.to_html(signature_figure(timings, secret),
                      full_html=False, include_plotlyjs="cdn")
        + f"<p>The dip at probe byte <b>{secret}</b> (≈5 cycles vs ≈12 cycles for all "
        "other candidates) is the Flush+Reload signal: a squashed wrong-path load "
        "refilled <code>probe[{secret}]</code>, leaking the secret through the cache.</p>"
        "</div>"
        "<div class='card'><h2>Phase 7 — Mitigation comparison</h2>"
        + pio.to_html(mitigation_figure(rows), full_html=False, include_plotlyjs=False)
        + "<table><tr><th>Attack</th><th>Mitigation</th><th>Leak</th>"
        "<th>IPC</th><th>Overhead %</th></tr>"
        + "".join(
            f"<tr><td>{r['attack']}</td><td>{r['mitigation']}</td>"
            f"<td>{r['leak']}</td><td>{r['ipc']}</td><td>{r['ipc_overhead_pct']}</td></tr>"
            for r in rows
        )
        + "</table>"
        + "<p><code>DISABLE_SPEC_FILL</code> removes the speculative-fill primitive and "
        "stops both attacks at ~0% IPC overhead; <code>SERIALIZE_BRANCH</code> stops "
        "Meltdown but not Spectre v1.</p></div>"
        "</body></html>"
    )
    out.write_text(html)
    print(f"Wrote {out}")


def main() -> None:
    p = argparse.ArgumentParser(description="Cache-Safety dashboard (Phase 8)")
    p.add_argument("--export", metavar="HTML",
                   help="export self-contained HTML dashboard and exit")
    a = p.parse_args()
    if a.export:
        export_html(pathlib.Path(a.export))
    else:
        run_streamlit()


if __name__ == "__main__":
    main()
