#!/usr/bin/env python3
"""Run identical trace across associativity and replacement-policy combinations."""
import argparse,csv,pathlib,subprocess
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

def metrics(path):
    with open(path,newline='') as f:return {r['metric']:r['value'] for r in csv.DictReader(f)}
def main():
    p=argparse.ArgumentParser();p.add_argument('--binary',default='./cache_sim');p.add_argument('--trace',default='sim/traces/locality_demo.trace');p.add_argument('--out-dir',default='sim/results/sweep');p.add_argument('--capacity',type=int,default=256);p.add_argument('--line-size',type=int,default=64);a=p.parse_args()
    out=pathlib.Path(a.out_dir);out.mkdir(parents=True,exist_ok=True); rows=[]
    for ways in (1,2,4):
        for policy in ('lru','fifo'):
            prefix=out/f'{ways}way-{policy}'
            subprocess.run([a.binary,'--trace',a.trace,'--out',str(prefix),'--capacity',str(a.capacity),'--line-size',str(a.line_size),'--ways',str(ways),'--policy',policy],check=True)
            m=metrics(str(prefix)+'_summary.csv');rows.append({'ways':ways,'policy':policy,'accesses':m['accesses'],'hits':m['hits'],'misses':m['misses'],'hit_rate':m['hit_rate'],'writebacks':m['writebacks']})
    with open(out/'comparison.csv','w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=rows[0].keys());w.writeheader();w.writerows(rows)
    fig,ax=plt.subplots(figsize=(8,4.5));labels=[f"{r['ways']}-way {r['policy'].upper()}" for r in rows];vals=[float(r['hit_rate'])*100 for r in rows]
    ax.bar(labels,vals);ax.set(ylabel='Hit rate (%)',title='Associativity and replacement policy — same trace');ax.set_ylim(0,100);ax.tick_params(axis='x',rotation=25);ax.grid(axis='y',alpha=.25);fig.tight_layout();fig.savefig(out/'hit-rate-comparison.svg');plt.close(fig)
    print(f'Wrote {out}/comparison.csv and {out}/hit-rate-comparison.svg')
if __name__=='__main__':main()
