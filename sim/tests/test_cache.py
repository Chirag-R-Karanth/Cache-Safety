#!/usr/bin/env python3
"""Cache simulator test suite: correctness per policy + edge cases + AMAT."""
import csv
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]


class CacheSimulatorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = pathlib.Path(tempfile.mkdtemp(prefix='cache-safety-tests-'))
        cls.bin = cls.tmp / 'cache_sim'
        subprocess.run(
            ['g++', '-std=c++17', '-O2', '-Wall', '-Wextra', '-Wpedantic',
             str(ROOT / 'src/cache.cpp'), '-o', str(cls.bin)],
            check=True)

    def run_sim(self, trace, name='out', **opts):
        trace_path = self.tmp / f'{name}.trace'
        trace_path.write_text(trace)
        prefix = self.tmp / name
        args = [str(self.bin), '--trace', str(trace_path), '--out', str(prefix)]
        for k, v in opts.items():
            args += ['--' + k.replace('_', '-'), str(v)]
        proc = subprocess.run(args, text=True, capture_output=True)
        return proc, prefix

    def summary(self, prefix):
        with open(str(prefix) + '_summary.csv', newline='') as f:
            return {r['metric']: r['value'] for r in csv.DictReader(f)}

    def accesses(self, prefix):
        with open(str(prefix) + '_accesses.csv', newline='') as f:
            return list(csv.DictReader(f))

    # --- basic hit/miss -----------------------------------------------------
    def test_repeated_block_hits_after_first_miss(self):
        p, o = self.run_sim('R 0x0\nR 0x0\nR 0x0\n',
                            capacity=256, line_size=64, ways=1, policy='lru')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual((m['accesses'], m['hits'], m['misses']), ('3', '2', '1'))

    def test_cold_cache_first_access_always_misses(self):
        p, o = self.run_sim('R 0x0\nR 0x40\nR 0x80\n',
                            capacity=256, line_size=64, ways=4, policy='lru')
        self.assertEqual(p.returncode, 0, p.stderr)
        rows = self.accesses(o)
        self.assertEqual([r['hit'] for r in rows], ['0', '0', '0'])

    def test_dirty_eviction_causes_writeback(self):
        p, o = self.run_sim('W 0x0\nR 0x100\n',
                            capacity=64, line_size=64, ways=1, policy='lru')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(self.summary(o)['writebacks'], '1')

    def test_invalid_non_power_of_two_set_count_rejected(self):
        p, _ = self.run_sim('R 0x0\n', capacity=192, line_size=64, ways=1,
                            policy='lru')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('valid powers of two', p.stderr)

    def test_empty_trace_has_zero_counts(self):
        p, o = self.run_sim('# empty\n', capacity=256, line_size=64, ways=2,
                            policy='fifo')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual((m['accesses'], m['hits'], m['misses']), ('0', '0', '0'))

    # --- replacement policies ----------------------------------------------
    def test_lru_and_fifo_choose_different_victims(self):
        trace = 'R 0x0\nR 0x40\nR 0x0\nR 0x80\nR 0x40\n'
        lru, o = self.run_sim(trace, capacity=128, line_size=64, ways=2,
                              policy='lru')
        self.assertEqual(lru.returncode, 0, lru.stderr)
        lru_m = self.summary(o)
        fifo, o = self.run_sim(trace, capacity=128, line_size=64, ways=2,
                               policy='fifo')
        self.assertEqual(fifo.returncode, 0, fifo.stderr)
        fifo_m = self.summary(o)
        self.assertEqual(lru_m['misses'], '4')
        self.assertEqual(fifo_m['misses'], '3')

    def test_plru_and_lru_evict_different_ways(self):
        # Hand-worked 4-way PLRU vs LRU (tree walk in build report):
        # A B C D fills, then hits A B C, then E evicts A (PLRU) vs D (LRU);
        # final A is a hit under LRU and a miss under PLRU.
        addrs = [0x00, 0x40, 0x80, 0xC0, 0x00, 0x40, 0x80, 0x100, 0x00]
        trace = ''.join(f'R 0x{a:x}\n' for a in addrs)
        lru, ol = self.run_sim(trace, name='lru4', capacity=256, line_size=64,
                               ways=4, policy='lru')
        self.assertEqual(lru.returncode, 0, lru.stderr)
        plru, op = self.run_sim(trace, name='plru4', capacity=256,
                                line_size=64, ways=4, policy='plru')
        self.assertEqual(plru.returncode, 0, plru.stderr)
        self.assertEqual(self.summary(ol)['misses'], '5')
        self.assertEqual(self.summary(op)['misses'], '6')

    def test_non_power_of_two_ways_rejected(self):
        # ways=3 can never satisfy "sets must be a power of two" together
        # with power-of-two capacity/line size — must be rejected either way.
        p, _ = self.run_sim('R 0x0\n', capacity=192, line_size=64, ways=3,
                            policy='plru')
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('error:', p.stderr)

    def test_random_policy_deterministic_with_seed(self):
        trace = ''.join(f'R 0x{a:x}\n' for a in range(0, 0x400, 0x40))
        p1, o1 = self.run_sim(trace, name='rnd1', capacity=128, line_size=64,
                              ways=2, policy='random', seed=123)
        p2, o2 = self.run_sim(trace, name='rnd2', capacity=128, line_size=64,
                              ways=2, policy='random', seed=123)
        self.assertEqual(p1.returncode, 0, p1.stderr)
        self.assertEqual(p2.returncode, 0, p2.stderr)
        self.assertEqual(self.summary(o1)['misses'],
                         self.summary(o2)['misses'])
        rows1, rows2 = self.accesses(o1), self.accesses(o2)
        self.assertEqual([r['evicted_address'] for r in rows1],
                         [r['evicted_address'] for r in rows2])

    # --- edge-case geometries ----------------------------------------------
    def test_full_associativity_single_set(self):
        # 256 B / (64 B * 4 ways) = 1 set: everything competes everywhere.
        trace = 'R 0x0\nR 0x40\nR 0x80\nR 0xC0\nR 0x0\n'
        p, o = self.run_sim(trace, capacity=256, line_size=64, ways=4,
                            policy='lru')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual(m['sets'], '1')
        self.assertEqual((m['hits'], m['misses']), ('1', '4'))

    def test_single_line_cache(self):
        trace = 'R 0x0\nR 0x0\nR 0x40\nR 0x0\n'
        p, o = self.run_sim(trace, capacity=64, line_size=64, ways=1,
                            policy='lru')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual((m['sets'], m['ways']), ('1', '1'))
        # miss, hit, miss (evicts), miss
        self.assertEqual(m['misses'], '3')

    # --- write policies -----------------------------------------------------
    def test_write_through_generates_no_writebacks(self):
        # 2-line cache: W miss (alloc+through), R miss, W hit (through), R hit
        trace = 'W 0x0\nR 0x40\nW 0x0\nR 0x40\n'
        p, o = self.run_sim(trace, capacity=128, line_size=64, ways=1,
                            write_policy='wt')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual(m['writebacks'], '0')
        self.assertEqual(m['write_policy'], 'wt')
        self.assertEqual((m['hits'], m['misses']), ('2', '2'))
        self.assertEqual(m['write_throughs'], '2')

    def test_write_no_allocate_does_not_fill_on_write(self):
        trace = 'W 0x0\nR 0x0\n'
        p, o = self.run_sim(trace, capacity=64, line_size=64, ways=1,
                            write_policy='wt', write_allocate=0)
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        # write miss bypasses (no fill); the later read miss allocates
        self.assertEqual((m['misses'], m['fills']), ('2', '1'))
        self.assertEqual(m['write_throughs'], '1')

    def test_write_back_write_hit_marks_dirty(self):
        p, o = self.run_sim('W 0x0\nR 0x0\n', capacity=64, line_size=64,
                            ways=1, write_policy='wb')
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        self.assertEqual((m['hits'], m['misses'], m['writebacks']),
                         ('1', '1', '0'))
        self.assertEqual(m['write_throughs'], '0')

    # --- AMAT ---------------------------------------------------------------
    def test_amat_formula(self):
        # 3 accesses to the same block, 1 miss => miss_rate = 1/3
        p, o = self.run_sim('R 0x0\nR 0x0\nR 0x0\n', capacity=64,
                            line_size=64, ways=1, hit_latency=2,
                            miss_penalty=40)
        self.assertEqual(p.returncode, 0, p.stderr)
        m = self.summary(o)
        expected = 2.0 + (1.0 / 3.0) * 40.0
        self.assertAlmostEqual(float(m['amat']), expected, places=6)

    def test_amat_on_empty_trace_equals_hit_latency(self):
        p, o = self.run_sim('# nothing\n', capacity=64, line_size=64, ways=1,
                            hit_latency=3, miss_penalty=100)
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertEqual(float(self.summary(o)['amat']), 3.0)


if __name__ == '__main__':
    unittest.main()
