---
description: "Draft a paper section from an outline or topic"
agent: "writer"
argument-hint: "Section name and key points to cover"
---

Draft the following paper section for our relaxed concurrent counting bloom filter paper.

**Section**: {{input}}

Requirements:
- LaTeX source ready for `paper/` directory
- Use `\cite{}` placeholders where citations are needed (mark with `% TODO: cite`)
- Include `\label{}` for cross-referencing
- Follow the paper's notation: $\mathcal{B}$ for bloom filter, $k$ hash functions, $m$ counters, $n$ elements
- Formal definitions in `definition` environments
- Keep it tight — no filler prose
