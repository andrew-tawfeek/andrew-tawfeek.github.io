/**
 * tutorial-renderer.js — Renders markdown tutorials with math and interactive Python
 *
 * Pipeline:
 * 1. Read ?slug= from URL, fetch tutorials/{slug}.md
 * 2. Parse YAML front matter
 * 3. Extract ```python {interactive} blocks, replace with text placeholders
 * 4. marked.parse() the remaining markdown
 * 5. Set innerHTML, then inject PyScript elements at placeholder locations
 * 6. Load PyScript core.js (which discovers <script type="py"> via MutationObserver)
 * 7. Run KaTeX + highlight.js
 */

(function () {
  'use strict';

  var container = document.getElementById('tutorial-content');
  if (!container) return;

  // =========================================================================
  // highlight.js theme toggling (github-dark vs github)
  // =========================================================================

  function syncHljsTheme() {
    var theme = document.documentElement.getAttribute('data-theme') || 'light';
    var dark = document.getElementById('hljs-dark');
    var light = document.getElementById('hljs-light');
    if (dark && light) {
      dark.disabled = (theme === 'light');
      light.disabled = (theme !== 'light');
    }
  }

  syncHljsTheme();

  // Watch for theme toggle changes
  new MutationObserver(function () { syncHljsTheme(); })
    .observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });

  var params = new URLSearchParams(window.location.search);
  var slug = params.get('slug');

  if (!slug) {
    container.innerHTML = '<div class="tutorial-error">No tutorial specified. ' +
      '<a href="../tutorials.html">Browse tutorials &rarr;</a></div>';
    return;
  }

  // =========================================================================
  // YAML front matter parser
  // =========================================================================

  function parseFrontMatter(text) {
    var meta = {};
    var body = text;

    if (text.substring(0, 3) === '---') {
      var end = text.indexOf('\n---', 3);
      if (end !== -1) {
        var yamlBlock = text.substring(3, end).trim();
        body = text.substring(end + 4).trim();

        yamlBlock.split('\n').forEach(function (line) {
          var colonIdx = line.indexOf(':');
          if (colonIdx === -1) return;
          var key = line.substring(0, colonIdx).trim();
          var val = line.substring(colonIdx + 1).trim();

          if (val.charAt(0) === '[' && val.charAt(val.length - 1) === ']') {
            val = val.substring(1, val.length - 1).split(',').map(function (s) {
              return s.trim().replace(/^["']|["']$/g, '');
            });
          } else {
            val = val.replace(/^["']|["']$/g, '');
          }
          meta[key] = val;
        });
      }
    }

    return { meta: meta, body: body };
  }

  // =========================================================================
  // Interactive block extraction — replace with simple div placeholders
  // =========================================================================

  function extractInteractiveBlocks(markdown) {
    var blocks = [];
    var counter = 0;
    var pattern = /```python\s*\{interactive\}\s*\n([\s\S]*?)```/g;

    var processed = markdown.replace(pattern, function (match, code) {
      var id = 'pyscript-block-' + counter;
      blocks.push({ id: id, code: code.trim() });
      counter++;
      // Return a simple HTML block that marked will pass through untouched
      return '\n\n<div id="' + id + '" class="interactive-block">' +
        '<div class="interactive-label">Interactive Python (PyScript)</div>' +
        '<div id="' + id + '-out" class="pyscript-output"></div>' +
        '</div>\n\n';
    });

    return { markdown: processed, blocks: blocks };
  }

  // =========================================================================
  // Fetch and render
  // =========================================================================

  fetch('../tutorials/' + slug + '.md')
    .then(function (res) {
      if (!res.ok) throw new Error('Tutorial not found');
      return res.text();
    })
    .then(function (text) {
      var parsed = parseFrontMatter(text);
      var meta = parsed.meta;
      var extracted = extractInteractiveBlocks(parsed.body);

      // Configure marked
      if (window.marked) {
        marked.setOptions({ gfm: true, breaks: false });
      }

      // Build header
      var headerHTML = '';
      if (meta.title) {
        headerHTML += '<h1>' + meta.title + '</h1>';
        document.title = meta.title + ' \u2014 Andrew R. Tawfeek';
      }

      var metaLine = '';
      if (meta.date) metaLine += meta.date;
      if (metaLine) {
        headerHTML += '<div class="tutorial-header-meta">' + metaLine;
        if (meta.tags && Array.isArray(meta.tags)) {
          headerHTML += '<div class="tutorial-header-tags">';
          meta.tags.forEach(function (tag) {
            headerHTML += '<span class="tutorial-tag">' + tag + '</span>';
          });
          headerHTML += '</div>';
        }
        headerHTML += '</div>';
      }

      // Render markdown to HTML
      var bodyHTML = window.marked ? marked.parse(extracted.markdown) : extracted.markdown;
      container.innerHTML = headerHTML + bodyHTML;

      // Load PyScript, wait for it to initialize, then inject code blocks.
      if (extracted.blocks.length > 0) {
        // Map common import names to Pyodide package names
        var PACKAGE_MAP = {
          'numpy': 'numpy',
          'np': 'numpy',
          'matplotlib': 'matplotlib',
          'plt': 'matplotlib',
          'pandas': 'pandas',
          'pd': 'pandas',
          'scipy': 'scipy',
          'sklearn': 'scikit-learn',
          'sympy': 'sympy',
          'networkx': 'networkx',
          'plotly': 'plotly'
        };

        // Show loading indicators on all blocks
        extracted.blocks.forEach(function (block) {
          var el = document.getElementById(block.id);
          if (el) {
            var loader = document.createElement('div');
            loader.className = 'pyscript-loading';
            loader.id = block.id + '-loader';
            loader.textContent = 'Loading Python environment\u2026';
            el.appendChild(loader);
          }
        });

        // Pre-load Plotly.js CDN if any block imports plotly
        var needsPlotlyJS = extracted.blocks.some(function (b) {
          return /(?:^|\n)\s*(?:import|from)\s+plotly/.test(b.code);
        });
        if (needsPlotlyJS && !window.Plotly && !document.querySelector('script[src*="plotly"]')) {
          var plotlyScript = document.createElement('script');
          plotlyScript.src = 'https://cdn.plot.ly/plotly-2.35.2.min.js';
          document.head.appendChild(plotlyScript);
        }

        // Packages available via pyodide_js.loadPackage (built into Pyodide CDN)
        var PYODIDE_PACKAGES = {
          'numpy': true, 'matplotlib': true, 'pandas': true,
          'scipy': true, 'sympy': true, 'networkx': true,
          'scikit-learn': true
        };

        // For each block, detect needed packages and prepend install code
        function getBlockCode(block) {
          var pyodidePackages = {};
          var micropipPackages = {};
          var importPattern = /(?:^|\n)\s*(?:import|from)\s+(\w+)/g;
          var im;
          while ((im = importPattern.exec(block.code)) !== null) {
            var pkg = PACKAGE_MAP[im[1]];
            if (pkg) {
              if (PYODIDE_PACKAGES[pkg]) {
                pyodidePackages[pkg] = true;
              } else {
                micropipPackages[pkg] = true;
              }
            }
          }

          var preamble = '';
          var pyodideList = Object.keys(pyodidePackages);
          var micropipList = Object.keys(micropipPackages);

          if (pyodideList.length > 0) {
            preamble += 'import pyodide_js\n_ = await pyodide_js.loadPackage(' +
              JSON.stringify(pyodideList) + ')\n';
          }
          if (micropipList.length > 0) {
            // micropip itself must be loaded via pyodide first
            if (pyodideList.length === 0) {
              preamble += 'import pyodide_js\n';
            }
            preamble += '_ = await pyodide_js.loadPackage("micropip")\n' +
              'import micropip\nawait micropip.install(' +
              JSON.stringify(micropipList) + ')\n';
          }

          // Append done sentinel — marks block as finished after all code runs
          var sentinel = '\nfrom js import document as _doc\n' +
            '_doc.getElementById("' + block.id + '").setAttribute("data-done", "true")\n';

          return preamble + block.code + sentinel;
        }

        // Inject blocks sequentially — wait for each to finish before
        // injecting the next, so display() output targets correctly.
        function injectPyBlocks() {
          var i = 0;
          function injectNext() {
            if (i >= extracted.blocks.length) return;
            var block = extracted.blocks[i];
            i++;
            var el = document.getElementById(block.id);
            if (!el) { injectNext(); return; }

            // Update loader text for this block
            var loader = document.getElementById(block.id + '-loader');
            var code = getBlockCode(block).trim();
            if (loader) {
              var hasPackages = code.indexOf('pyodide_js.loadPackage') !== -1;
              loader.textContent = hasPackages
                ? 'Installing packages & running\u2026'
                : 'Running\u2026';
            }

            var scriptEl = document.createElement('script');
            scriptEl.setAttribute('type', 'py');
            scriptEl.setAttribute('output', block.id + '-out');
            scriptEl.textContent = code;
            el.appendChild(scriptEl);

            // Poll for done sentinel — the code appends data-done="true" when finished
            var pollCount = 0;
            var pollDone = setInterval(function () {
              pollCount++;
              var isDone = el.getAttribute('data-done') === 'true';
              if (isDone || pollCount > 600) {
                clearInterval(pollDone);
                // Remove the loading indicator
                var ldr = document.getElementById(block.id + '-loader');
                if (ldr) ldr.remove();
                injectNext();
              }
            }, 100);
          }
          injectNext();
        }

        if (!document.querySelector('link[href*="pyscript"]')) {
          var link = document.createElement('link');
          link.rel = 'stylesheet';
          link.href = 'https://pyscript.net/releases/2024.11.1/core.css';
          document.head.appendChild(link);
        }

        if (!document.querySelector('script[src*="pyscript"]')) {
          var ps = document.createElement('script');
          ps.setAttribute('type', 'module');
          ps.setAttribute('src', 'https://pyscript.net/releases/2024.11.1/core.js');
          document.head.appendChild(ps);
        }

        // Poll for PyScript readiness, then inject blocks.
        var attempts = 0;
        var poller = setInterval(function () {
          attempts++;
          if (customElements.get('py-script') || attempts > 100) {
            clearInterval(poller);
            if (customElements.get('py-script')) {
              injectPyBlocks();
            } else {
              // Timeout — remove all loaders with error message
              extracted.blocks.forEach(function (b) {
                var ldr = document.getElementById(b.id + '-loader');
                if (ldr) ldr.textContent = 'Failed to load Python environment.';
              });
            }
          }
        }, 100);
      }

      // KaTeX: render math
      if (window.renderMathInElement) {
        renderMathInElement(container, {
          delimiters: [
            { left: '$$', right: '$$', display: true },
            { left: '$', right: '$', display: false },
            { left: '\\[', right: '\\]', display: true },
            { left: '\\(', right: '\\)', display: false }
          ],
          throwOnError: false
        });
      }

      // highlight.js: syntax-highlight non-interactive code blocks
      if (window.hljs) {
        container.querySelectorAll('pre code').forEach(function (block) {
          if (!block.closest('.interactive-block')) {
            hljs.highlightElement(block);
          }
        });
      }
    })
    .catch(function (err) {
      container.innerHTML = '<div class="tutorial-error">' +
        '<p>Could not load tutorial: ' + err.message + '</p>' +
        '<p><a href="../tutorials.html">&larr; Back to tutorials</a></p></div>';
    });

})();
