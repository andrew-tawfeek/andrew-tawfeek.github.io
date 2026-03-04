/**
 * tutorial-renderer.js — Renders markdown tutorials with math and interactive Python
 *
 * Pipeline:
 * 1. Read ?slug= from URL
 * 2. Fetch tutorials/{slug}.md
 * 3. Parse YAML front matter (title, date, tags)
 * 4. Detect ```python {interactive} blocks → prepare PyScript loading
 * 5. Replace interactive blocks with placeholder divs
 * 6. marked.parse() on remaining markdown
 * 7. Re-insert PyScript <script type="py"> blocks at placeholders
 * 8. Inject into #tutorial-content
 * 9. Run KaTeX renderMathInElement()
 * 10. Run hljs.highlightElement() on non-interactive code blocks
 */

(function () {
  'use strict';

  var container = document.getElementById('tutorial-content');
  if (!container) return;

  // =========================================================================
  // Get slug from URL
  // =========================================================================

  var params = new URLSearchParams(window.location.search);
  var slug = params.get('slug');

  if (!slug) {
    container.innerHTML = '<div class="tutorial-error">No tutorial specified. ' +
      '<a href="../tutorials.html">Browse tutorials &rarr;</a></div>';
    return;
  }

  // =========================================================================
  // YAML front matter parser (simple key: value)
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

          // Handle arrays: [item1, item2]
          if (val.charAt(0) === '[' && val.charAt(val.length - 1) === ']') {
            val = val.substring(1, val.length - 1).split(',').map(function (s) {
              return s.trim().replace(/^["']|["']$/g, '');
            });
          } else {
            // Strip quotes
            val = val.replace(/^["']|["']$/g, '');
          }
          meta[key] = val;
        });
      }
    }

    return { meta: meta, body: body };
  }

  // =========================================================================
  // Interactive block extraction
  // =========================================================================

  function extractInteractiveBlocks(markdown) {
    var blocks = [];
    var counter = 0;
    var pattern = /```python\s*\{interactive\}\s*\n([\s\S]*?)```/g;

    var processed = markdown.replace(pattern, function (match, code) {
      var id = '__interactive_' + counter + '__';
      blocks.push({ id: id, code: code.trim() });
      counter++;
      return '<div id="' + id + '" class="interactive-block">' +
        '<div class="interactive-label">Interactive Python (PyScript)</div>' +
        '<div class="pyscript-output"></div></div>';
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

      // Extract interactive blocks before marked parses them
      var extracted = extractInteractiveBlocks(parsed.body);
      var hasInteractive = extracted.blocks.length > 0;

      // Configure marked
      if (window.marked) {
        marked.setOptions({
          gfm: true,
          breaks: false
        });
      }

      // Build header
      var headerHTML = '';
      if (meta.title) {
        headerHTML += '<h1>' + meta.title + '</h1>';
        document.title = meta.title + ' — Andrew R. Tawfeek';
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

      // Render markdown
      var bodyHTML = window.marked ? marked.parse(extracted.markdown) : extracted.markdown;
      container.innerHTML = headerHTML + bodyHTML;

      // Insert PyScript blocks
      if (hasInteractive) {
        extracted.blocks.forEach(function (block) {
          var el = document.getElementById(block.id);
          if (!el) return;
          var outputDiv = el.querySelector('.pyscript-output');
          if (outputDiv) {
            var script = document.createElement('script');
            script.type = 'py';
            script.setAttribute('output', block.id + '-out');
            outputDiv.id = block.id + '-out';
            script.textContent = block.code;
            el.appendChild(script);
          }
        });

        // Load PyScript dynamically
        if (!document.querySelector('script[src*="pyscript"]')) {
          var pyScript = document.createElement('script');
          pyScript.src = 'https://pyscript.net/releases/2024.1.1/core.js';
          pyScript.type = 'module';
          document.head.appendChild(pyScript);
        }
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
          // Skip code inside interactive blocks
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
