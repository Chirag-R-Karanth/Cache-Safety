#!/usr/bin/env python3
"""Create reproducible SVG charts and an HTML explanation from simulator CSVs."""
import argparse, csv, html, pathlib
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def read_metrics(path):
    with open(path,newline='') as f: return {r['metric']:r['value'] for r in csv.DictReader(f)}
def read_accesses(path):
    with open(path,newline='') as f: return list(csv.DictReader(f))
def main():
    p=argparse.ArgumentParser();p.add_argument('--summary',required=True);p.add_argument('--accesses',required=True);p.add_argument('--out-dir',default='sim/results/demo');a=p.parse_args()
    out=pathlib.Path(a.out_dir);out.mkdir(parents=True,exist_ok=True);m=read_metrics(a.summary);rows=read_accesses(a.accesses)
    hits=[int(r['hit']) for r in rows]; misses=[1-x for x in hits]; x=list(range(1,len(rows)+1))
    cumulative=[sum(hits[:i])/i*100 for i in x]
    fig,ax=plt.subplots(figsize=(9,4.8));ax.plot(x,cumulative,marker='o',markersize=3);ax.set(xlabel='Memory access number',ylabel='Cumulative hit rate (%)',title='Cache hit rate as the trace executes');ax.set_ylim(0,100);ax.grid(True,alpha=.25);fig.tight_layout();fig.savefig(out/'hit-rate.svg', metadata={'Date': None});plt.close(fig)
    fig,ax=plt.subplots(figsize=(9,4.8));ax.bar(x,hits,label='Hit');ax.bar(x,misses,bottom=hits,label='Miss');ax.set(xlabel='Memory access number',ylabel='Outcome',title='Per-access cache outcome');ax.set_yticks([0,1],['Miss','Hit']);ax.legend();ax.grid(axis='y',alpha=.2);fig.tight_layout();fig.savefig(out/'access-outcomes.svg', metadata={'Date': None});plt.close(fig)
    set_counts={}
    for r in rows: set_counts[r['set']]=set_counts.get(r['set'],0)+1
    fig,ax=plt.subplots(figsize=(7,4));keys=sorted(set_counts,key=lambda z:int(z));ax.bar(keys,[set_counts[k] for k in keys]);ax.set(xlabel='Cache set index',ylabel='Accesses mapped to set',title='Address pressure by cache set');ax.grid(axis='y',alpha=.2);fig.tight_layout();fig.savefig(out/'set-pressure.svg', metadata={'Date': None});plt.close(fig)
    pct=lambda key: f"{float(m[key])*100:.1f}%"
    metric_rows=''.join(f'<tr><th>{html.escape(k.replace("_"," ").title())}</th><td>{html.escape(v)}</td></tr>' for k,v in m.items())
    evictions=sum(int(r['evicted_valid']) for r in rows); dirty=sum(int(r['evicted_dirty']) for r in rows)
    explanation=f"The trace issued {m['accesses']} memory accesses. {m['hits']} were cache hits and {m['misses']} were misses, giving a {pct('hit_rate')} hit rate. A hit means the requested block was already present in its indexed set. A miss causes a line fill; when all ways in that set are occupied, the configured replacement policy chooses a victim. {evictions} valid lines were evicted, including {dirty} dirty lines. Dirty evictions require writeback to the next memory level in this model."
    doc=f'''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>MicroTrace — Cache experiment</title><style>body{{font:16px/1.55 system-ui;max-width:1050px;margin:40px auto;padding:0 20px;color:#20242b}}h1,h2{{line-height:1.2}}.kpis{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}}.kpi,section{{border:1px solid #ddd;border-radius:10px;padding:16px}}.value{{font-size:1.7rem;font-weight:700}}img{{width:100%;height:auto;border:1px solid #ddd;border-radius:8px;margin:8px 0 24px}}table{{border-collapse:collapse;width:100%}}td,th{{padding:7px 10px;border-bottom:1px solid #ddd;text-align:left}}small{{color:#555}}</style><h1>MicroTrace: Cache experiment</h1><p><small>Generated from simulator CSV outputs; no chart values are hard-coded.</small></p><div class="kpis"><div class="kpi"><small>Accesses</small><div class="value">{m['accesses']}</div></div><div class="kpi"><small>Hit rate</small><div class="value">{pct('hit_rate')}</div></div><div class="kpi"><small>Miss rate</small><div class="value">{pct('miss_rate')}</div></div><div class="kpi"><small>Writebacks</small><div class="value">{m['writebacks']}</div></div></div><section><h2>What happened</h2><p>{html.escape(explanation)}</p><p><b>Interpretation:</b> A high hit rate indicates that this particular access sequence reuses blocks while they remain resident. It does not prove that this cache configuration is universally better. Compare configurations using the exact same trace and change one parameter at a time.</p></section><h2>Visual analysis</h2><h3>Cumulative hit rate</h3><img src="hit-rate.svg"><h3>Outcome of every access</h3><img src="access-outcomes.svg"><h3>Cache-set pressure</h3><img src="set-pressure.svg"><h2>Run configuration and metrics</h2><table>{metric_rows}</table><p><small>Model limits: one cache level, blocking conceptual accesses, write-allocate, write-back dirty tracking, and either LRU or FIFO replacement. No real CPU timing or Spectre behaviour is modelled here.</small></p></html>'''
    (out/'report.html').write_text(doc,encoding='utf-8');print(f"Wrote {out/'report.html'} and 3 SVG charts")
if __name__=='__main__':main()
