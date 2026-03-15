---
description: "Run a benchmark experiment and collect data"
agent: "coder"
argument-hint: "Experiment description (e.g., throughput vs threads)"
---

Implement and run the following experiment:

**Experiment**: {{input}}

Requirements:
- Code in `src/` directory
- Output CSV to `data/` with columns: `threads,ops_per_sec,fpr,latency_ns` (as applicable)
- Include warmup phase and multiple iterations
- Seed RNG for reproducibility
- Document hardware assumptions in comments
- Print summary statistics to stdout
