/**
 * content-loader.js — Data-driven content renderer
 * Fetches JSON data files and renders them into page containers.
 * Uses the same CSS classes as the original hardcoded markup.
 */

(function () {
  'use strict';

  // =========================================================================
  // SVG Icon Constants (used in project cards)
  // =========================================================================

  const ICONS = {
    externalLink: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 3a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v6a1 1 0 1 1-2 0V5.414l-9.293 9.293a1 1 0 0 1-1.414-1.414L18.586 4H15a1 1 0 0 1-1-1zM3 7a2 2 0 0 1 2-2h5a1 1 0 1 1 0 2H5v12h12v-5a1 1 0 1 1 2 0v5a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7z"/></svg>',
    github: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2C6.477 2 2 6.484 2 12.021c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.482 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.337c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.021C22 6.484 17.522 2 12 2z"/></svg>',
    document: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8l-6-6zm0 2l4 4h-4V4zM6 20V4h6v5a1 1 0 0 0 1 1h5v10H6z"/></svg>',
    // Project thumbnail icons
    thumb: {
      network: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="5" r="2"/><circle cx="19" cy="5" r="2"/><circle cx="5" cy="19" r="2"/><circle cx="19" cy="19" r="2"/><circle cx="12" cy="12" r="2.5"/><line x1="7" y1="5" x2="17" y2="5"/><line x1="7" y1="19" x2="17" y2="19"/><line x1="5" y1="7" x2="5" y2="17"/><line x1="19" y1="7" x2="19" y2="17"/><line x1="7" y1="7" x2="10" y2="10"/><line x1="17" y1="7" x2="14" y2="10"/><line x1="7" y1="17" x2="10" y2="14"/><line x1="17" y1="17" x2="14" y2="14"/></svg>',
      knot: '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3C7 3 3 7 3 12s4 9 9 9 9-4 9-9-4-9-9-9z"/><path d="M12 8c-2.2 0-4 1.8-4 4s1.8 4 4 4 4-1.8 4-4-1.8-4-4-4z"/><line x1="8.5" y1="8.5" x2="15.5" y2="15.5"/><line x1="15.5" y1="8.5" x2="8.5" y2="15.5"/></svg>',
      simplex: '<svg viewBox="0 0 24 24" aria-hidden="true"><polygon points="12,3 21,18 3,18"/><line x1="12" y1="3" x2="12" y2="18"/><line x1="7.5" y1="10.5" x2="16.5" y2="10.5"/><circle cx="12" cy="3" r="1.5"/><circle cx="21" cy="18" r="1.5"/><circle cx="3" cy="18" r="1.5"/></svg>'
    }
  };

  // Button icon mapping by link type
  function getLinkIcon(type) {
    if (type === 'demo') return ICONS.externalLink;
    if (type === 'github') return ICONS.github;
    if (type === 'paper') return ICONS.document;
    return ICONS.externalLink;
  }

  // =========================================================================
  // Fetch helper
  // =========================================================================

  // Determine base path: pages in subdirectories need "../"
  var basePath = '';
  var path = window.location.pathname;
  // If we're in a subdirectory like /tutorials/template.html
  if (path.indexOf('/tutorials/') !== -1) {
    basePath = '../';
  }

  function fetchJSON(url) {
    return fetch(basePath + url).then(function (res) {
      if (!res.ok) throw new Error('Failed to fetch ' + url + ': ' + res.status);
      return res.json();
    });
  }

  // =========================================================================
  // Renderers
  // =========================================================================

  function renderNews(container) {
    return fetchJSON('content/news.json').then(function (items) {
      container.innerHTML = items.map(function (item) {
        return '<div class="news-item" role="listitem">' +
          '<time class="news-date" datetime="' + item.datetime + '">' + item.date + '</time>' +
          '<p class="news-text">' + item.text + '</p>' +
          '</div>';
      }).join('');
    });
  }

  function renderPublications(container) {
    return fetchJSON('content/publications.json').then(function (pubs) {
      container.innerHTML = pubs.map(function (pub) {
        // Auto-bold "Andrew R. Tawfeek" in authors
        var authors = pub.authors.replace(
          /Andrew R\. Tawfeek/g,
          '<strong>Andrew R. Tawfeek</strong>'
        );

        var titleHTML;
        if (pub.url) {
          titleHTML = '<a href="' + pub.url + '" target="_blank" rel="noopener noreferrer">' +
            pub.title + '</a>';
        } else {
          titleHTML = pub.title;
        }

        var statusHTML = '';
        if (pub.status) {
          statusHTML = ' <span class="pub-status ' + (pub.statusClass || '') + '">' +
            pub.status + '</span>';
        }

        var linksHTML = pub.links.map(function (link) {
          return '<a class="pub-link" href="' + link.url +
            '" target="_blank" rel="noopener noreferrer">' + link.label + '</a>';
        }).join('');

        return '<article class="pub-card" role="listitem">' +
          '<div class="pub-title">' + titleHTML + statusHTML + '</div>' +
          '<p class="pub-authors">' + authors + '</p>' +
          '<p class="pub-venue">' + pub.venue + '</p>' +
          '<div class="pub-links">' + linksHTML + '</div>' +
          '</article>';
      }).join('');
    });
  }

  function renderInterests(container) {
    return fetchJSON('content/interests.json').then(function (interests) {
      container.innerHTML = interests.map(function (tag) {
        return '<span class="interest-tag" role="listitem">' + tag + '</span>';
      }).join('');
    });
  }

  function renderProjects(container) {
    return fetchJSON('content/projects.json').then(function (projects) {
      container.innerHTML = projects.map(function (proj) {
        // Thumbnail
        var thumbSVG = (proj.thumbIcon && ICONS.thumb[proj.thumbIcon]) || '';
        var thumbHTML = '<div class="project-thumb" aria-hidden="true">' +
          '<div class="project-thumb-placeholder">' +
          thumbSVG +
          proj.name.toLowerCase().replace(/\s+/g, '-') +
          '</div></div>';

        // Tech badges
        var techHTML = proj.tech.map(function (t) {
          return '<span class="tech-badge">' + t + '</span>';
        }).join('');

        // Links
        var linksHTML = proj.links.map(function (link) {
          var btnClass = link.type === 'demo'
            ? 'btn-project btn-project-primary'
            : 'btn-project btn-project-secondary';
          return '<a class="' + btnClass + '" href="' + link.url +
            '" target="_blank" rel="noopener noreferrer" aria-label="' + link.label + ' for ' + proj.name + '">' +
            getLinkIcon(link.type) +
            link.label + '</a>';
        }).join('');

        return '<article class="project-card" aria-labelledby="proj-' + proj.id + '-title">' +
          thumbHTML +
          '<div class="project-body">' +
          '<h2 class="project-name" id="proj-' + proj.id + '-title">' + proj.name + '</h2>' +
          '<p class="project-desc">' + proj.description + '</p>' +
          '<div class="project-tech" aria-label="Technologies used">' + techHTML + '</div>' +
          '<div class="project-links">' + linksHTML + '</div>' +
          '</div></article>';
      }).join('');
    });
  }

  function renderTutorials(container) {
    return fetchJSON('content/tutorials.json').then(function (tutorials) {
      container.innerHTML = tutorials.map(function (tut) {
        var tagsHTML = tut.tags.map(function (tag) {
          return '<span class="tutorial-tag">' + tag + '</span>';
        }).join('');

        var actionHTML;
        if (tut.published) {
          actionHTML = '<a class="tutorial-read-link" href="tutorials/template.html?slug=' +
            tut.slug + '">Read tutorial &rarr;</a>';
        } else {
          actionHTML = '<span class="tutorial-coming-soon" aria-label="Not yet published">Coming soon</span>';
        }

        return '<article class="tutorial-card" role="listitem" aria-labelledby="tut-' + tut.slug + '-title">' +
          '<div class="tutorial-meta">' +
          '<time class="tutorial-date" datetime="' + tut.datetime + '">' + tut.date + '</time>' +
          '<div class="tutorial-tags" aria-label="Tags">' + tagsHTML + '</div>' +
          '</div>' +
          '<h2 class="tutorial-title" id="tut-' + tut.slug + '-title">' + tut.title + '</h2>' +
          '<p class="tutorial-desc">' + tut.description + '</p>' +
          actionHTML +
          '</article>';
      }).join('');
    });
  }

  // =========================================================================
  // Init — detect containers and render only what's needed
  // =========================================================================

  function init() {
    var tasks = [];

    var newsEl = document.getElementById('news-container');
    if (newsEl) tasks.push(renderNews(newsEl));

    var pubsEl = document.getElementById('pub-container');
    if (pubsEl) tasks.push(renderPublications(pubsEl));

    var interestsEl = document.getElementById('interests-container');
    if (interestsEl) tasks.push(renderInterests(interestsEl));

    var projectsEl = document.getElementById('projects-container');
    if (projectsEl) tasks.push(renderProjects(projectsEl));

    var tutorialsEl = document.getElementById('tutorials-container');
    if (tutorialsEl) tasks.push(renderTutorials(tutorialsEl));

    Promise.all(tasks).catch(function (err) {
      console.error('[content-loader]', err);
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

})();
