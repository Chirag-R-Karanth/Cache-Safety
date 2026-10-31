#!/usr/bin/env python3
import csv, pathlib, subprocess, tempfile, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
class CacheSimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp=pathlib.Path(tempfile.mkdtemp(prefix='microtrace-tests-'))
        cls.bin=cls.tmp/'cache_sim'
        subprocess.run(['g++','-std=c++17','-O2','-Wall','-Wextra','-Wpedantic',str(ROOT/'src/cache_sim.cpp'),'-o',str(cls.bin)],check=True)
    def run_sim(self, trace, **opts):
        trace_path=self.tmp/'case.trace'; trace_path.write_text(trace)
        prefix=self.tmp/'out'
        args=[str(self.bin),'--trace',str(trace_path),'--out',str(prefix)]
        for k,v in opts.items(): args += ['--'+k.replace('_','-'),str(v)]
        proc=subprocess.run(args,text=True,capture_output=True)
        return proc,prefix
    def summary(self,prefix):
        with open(str(prefix)+'_summary.csv',newline='') as f:return {r['metric']:r['value'] for r in csv.DictReader(f)}
    def test_repeated_block_hits_after_first_miss(self):
        p,o=self.run_sim('R 0x0\nR 0x0\nR 0x0\n',capacity=256,line_size=64,ways=1,policy='lru')
        self.assertEqual(p.returncode,0,p.stderr); m=self.summary(o)
        self.assertEqual((m['accesses'],m['hits'],m['misses']),('3','2','1'))
    def test_dirty_eviction_causes_writeback(self):
        p,o=self.run_sim('W 0x0\nR 0x100\n',capacity=64,line_size=64,ways=1,policy='lru')
        self.assertEqual(p.returncode,0,p.stderr); self.assertEqual(self.summary(o)['writebacks'],'1')
    def test_invalid_non_power_of_two_set_count_rejected(self):
        p,_=self.run_sim('R 0x0\n',capacity=192,line_size=64,ways=1,policy='lru')
        self.assertNotEqual(p.returncode,0); self.assertIn('valid powers of two',p.stderr)
    def test_empty_trace_has_zero_counts(self):
        p,o=self.run_sim('# empty\n',capacity=256,line_size=64,ways=2,policy='fifo')
        self.assertEqual(p.returncode,0,p.stderr); m=self.summary(o)
        self.assertEqual((m['accesses'],m['hits'],m['misses']),('0','0','0'))
    def test_lru_and_fifo_choose_different_victims(self):
        trace='R 0x0\nR 0x40\nR 0x0\nR 0x80\nR 0x40\n'
        lru,o=self.run_sim(trace,capacity=128,line_size=64,ways=2,policy='lru')
        self.assertEqual(lru.returncode,0,lru.stderr); lru_m=self.summary(o)
        fifo,o=self.run_sim(trace,capacity=128,line_size=64,ways=2,policy='fifo')
        self.assertEqual(fifo.returncode,0,fifo.stderr); fifo_m=self.summary(o)
        self.assertEqual(lru_m['misses'],'4'); self.assertEqual(fifo_m['misses'],'3')
if __name__=='__main__':unittest.main()
