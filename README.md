# andrew-tawfeek.github.io

Personal website for Andrew R. Tawfeek — mathematician and ML researcher.

## Project Structure

```
/
├── index.html              # Home page (bio, news, publications, interests)
├── projects.html           # Project showcase
├── tutorials.html          # Tutorial listing
├── cv.html                 # CV / resume
├── content/                # Data files (edit these to update content)
│   ├── about.json          # Bio paragraphs (array of HTML strings)
│   ├── news.json           # News items
│   ├── publications.json   # Publication list
│   ├── projects.json       # Project cards
│   ├── interests.json      # Research interest tags
│   └── tutorials.json      # Tutorial metadata
├── tutorials/              # Tutorial content
│   ├── template.html       # Shell page for rendering any tutorial
│   └── *.md                # Individual tutorial markdown files
├── assets/
│   ├── css/style.css       # All styles (TeX Gyre Pagella font, light/dark theme)
│   ├── js/
│   │   ├── main.js         # Theme toggle, nav, smooth scroll
│   │   ├── content-loader.js   # Fetches JSON → renders into pages
│   │   └── tutorial-renderer.js # Renders markdown tutorials (KaTeX, hljs, PyScript)
│   └── img/                # Images
└── CLAUDE.md               # AI assistant instructions
```

## Adding Content

### About / Bio

Edit `content/about.json` — an array of HTML paragraph strings:

```json
[
  "First paragraph with <a href=\"...\">links</a> supported.",
  "Second paragraph.",
  "Third paragraph."
]
```

### News

Edit `content/news.json`. Each entry:

```json
{
  "date": "Mar 2026",
  "datetime": "2026-03",
  "text": "HTML content here — supports <a>, <em>, etc."
}
```

### Publications

Edit `content/publications.json`. Each entry:

```json
{
  "title": "Paper Title",
  "authors": "First Author, Andrew R. Tawfeek",
  "venue": "Journal Name, Year",
  "year": 2025,
  "url": "https://...",
  "status": "PMLR 2025",
  "statusClass": "accepted",
  "links": [
    { "label": "arXiv", "url": "https://arxiv.org/abs/..." },
    { "label": "PDF", "url": "https://..." }
  ]
}
```

"Andrew R. Tawfeek" is auto-bolded in the authors list. Status classes: `in-prep`, `under-revision`, `accepted`.

### Projects

Edit `content/projects.json`. Each entry:

```json
{
  "id": "project-id",
  "name": "Project Name",
  "description": "Description text.",
  "tech": ["Python", "PyTorch"],
  "links": [
    { "type": "demo", "url": "https://...", "label": "Live Demo" },
    { "type": "github", "url": "https://...", "label": "Code" },
    { "type": "paper", "url": "https://...", "label": "Paper" }
  ],
  "thumbIcon": "network"
}
```

Link types: `demo` (primary button), `github`, `paper` (secondary buttons).
Thumb icons: `network`, `knot`, `simplex`.

### Tutorials

1. Add metadata to `content/tutorials.json`:

```json
{
  "slug": "my-tutorial",
  "title": "My Tutorial Title",
  "date": "March 2026",
  "datetime": "2026-03",
  "description": "Short description.",
  "tags": ["Topic1", "Topic2"],
  "published": true
}
```

2. Create `tutorials/my-tutorial.md` with front matter:

````markdown
---
title: My Tutorial Title
date: March 2026
tags: [Topic1, Topic2]
---

## Section 1

Regular markdown content. Inline math: $x^2 + y^2 = z^2$.

Display math:

$$\int_0^\infty e^{-x^2} dx = \frac{\sqrt{\pi}}{2}$$

Code blocks with syntax highlighting:

```python
def hello():
    print("Hello, world!")
```
````

### Research Interests

Edit `content/interests.json` — a flat array of strings:

```json
["Tropical Geometry", "Machine Learning", "TDA"]
```

## Writing Interactive Python (PyScript)

Interactive Python blocks run in the browser via [PyScript](https://pyscript.net/) / [Pyodide](https://pyodide.org/). They are loaded on demand only when a tutorial contains them.

### Basics

Use ` ```python {interactive} ` fencing. Always use `display()` for output — `print()` goes to the browser console only.

```python {interactive}
from pyscript import display
import math
display(f"Pi is approximately {math.pi:.6f}")
```

### Package installation

External packages are **auto-detected** from `import` statements:

- **Pyodide built-ins** (numpy, matplotlib, pandas, scipy, sympy, networkx, scikit-learn) are installed via `pyodide_js.loadPackage()` — fast, cached by the browser after first load.
- **PyPI packages** (plotly, etc.) are installed via `micropip.install()` — works for any pure-Python package on PyPI.

No manual configuration needed. First load downloads packages; subsequent visits use the browser cache.

### Static plots (matplotlib)

Use the `agg` backend and `display(fig)` — never `plt.show()`.

```python {interactive}
from pyscript import display
import matplotlib
matplotlib.use('agg')
from matplotlib import pyplot as plt
import numpy as np

fig, ax = plt.subplots()
ax.plot([1, 2, 3], [1, 4, 9])
display(fig)
plt.close(fig)
```

### Interactive plots (Plotly)

For pan/zoom/hover interactivity, use Plotly. The renderer auto-loads the Plotly.js CDN when it detects plotly imports. Render plots by appending a div to the block container and calling `Plotly.newPlot()`:

```python {interactive}
from js import document, Plotly as PlotlyJS, Object
from pyodide.ffi import to_js
import plotly.graph_objects as go

fig = go.Figure(data=go.Scatter(x=[1, 2, 3], y=[1, 4, 2]))

# __block_id__ is auto-injected by the renderer — always available
plot_div = document.createElement('div')
document.getElementById(__block_id__).appendChild(plot_div)

fig_dict = fig.to_dict()
PlotlyJS.newPlot(
    plot_div,
    to_js(fig_dict['data'], dict_converter=Object.fromEntries),
    to_js(fig_dict['layout'], dict_converter=Object.fromEntries),
    to_js({"displayModeBar": False}, dict_converter=Object.fromEntries)
)
```

**Key points:**
- Do NOT use `display(fig.to_html(...))` — this dumps the entire plotly.js library as raw text.
- Use `document.getElementById(__block_id__).appendChild(div)` to inject DOM elements into the block.
- Set `displayModeBar: False` to hide the toolbar, or `True` to show it.
- `__block_id__` is a Python variable automatically set by the renderer for each interactive block.

### Execution model

- Multiple interactive blocks execute **sequentially** (each waits for the previous to finish).
- A loading spinner shows "Loading Python environment..." → "Installing packages & running..." while blocks execute.
- Each block has access to `__block_id__` (its container div ID) for direct DOM manipulation.

### Choosing between matplotlib and Plotly

| Feature | matplotlib (`agg`) | Plotly |
|---|---|---|
| Output type | Static image | Interactive HTML |
| Pan/zoom | No | Yes |
| Hover tooltips | No | Yes |
| Package size | ~8 MB (cached) | ~3 MB via micropip + CDN JS |
| Best for | Publication-quality static figures | Exploratory/interactive data viz |

## Local Development

```bash
cd andrew-tawfeek.github.io
python -m http.server 8080
# Open http://localhost:8080
```

Use port 8080 (port 8000 may conflict with other local services). Content is loaded via `fetch()`, so a local server is required (file:// won't work).

## Tech Stack

- Pure HTML/CSS/JS — no build tools, no frameworks
- **Font**: TeX Gyre Pagella (Palatino) for body, JetBrains Mono for code
- **Theme**: Light mode default, dark/light toggle
- Client-side JSON fetching for content
- [marked.js](https://marked.js.org/) for markdown rendering
- [KaTeX](https://katex.org/) for math typesetting (Euler-style math)
- [highlight.js](https://highlightjs.org/) for syntax highlighting (github / github-dark themes, toggled with site theme)
- [PyScript](https://pyscript.net/) for interactive Python (loaded on demand)
- [Plotly.js](https://plotly.com/javascript/) for interactive plots (CDN, loaded on demand)
- Hosted on GitHub Pages
