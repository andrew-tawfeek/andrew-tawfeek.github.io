/**
 * main.js — Andrew R. Tawfeek personal website
 * Handles: theme toggle, mobile nav, active nav link, smooth scroll
 * No external dependencies.
 */

(function () {
  'use strict';

  /* -------------------------------------------------------------------------
     Theme Management
     Persists user preference to localStorage.
     Default: dark. Toggle via button; respects system preference on first visit.
     ------------------------------------------------------------------------- */
  const ThemeManager = (() => {
    const STORAGE_KEY = 'site-theme';
    const DARK = 'dark';
    const LIGHT = 'light';

    /**
     * Detect preferred theme in order:
     * 1. Saved preference in localStorage
     * 2. System prefers-color-scheme
     * 3. Default: dark
     */
    function getPreferredTheme() {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === DARK || saved === LIGHT) return saved;

      // Check system preference
      if (window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
        return LIGHT;
      }
      return DARK;
    }

    function applyTheme(theme) {
      document.documentElement.setAttribute('data-theme', theme);
      localStorage.setItem(STORAGE_KEY, theme);

      // Update aria-label on toggle button(s)
      document.querySelectorAll('.theme-toggle').forEach(btn => {
        btn.setAttribute(
          'aria-label',
          theme === DARK ? 'Switch to light mode' : 'Switch to dark mode'
        );
      });
    }

    function toggle() {
      const current = document.documentElement.getAttribute('data-theme') || DARK;
      applyTheme(current === DARK ? LIGHT : DARK);
    }

    function init() {
      // Apply before first paint to avoid flash
      applyTheme(getPreferredTheme());

      // Wire up all toggle buttons (nav bar may have one)
      document.querySelectorAll('.theme-toggle').forEach(btn => {
        btn.addEventListener('click', toggle);
      });

      // Respond to system-level changes if user hasn't set a preference
      if (window.matchMedia) {
        window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', (e) => {
          if (!localStorage.getItem(STORAGE_KEY)) {
            applyTheme(e.matches ? LIGHT : DARK);
          }
        });
      }
    }

    return { init, toggle, applyTheme };
  })();

  /* -------------------------------------------------------------------------
     Mobile Navigation
     Hamburger toggle opens/closes a drawer below the nav bar.
     Closes on outside click, Escape key, or when a link is selected.
     ------------------------------------------------------------------------- */
  const MobileNav = (() => {
    let hamburger = null;
    let drawer = null;
    let isOpen = false;

    function open() {
      isOpen = true;
      drawer.classList.add('open');
      hamburger.setAttribute('aria-expanded', 'true');
      hamburger.setAttribute('aria-label', 'Close menu');
      // Swap icon lines to X
      updateHamburgerIcon(true);
    }

    function close() {
      isOpen = false;
      drawer.classList.remove('open');
      hamburger.setAttribute('aria-expanded', 'false');
      hamburger.setAttribute('aria-label', 'Open menu');
      updateHamburgerIcon(false);
    }

    function toggle() {
      isOpen ? close() : open();
    }

    function updateHamburgerIcon(isX) {
      const svg = hamburger.querySelector('svg');
      if (!svg) return;
      if (isX) {
        // X icon
        svg.innerHTML = `
          <line x1="4" y1="4" x2="20" y2="20"/>
          <line x1="20" y1="4" x2="4" y2="20"/>
        `;
      } else {
        // Hamburger icon
        svg.innerHTML = `
          <line x1="3" y1="6" x2="21" y2="6"/>
          <line x1="3" y1="12" x2="21" y2="12"/>
          <line x1="3" y1="18" x2="21" y2="18"/>
        `;
      }
    }

    function init() {
      hamburger = document.querySelector('.nav-hamburger');
      drawer = document.querySelector('.nav-mobile-drawer');
      if (!hamburger || !drawer) return;

      hamburger.addEventListener('click', toggle);

      // Close when a drawer link is clicked
      drawer.querySelectorAll('a').forEach(link => {
        link.addEventListener('click', close);
      });

      // Close on Escape
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && isOpen) close();
      });

      // Close on outside click
      document.addEventListener('click', (e) => {
        if (isOpen && !hamburger.contains(e.target) && !drawer.contains(e.target)) {
          close();
        }
      });
    }

    return { init };
  })();

  /* -------------------------------------------------------------------------
     Active Nav Link Highlighting
     Marks the nav link that matches the current page as active.
     Also populates the mobile drawer's active state.
     ------------------------------------------------------------------------- */
  const ActiveNav = (() => {
    function init() {
      const currentPath = window.location.pathname;

      // Normalize: strip trailing slash, get last segment
      const segments = currentPath.replace(/\/$/, '').split('/');
      const currentFile = segments[segments.length - 1] || 'index.html';

      // Determine which page we're on
      function matchesLink(href) {
        if (!href) return false;
        const hrefFile = href.split('/').pop() || 'index.html';

        // Home: match root, index.html, empty
        if (currentFile === '' || currentFile === 'index.html') {
          return hrefFile === 'index.html' || href === '/' || href === './';
        }
        return hrefFile === currentFile;
      }

      document.querySelectorAll('.nav-links a, .nav-mobile-drawer a').forEach(link => {
        if (matchesLink(link.getAttribute('href'))) {
          link.classList.add('active');
          link.setAttribute('aria-current', 'page');
        }
      });
    }

    return { init };
  })();

  /* -------------------------------------------------------------------------
     Smooth Scroll
     Intercepts clicks on anchor href="#..." links and scrolls smoothly,
     accounting for the fixed nav bar height.
     ------------------------------------------------------------------------- */
  const SmoothScroll = (() => {
    function getNavHeight() {
      const nav = document.querySelector('.site-nav');
      return nav ? nav.offsetHeight : 60;
    }

    function scrollToTarget(targetId) {
      const target = document.getElementById(targetId);
      if (!target) return;

      const top = target.getBoundingClientRect().top + window.scrollY - getNavHeight() - 16;
      window.scrollTo({ top, behavior: 'smooth' });
    }

    function init() {
      document.addEventListener('click', (e) => {
        const link = e.target.closest('a[href^="#"]');
        if (!link) return;

        const targetId = link.getAttribute('href').slice(1);
        if (!targetId) return;

        e.preventDefault();
        scrollToTarget(targetId);

        // Update URL hash without jumping
        if (history.pushState) {
          history.pushState(null, '', `#${targetId}`);
        }
      });
    }

    return { init };
  })();

  /* -------------------------------------------------------------------------
     Nav Scroll Behavior
     Adds a subtle shadow/border emphasis when page is scrolled.
     ------------------------------------------------------------------------- */
  const NavScroll = (() => {
    function init() {
      const nav = document.querySelector('.site-nav');
      if (!nav) return;

      let ticking = false;

      function onScroll() {
        if (!ticking) {
          window.requestAnimationFrame(() => {
            if (window.scrollY > 10) {
              nav.style.boxShadow = '0 2px 16px rgba(0,0,0,0.2)';
            } else {
              nav.style.boxShadow = 'none';
            }
            ticking = false;
          });
          ticking = true;
        }
      }

      window.addEventListener('scroll', onScroll, { passive: true });
    }

    return { init };
  })();

  /* -------------------------------------------------------------------------
     Initialization
     Wait for DOM to be ready, then wire everything up.
     ------------------------------------------------------------------------- */
  function init() {
    ThemeManager.init();
    MobileNav.init();
    ActiveNav.init();
    SmoothScroll.init();
    NavScroll.init();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    // DOM already parsed (deferred script)
    init();
  }

})();
