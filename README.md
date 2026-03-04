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
│   ├── news.json           # News items
│   ├── publications.json   # Publication list
│   ├── projects.json       # Project cards
│   ├── interests.json      # Research interest tags
│   └── tutorials.json      # Tutorial metadata
├── tutorials/              # Tutorial content
│   ├── template.html       # Shell page for rendering any tutorial
│   └── *.md                # Individual tutorial markdown files
├── assets/
│   ├── css/style.css       # All styles
│   ├── js/
│   │   ├── main.js         # Theme toggle, nav, smooth scroll
│   │   ├── content-loader.js   # Fetches JSON → renders into pages
│   │   └── tutorial-renderer.js # Renders markdown tutorials
│   └── img/                # Images
└── CLAUDE.md               # AI assistant instructions
```

## Adding Content

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

```markdown
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

Interactive Python (runs in browser via PyScript):

```python {interactive}
import math
print(f"Pi is approximately {math.pi:.6f}")
```

### Research Interests

Edit `content/interests.json` — a flat array of strings:

```json
["Tropical Geometry", "Machine Learning", "TDA"]
```

## Local Development

```bash
cd andrew-tawfeek.github.io
python -m http.server 8080
# Open http://localhost:8080
```

Content is loaded via `fetch()`, so a local server is required (file:// won't work for JSON loading).

## Tech Stack

- Pure HTML/CSS/JS — no build tools, no frameworks
- Client-side JSON fetching for content
- [marked.js](https://marked.js.org/) for markdown rendering
- [KaTeX](https://katex.org/) for math typesetting
- [highlight.js](https://highlightjs.org/) for syntax highlighting
- [PyScript](https://pyscript.net/) for interactive Python (loaded on demand)
- Hosted on GitHub Pages
