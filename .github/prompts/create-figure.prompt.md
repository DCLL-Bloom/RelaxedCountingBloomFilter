---
description: "Create a publication-quality plot from experimental data"
agent: "visualizer"
argument-hint: "Data file and plot type (e.g., data/throughput.csv, line plot)"
---

Create a publication-quality figure:

**Input**: {{input}}

Requirements:
- Read data from CSV in `data/`
- Save PDF to `figures/` (also PNG for drafts)
- Single-column width (3.5 inches), serif font, 10pt
- Grayscale-safe colors with distinct markers
- Axis labels with units, grid with low alpha
- Return `\includegraphics` LaTeX snippet
