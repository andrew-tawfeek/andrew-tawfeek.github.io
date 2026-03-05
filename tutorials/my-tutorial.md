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

This below should run:

```python {interactive}
from pyscript import display
import math
display(f"Pi is approximately {math.pi:.6f}")
display("Hello")
display(f"2**2 == 1? {2**2 == 1}")
```
