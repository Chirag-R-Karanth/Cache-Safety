#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

struct Line { bool valid=false, dirty=false; uint64_t tag=0, inserted=0, touched=0; };
struct Config { uint64_t capacity=1024, line_size=64; size_t ways=1; std::string policy="lru"; };
static uint64_t number(const std::string& s) { size_t n=0; auto v=std::stoull(s,&n,0); if(n!=s.size()) throw std::runtime_error("invalid number: "+s); return v; }
static void usage() { std::cerr << "Usage: cache_sim --trace FILE --out PREFIX [--capacity BYTES] [--line-size BYTES] [--ways N] [--policy lru|fifo]\nTrace format: one access per line: R 0xADDR or W 0xADDR; # comments allowed.\n"; }
int main(int argc,char**argv) try {
  Config c; std::string trace,out;
  for(int i=1;i<argc;i++){ std::string a=argv[i]; auto val=[&](){if(++i>=argc) throw std::runtime_error("missing value for "+a);return std::string(argv[i]);};
    if(a=="--trace") trace=val(); else if(a=="--out") out=val(); else if(a=="--capacity") c.capacity=number(val()); else if(a=="--line-size") c.line_size=number(val()); else if(a=="--ways") c.ways=number(val()); else if(a=="--policy") c.policy=val(); else if(a=="--help"){usage();return 0;} else throw std::runtime_error("unknown option: "+a);
  }
  if(trace.empty()||out.empty()) {usage();return 2;}
  auto power2=[](uint64_t x){return x && !(x&(x-1));};
  if(!power2(c.capacity)||!power2(c.line_size)||c.line_size>c.capacity||c.ways==0||c.capacity%(c.line_size*c.ways)!=0||!power2(c.capacity/(c.line_size*c.ways))) throw std::runtime_error("capacity, line size and number of sets must form valid powers of two; ways must divide line count");
  if(c.policy!="lru"&&c.policy!="fifo") throw std::runtime_error("policy must be lru or fifo");
  const size_t sets=c.capacity/(c.line_size*c.ways); std::vector<std::vector<Line>> cache(sets,std::vector<Line>(c.ways));
  std::ifstream in(trace); if(!in) throw std::runtime_error("cannot open trace: "+trace);
  std::ofstream access(out+"_accesses.csv"), summary(out+"_summary.csv"); if(!access||!summary) throw std::runtime_error("cannot create output files");
  access<<"sequence,op,address,set,tag,hit,evicted_valid,evicted_dirty,evicted_address\n";
  uint64_t hits=0,misses=0,writes=0,writebacks=0,seq=0; std::string line;
  while(std::getline(in,line)) { auto hash=line.find('#'); if(hash!=std::string::npos) line.resize(hash); std::istringstream ss(line); std::string op,addr_s,extra; if(!(ss>>op)) continue; if(!(ss>>addr_s)||(ss>>extra)) throw std::runtime_error("bad trace line "+std::to_string(seq+1));
    if(op!="R"&&op!="W") throw std::runtime_error("operation must be R or W at trace line "+std::to_string(seq+1));
    uint64_t addr=number(addr_s), block=addr/c.line_size, set=block%sets, tag=block/sets; if(op=="W") writes++; seq++;
    auto& ways=cache[set]; size_t found=c.ways; for(size_t w=0;w<c.ways;w++) if(ways[w].valid&&ways[w].tag==tag){found=w;break;}
    bool hit=found<c.ways, evvalid=false, evdirty=false; uint64_t evaddr=0;
    if(hit){hits++; ways[found].touched=seq; if(op=="W") ways[found].dirty=true;}
    else {misses++; size_t victim=c.ways; for(size_t w=0;w<c.ways;w++) if(!ways[w].valid){victim=w;break;}
      if(victim==c.ways){victim=0; for(size_t w=1;w<c.ways;w++){uint64_t lhs=c.policy=="lru"?ways[w].touched:ways[w].inserted; uint64_t rhs=c.policy=="lru"?ways[victim].touched:ways[victim].inserted; if(lhs<rhs)victim=w;}}
      auto& v=ways[victim]; evvalid=v.valid; evdirty=v.valid&&v.dirty; if(evdirty)writebacks++; if(evvalid)evaddr=((v.tag*sets+set)*c.line_size);
      v.valid=true;v.tag=tag;v.dirty=(op=="W");v.inserted=seq;v.touched=seq;
    }
    access<<seq<<','<<op<<",0x"<<std::hex<<addr<<std::dec<<','<<set<<",0x"<<std::hex<<tag<<std::dec<<','<<(hit?1:0)<<','<<(evvalid?1:0)<<','<<(evdirty?1:0)<<",0x"<<std::hex<<evaddr<<std::dec<<'\n';
  }
  double hitrate=seq?double(hits)/seq:0.0, missrate=seq?double(misses)/seq:0.0;
  summary<<"metric,value\naccesses,"<<seq<<"\nhits,"<<hits<<"\nmisses,"<<misses<<"\nhit_rate,"<<std::setprecision(10)<<hitrate<<"\nmiss_rate,"<<missrate<<"\nwrites,"<<writes<<"\nwritebacks,"<<writebacks<<"\nsets,"<<sets<<"\nways,"<<c.ways<<"\ncapacity_bytes,"<<c.capacity<<"\nline_size_bytes,"<<c.line_size<<"\npolicy,"<<c.policy<<"\n";
  std::cout<<"Completed "<<seq<<" accesses: "<<hits<<" hits, "<<misses<<" misses ("<<std::fixed<<std::setprecision(1)<<hitrate*100<<"% hit rate).\nWrote "<<out<<"_summary.csv and "<<out<<"_accesses.csv\n";
  return 0;
} catch(const std::exception&e){std::cerr<<"error: "<<e.what()<<'\n';return 1;}
