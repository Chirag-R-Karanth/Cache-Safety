#!/usr/bin/env python3
"""Design-space sweep: capacity x ways x line size x policy across traces.

Outputs (under --out-dir, default sim/results/sweep/):
  comparison.csv              — one row per configuration (hit_rate, amat, ...)
  hit-rate-comparison.svg     — bar chart: ways x policy at base config
  hit-rate-vs-capacity.svg    — hit rate vs capacity, per policy
  amat-vs-ways.svg            — AMAT vs associativity, per policy
"""
import argparse
import csv
import pathlib
import subprocess

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt


def metrics(path):
    with open(path, newline='') as f:
        return {r['metric']: r['value'] for r in csv.DictReader(f)}


def run_one(binary, trace, prefix, **cfg):
    args = [binary, '--trace', str(trace), '--out', str(prefix)]
    for k, v in cfg.items():
        args += ['--' + k.replace('_', '-'), str(v)]
    subprocess.run(args, check=True, capture_output=True, text=True)
    return metrics(str(prefix) + '_summary.csv')


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--binary', default='./cache_sim')
    p.add_argument('--traces', nargs='+',
                   default=['sim/traces/locality_demo.trace',
                            'sim/traces/loop_reuse.trace',
                            'sim/traces/stream_stride.trace'])
    p.add_argument('--out-dir', default='sim/results/sweep')
    p.add_argument('--capacity', type=int, default=256)
    p.add_argument('--line-size', type=int, default=64)
    p.add_argument('--hit-latency', type=float, default=1.0)
    p.add_argument('--miss-penalty', type=float, default=50.0)
    a = p.parse_args()

    out = pathlib.Path(a.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    policies = ('lru', 'fifo', 'plru')
    rows = []

    # Sweep 1: associativity x policy at the base capacity (all traces)
    for trace in a.traces:
        tname = pathlib.Path(trace).stem
        for ways in (1, 2, 4):
            for policy in policies:
                if policy == 'plru' and ways not in (1, 2, 4):
                    continue
                prefix = out / f'{tname}-{ways}way-{policy}'
                m = run_one(a.binary, trace, prefix,
                            capacity=a.capacity, line_size=a.line_size,
                            ways=ways, policy=policy,
                            hit_latency=a.hit_latency,
                            miss_penalty=a.miss_penalty)
                rows.append({'trace': tname, 'sweep': 'ways', 'ways': ways,
                             'capacity': a.capacity, 'line_size': a.line_size,
                             'policy': policy, 'accesses': m['accesses'],
                             'hits': m['hits'], 'misses': m['misses'],
                             'hit_rate': m['hit_rate'], 'amat': m['amat'],
                             'writebacks': m['writebacks']})

    # Sweep 2: capacity at fixed 2-way LRU (first trace only, hit-rate curve)
    cap_trace = a.traces[0]
    tname = pathlib.Path(cap_trace).stem
    for capacity in (128, 256, 512, 1024, 2048):
        for policy in policies:
            prefix = out / f'{tname}-cap{capacity}-{policy}'
            m = run_one(a.binary, cap_trace, prefix,
                        capacity=capacity, line_size=a.line_size, ways=2,
                        policy=policy, hit_latency=a.hit_latency,
                        miss_penalty=a.miss_penalty)
            rows.append({'trace': tname, 'sweep': 'capacity', 'ways': 2,
                         'capacity': capacity, 'line_size': a.line_size,
                         'policy': policy, 'accesses': m['accesses'],
                         'hits': m['hits'], 'misses': m['misses'],
                         'hit_rate': m['hit_rate'], 'amat': m['amat'],
                         'writebacks': m['writebacks']})

    with open(out / 'comparison.csv', 'w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    def sel(sweep, **flt):
        return [r for r in rows if r['sweep'] == sweep
                and all(r[k] == v for k, v in flt.items())]

    # Chart 1: ways x policy bars per trace (backwards-compatible name)
    base = sel('ways')
    traces = sorted({r['trace'] for r in base})
    fig, axes = plt.subplots(1, len(traces), figsize=(5 * len(traces), 4.5),
                             squeeze=False)
    for ax, tname in zip(axes[0], traces):
        sub = [r for r in base if r['trace'] == tname]
        labels = [f"{r['ways']}-way {r['policy'].upper()}" for r in sub]
        vals = [float(r['hit_rate']) * 100 for r in sub]
        ax.bar(labels, vals)
        ax.set(ylabel='Hit rate (%)',
               title=f'Associativity x policy — {tname}',
               ylim=(0, 100))
        ax.tick_params(axis='x', rotation=35)
        ax.grid(axis='y', alpha=.25)
    fig.tight_layout()
    fig.savefig(out / 'hit-rate-comparison.svg', metadata={'Date': None})
    plt.close(fig)

    # Chart 2: hit rate vs capacity (2-way, all policies, primary trace)
    cap_rows = sel('capacity')
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for policy in policies:
        sub = sorted((r for r in cap_rows if r['policy'] == policy),
                     key=lambda r: r['capacity'])
        if not sub:
            continue
        ax.plot([r['capacity'] for r in sub],
                [float(r['hit_rate']) * 100 for r in sub],
                marker='o', label=policy.upper())
    ax.set(xlabel='Cache capacity (bytes)', ylabel='Hit rate (%)',
           title=f'Hit rate vs capacity (2-way, {tname})', xscale='log')
    ax.set_xticks([128, 256, 512, 1024, 2048])
    ax.set_xticklabels(["128", "256", "512", "1024", "2048"])
    ax.set_ylim(0, 100)
    ax.legend()
    ax.grid(alpha=.25)
    fig.tight_layout()
    fig.savefig(out / 'hit-rate-vs-capacity.svg', metadata={'Date': None})
    plt.close(fig)

    # Chart 3: AMAT vs ways (all traces, LRU only)
    fig, ax = plt.subplots(figsize=(8, 4.8))
    for tname in traces:
        sub = sorted((r for r in base if r['trace'] == tname
                      and r['policy'] == 'lru'), key=lambda r: r['ways'])
        ax.plot([r['ways'] for r in sub], [float(r['amat']) for r in sub],
                marker='s', label=tname)
    ax.set(xlabel='Associativity (ways)',
           ylabel='AMAT (cycles)',
           title=f'AMAT vs associativity (LRU, hit={a.hit_latency:g}, '
                 f'penalty={a.miss_penalty:g})')
    ax.set_xticks([1, 2, 4])
    ax.legend()
    ax.grid(alpha=.25)
    fig.tight_layout()
    fig.savefig(out / 'amat-vs-ways.svg', metadata={'Date': None})
    plt.close(fig)

    print(f'Wrote {out}/comparison.csv and 3 charts '
          f'({len(rows)} configurations, {len(traces)} traces)')


if __name__ == '__main__':
    main()
