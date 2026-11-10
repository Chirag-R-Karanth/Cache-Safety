// Trace-driven set-associative cache simulator (Phase 1 of Cache-Safety).
// Configurable: capacity, line size, associativity, replacement policy
// (LRU/FIFO/tree-PLRU/random), write policy (write-back/write-through,
// write-allocate on/off), hit latency and miss penalty for AMAT.
// Trace format: one access per line — "R 0xADDR" or "W 0xADDR"; '#' comments.
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Line {
	bool valid = false, dirty = false;
	uint64_t tag = 0, inserted = 0, touched = 0;
};

enum class Policy { LRU, FIFO, PLRU, RANDOM };

struct Config {
	uint64_t capacity = 1024, line_size = 64;
	size_t ways = 1;
	Policy policy = Policy::LRU;
	std::string policy_name = "lru";
	bool write_back = true;       // false => write-through
	bool write_allocate = true;
	double hit_latency = 1.0, miss_penalty = 50.0;
	uint64_t seed = 0x9e3779b97f4a7c15ULL;
	std::string trace, out;
};

static uint64_t number(const std::string &s) {
	size_t n = 0;
	auto v = std::stoull(s, &n, 0);
	if (n != s.size()) throw std::runtime_error("invalid number: " + s);
	return v;
}

static bool power2(uint64_t x) { return x && !(x & (x - 1)); }

static void usage() {
	std::cerr
		<< "Usage: cache_sim --trace FILE --out PREFIX [options]\n"
		<< "  --capacity BYTES       total cache size (power of two)   [1024]\n"
		<< "  --line-size BYTES      block size (power of two)         [64]\n"
		<< "  --ways N               associativity                     [1]\n"
		<< "  --policy P             lru|fifo|plru|random              [lru]\n"
		<< "  --write-policy P       wb|wt (write-back|write-through)  [wb]\n"
		<< "  --write-allocate 0|1   allocate line on write miss       [1]\n"
		<< "  --hit-latency CYCLES   L1 hit latency for AMAT           [1]\n"
		<< "  --miss-penalty CYCLES  miss penalty for AMAT             [50]\n"
		<< "  --seed N               RNG seed for --policy random      [auto]\n"
		<< "AMAT = hit_latency + miss_rate * miss_penalty\n";
}

static Policy parse_policy(const std::string &s) {
	if (s == "lru") return Policy::LRU;
	if (s == "fifo") return Policy::FIFO;
	if (s == "plru") return Policy::PLRU;
	if (s == "random") return Policy::RANDOM;
	throw std::runtime_error("policy must be lru, fifo, plru or random");
}

static bool parse_bool(const std::string &s) {
	if (s == "1" || s == "yes" || s == "true") return true;
	if (s == "0" || s == "no" || s == "false") return false;
	throw std::runtime_error("expected 0|1|yes|no|true|false, got: " + s);
}

// --- tree-PLRU: ways must be a power of two ---------------------------------
struct PlruTree {
	size_t ways;
	std::vector<uint8_t> bits; // internal nodes, heap order

	explicit PlruTree(size_t w) : ways(w), bits(w - 1, 0) {}

	size_t victim() const {
		size_t idx = 0;
		size_t levels = 0;
		for (size_t w = 1; w < ways; w <<= 1) levels++;
		for (size_t level = 0; level < levels; ++level)
			idx = 2 * idx + 1 + bits[idx];
		return idx - (ways - 1);
	}

	void observe(size_t leaf) {
		size_t idx = leaf + (ways - 1);
		while (idx > 0) {
			size_t parent = (idx - 1) / 2;
			bits[parent] = (idx == 2 * parent + 1) ? 1 : 0; // point away
			idx = parent;
		}
	}
};

struct Cache {
	Config c;
	size_t sets;
	std::vector<std::vector<Line>> data;
	std::vector<PlruTree> plru;
	uint64_t seq = 0, hits = 0, misses = 0, writes = 0;
	uint64_t writebacks = 0, write_throughs = 0, fills = 0;

	explicit Cache(const Config &cfg) : c(cfg),
		sets(cfg.capacity / (cfg.line_size * cfg.ways)),
		data(sets, std::vector<Line>(cfg.ways)) {
		if (c.policy == Policy::PLRU)
			for (size_t s = 0; s < sets; ++s) plru.emplace_back(c.ways);
	}

	uint64_t next_random() { // xorshift64*
		c.seed ^= c.seed >> 12;
		c.seed ^= c.seed << 25;
		c.seed ^= c.seed >> 27;
		return c.seed * 0x2545F4914F6CDD1DULL;
	}

	size_t find_victim(size_t set) {
		auto &ways = data[set];
		for (size_t w = 0; w < c.ways; ++w)
			if (!ways[w].valid) return w; // always fill invalid first
		switch (c.policy) {
		case Policy::FIFO: {
			size_t v = 0;
			for (size_t w = 1; w < c.ways; ++w)
				if (ways[w].inserted < ways[v].inserted) v = w;
			return v;
		}
		case Policy::RANDOM:
			return static_cast<size_t>(next_random() % c.ways);
		case Policy::PLRU:
			return plru[set].victim();
		case Policy::LRU:
		default: {
			size_t v = 0;
			for (size_t w = 1; w < c.ways; ++w)
				if (ways[w].touched < ways[v].touched) v = w;
			return v;
		}
		}
	}

	// Returns hit?, and eviction info for the accesses CSV.
	void access(char op, uint64_t addr, bool &hit, bool &ev_valid, bool &ev_dirty,
	            uint64_t &ev_addr) {
		const uint64_t block = addr / c.line_size;
		const size_t set = block % sets;
		const uint64_t tag = block / sets;
		auto &ways = data[set];
		hit = false;
		ev_valid = ev_dirty = false;
		ev_addr = 0;
		seq++;
		const bool is_write = (op == 'W');
		if (is_write) writes++;

		size_t found = c.ways;
		for (size_t w = 0; w < c.ways; w++)
			if (ways[w].valid && ways[w].tag == tag) { found = w; break; }

		if (found < c.ways) {
			hit = true;
			hits++;
			ways[found].touched = seq;
			if (is_write) {
				if (c.write_back) ways[found].dirty = true;
				else write_throughs++; // write-through: memory updated now
			}
			if (c.policy == Policy::PLRU) plru[set].observe(found);
			return;
		}

		misses++;
		// Write miss with write-no-allocate: bypasses cache straight to memory.
		if (is_write && !c.write_allocate) {
			write_throughs++;
			return;
		}

		const size_t victim = find_victim(set);
		auto &v = ways[victim];
		ev_valid = v.valid;
		ev_dirty = v.valid && v.dirty;
		if (ev_dirty) writebacks++;
		if (ev_valid) ev_addr = (v.tag * sets + set) * c.line_size;

		v.valid = true;
		v.tag = tag;
		v.dirty = is_write && c.write_back; // write-through lines stay clean
		v.inserted = seq;
		v.touched = seq;
		fills++;
		if (is_write && !c.write_back) write_throughs++;
		if (c.policy == Policy::PLRU) plru[set].observe(victim);
	}
};

int main(int argc, char **argv) try {
	Config c;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto val = [&]() {
			if (++i >= argc) throw std::runtime_error("missing value for " + a);
			return std::string(argv[i]);
		};
		if (a == "--trace") c.trace = val();
		else if (a == "--out") c.out = val();
		else if (a == "--capacity") c.capacity = number(val());
		else if (a == "--line-size") c.line_size = number(val());
		else if (a == "--ways") c.ways = number(val());
		else if (a == "--policy") { c.policy_name = val(); c.policy = parse_policy(c.policy_name); }
		else if (a == "--write-policy") {
			std::string w = val();
			if (w == "wb" || w == "write-back") c.write_back = true;
			else if (w == "wt" || w == "write-through") c.write_back = false;
			else throw std::runtime_error("write policy must be wb or wt");
		}
		else if (a == "--write-allocate") c.write_allocate = parse_bool(val());
		else if (a == "--hit-latency") c.hit_latency = std::stod(val());
		else if (a == "--miss-penalty") c.miss_penalty = std::stod(val());
		else if (a == "--seed") c.seed = number(val());
		else if (a == "--help") { usage(); return 0; }
		else throw std::runtime_error("unknown option: " + a);
	}
	if (c.trace.empty() || c.out.empty()) { usage(); return 2; }

	if (!power2(c.capacity) || !power2(c.line_size) || c.line_size > c.capacity ||
	    c.ways == 0 || c.capacity % (c.line_size * c.ways) != 0 ||
	    !power2(c.capacity / (c.line_size * c.ways)))
		throw std::runtime_error(
			"capacity, line size and number of sets must form valid powers of two; "
			"ways must divide line count");
	if (c.policy == Policy::PLRU && !power2(c.ways))
		throw std::runtime_error("plru requires a power-of-two number of ways");
	if (c.hit_latency <= 0 || c.miss_penalty < 0)
		throw std::runtime_error("hit-latency must be > 0 and miss-penalty >= 0");

	Cache cache(c);
	std::ifstream in(c.trace);
	if (!in) throw std::runtime_error("cannot open trace: " + c.trace);
	std::ofstream access(c.out + "_accesses.csv"), summary(c.out + "_summary.csv");
	if (!access || !summary) throw std::runtime_error("cannot create output files");
	access << "sequence,op,address,set,tag,hit,evicted_valid,evicted_dirty,evicted_address\n";

	std::string line;
	while (std::getline(in, line)) {
		auto hash = line.find('#');
		if (hash != std::string::npos) line.resize(hash);
		std::istringstream ss(line);
		std::string op, addr_s, extra;
		if (!(ss >> op)) continue;
		if (!(ss >> addr_s) || (ss >> extra))
			throw std::runtime_error("bad trace line " + std::to_string(cache.seq + 1));
		if (op != "R" && op != "W")
			throw std::runtime_error("operation must be R or W at trace line " +
			                         std::to_string(cache.seq + 1));
		bool hit, ev_valid, ev_dirty;
		uint64_t ev_addr;
		const uint64_t addr = number(addr_s);
		cache.access(op[0], addr, hit, ev_valid, ev_dirty, ev_addr);
		const uint64_t block = addr / c.line_size;
		access << cache.seq << ',' << op << ",0x" << std::hex << addr << std::dec
		       << ',' << block % cache.sets << ",0x" << std::hex << block / cache.sets
		       << std::dec << ',' << (hit ? 1 : 0) << ',' << (ev_valid ? 1 : 0)
		       << ',' << (ev_dirty ? 1 : 0) << ",0x" << std::hex << ev_addr
		       << std::dec << '\n';
	}

	const double miss_rate = cache.seq ? double(cache.misses) / cache.seq : 0.0;
	const double hit_rate = cache.seq ? double(cache.hits) / cache.seq : 0.0;
	const double amat = c.hit_latency + miss_rate * c.miss_penalty;

	summary << "metric,value\n"
	        << "accesses," << cache.seq << "\n"
	        << "hits," << cache.hits << "\n"
	        << "misses," << cache.misses << "\n"
	        << "hit_rate," << std::setprecision(10) << hit_rate << "\n"
	        << "miss_rate," << miss_rate << "\n"
	        << "writes," << cache.writes << "\n"
	        << "writebacks," << cache.writebacks << "\n"
	        << "write_throughs," << cache.write_throughs << "\n"
	        << "fills," << cache.fills << "\n"
	        << "amat," << amat << "\n"
	        << "hit_latency," << c.hit_latency << "\n"
	        << "miss_penalty," << c.miss_penalty << "\n"
	        << "sets," << cache.sets << "\n"
	        << "ways," << c.ways << "\n"
	        << "capacity_bytes," << c.capacity << "\n"
	        << "line_size_bytes," << c.line_size << "\n"
	        << "policy," << c.policy_name << "\n"
	        << "write_policy," << (c.write_back ? "wb" : "wt") << "\n"
	        << "write_allocate," << (c.write_allocate ? 1 : 0) << "\n"
	        << "seed," << c.seed << "\n";

	std::cout << "Completed " << cache.seq << " accesses: " << cache.hits
	          << " hits, " << cache.misses << " misses (" << std::fixed
	          << std::setprecision(1) << hit_rate * 100 << "% hit rate), AMAT="
	          << std::setprecision(3) << amat << " cycles.\nWrote " << c.out
	          << "_summary.csv and " << c.out << "_accesses.csv\n";
	return 0;
} catch (const std::exception &e) {
	std::cerr << "error: " << e.what() << '\n';
	return 1;
}
