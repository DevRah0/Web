/* Runs in the head, before fragment targets or browser scroll restoration. */
(() => {
  const cleanAddress = () => {
    if (location.hash) history.replaceState(history.state, '', location.pathname + location.search);
  };
  try {
    history.scrollRestoration = 'manual';
    cleanAddress();
  } catch (_) { /* Native links still work if history access is restricted. */ }

  let navigated = false;
  const startAtTop = () => {
    if (!navigated) window.scrollTo({ top: 0, left: 0, behavior: 'instant' });
  };
  startAtTop();
  window.addEventListener('pageshow', event => {
    if (!event.persisted) startAtTop();
  });

  document.addEventListener('click', event => {
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
    const link = event.target.closest?.('a[href^="#"]');
    if (!link || link.hasAttribute('download') || (link.target && link.target !== '_self')) return;
    let id;
    try { id = decodeURIComponent(link.getAttribute('href').slice(1)); } catch (_) { return; }
    const target = document.getElementById(id);
    if (!target) return;

    event.preventDefault();
    navigated = true;
    try { cleanAddress(); } catch (_) {}
    const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const behavior = reduced || document.documentElement.dataset.motion === 'off' ? 'instant' : 'smooth';
    if (id === 'top') window.scrollTo({ top: 0, left: 0, behavior });
    else target.scrollIntoView({ behavior, block: 'start' });

    // Preserve keyboard/skip-link focus without triggering a second scroll.
    if (event.detail === 0 || id === 'main-content') {
      const temporaryTabIndex = !target.hasAttribute('tabindex');
      if (temporaryTabIndex) {
        target.setAttribute('tabindex', '-1');
        target.addEventListener('blur', () => target.removeAttribute('tabindex'), { once: true });
      }
      target.focus({ preventScroll: true });
    }
  });
})();
