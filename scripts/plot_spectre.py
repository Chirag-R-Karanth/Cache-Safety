#!/usr/bin/env python3
"""Spectre v1 Flush+Reload signature from spectre_v1 trial dumps.

Reads the CSV (columns: trial,secret,b,latency) produced by
tests/run_riscv_tests.sh from the TB RES dump, verifies that every
trial's fastest probe line is the secret byte, and renders the
256-entry probe-latency plot with the dip at the secret.

Usage:
  plot_spectre.py --csv results/spectre/results.csv \
                  --out-dir results/spectre [--verify]
"""
import argparse
import csv
import pathlib
import sys

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def read_rows(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))


def group_trials(rows):
    trials = {}
    for r in rows:
        t = int(r['trial'])
        trials.setdefault(t, {'secret': int(r['secret']), 'lat': []})
        trials[t]['lat'].append((int(r['b']), int(r['latency'])))
    for t in trials:
        trials[t]['lat'] = [v for _, v in sorted(trials[t]['lat'])]
    return trials


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--csv', required=True)
    p.add_argument('--out-dir', default='results/spectre')
    p.add_argument('--verify', action='store_true',
                   help='exit non-zero unless every trial recovers the secret')
    a = p.parse_args()

    trials = group_trials(read_rows(a.csv))
    if not trials:
        print('ERROR: no trials in CSV', file=sys.stderr)
        return 1

    recovered = 0
    report = []
    for t in sorted(trials):
        secret = trials[t]['secret']
        lat = trials[t]['lat']
        argmin = min(range(len(lat)), key=lambda b: lat[b])
        ok = argmin == secret and lat[secret] < min(
            lat[b] for b in range(len(lat)) if b != secret)
        recovered += ok
        report.append((t, secret, argmin, lat[secret],
                       min(lat[b] for b in range(len(lat)) if b != secret),
                       ok))
    n = len(trials)

    out = pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    # signature plot: trial 0 (single dip at the secret byte)
    t0 = trials[sorted(trials)[0]]
    lat, secret = t0['lat'], t0['secret']
    xs = list(range(256))
    fig, ax = plt.subplots(figsize=(9, 4.8))
    ax.plot(xs, lat, lw=1.2, color='#3556a8', label='reload latency')
    ax.plot([secret], [lat[secret]], 'o', ms=7, color='#c62828',
            label=f'secret = {secret} (fastest)')
    ax.annotate(f'{lat[secret]} cyc', (secret, lat[secret]),
                textcoords='offset points', xytext=(8, -14),
                color='#c62828', fontsize=9)
    ax.set(xlabel='Probe byte value b (probe[b] line)',
           ylabel='Reload latency (mcycle)',
           title=f'Spectre v1 Flush+Reload signature — trial 0, '
                 f'recovery {recovered}/{n} trials')
    ax.set_xlim(-4, 259)
    ax.grid(True, alpha=.25)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out / 'signature.svg', metadata={'Date': None})
    plt.close(fig)

    # recovery summary table (CSV, committed as evidence)
    with open(out / 'recovery.csv', 'w', newline='') as f:
        w = csv.writer(f)
        w.writerow(['trial', 'secret', 'argmin', 'secret_latency',
                    'min_other_latency', 'recovered'])
        for row in report:
            w.writerow(row)

    for t, s, am, sl, mo, ok in report:
        print(f'trial {t}: secret={s:3d} argmin={am:3d} '
              f'latency {sl} vs {mo} (other) -> {"OK" if ok else "FAIL"}')
    print(f'recovery: {recovered}/{n}')

    if a.verify and recovered != n:
        print('ERROR: secret not recovered in every trial', file=sys.stderr)
        return 1
    print(f'Wrote {out / "signature.svg"} and {out / "recovery.csv"}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
