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
some text in between

```python {interactive}
from pyscript import display
from matplotlib import pyplot as plt
import matplotlib
matplotlib.use('agg')
import numpy as np

# lets generate gbm

T = 1.0
N = 100
dt = T/N
mu = 0.1
sigma = 0.2
S0 = 100
t = np.linspace(0, T, N)
W = np.random.standard_normal(size=N)
W = np.cumsum(W)*np.sqrt(dt) # standard brownian motion
X = (mu-0.5*sigma**2)*t + sigma*W
S = S0*np.exp(X) # geometric brownian motion
fig, ax = plt.subplots()
ax.plot(t, S)
ax.set_title("Geometric Brownian Motion")
ax.set_xlabel("Time")
ax.set_ylabel("Price")
display(fig)
plt.close(fig)
```
