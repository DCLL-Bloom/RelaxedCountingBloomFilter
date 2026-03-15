# Relaxed Concurrent Counting Bloom Filter — Research Project

## Domain
Research paper on relaxed concurrent counting bloom filters. Combines probabilistic data structures, concurrent programming, and relaxed consistency semantics.

## Key Concepts
- Counting Bloom Filters (CBF): support deletions via counters instead of bits
- Relaxed consistency: trades strict linearizability for performance (bounded staleness)
- Lock-free / wait-free concurrent access patterns
- False positive rate (FPR) analysis under concurrent workloads

## Repository Structure
- `paper/` — LaTeX source, figures, bibliography
- `src/` — Implementation code (benchmarks, data structures)
- `data/` — Experimental results, raw benchmark output
- `figures/` — Generated plots and visualizations
- `references/` — Downloaded papers, notes on related work

## Conventions
- Paper uses LaTeX with BibTeX citations
- Code benchmarks in C/C++ or Rust (lock-free primitives)
- Plots generated with Python (matplotlib/seaborn)
- All claims must be backed by citations or experimental data
