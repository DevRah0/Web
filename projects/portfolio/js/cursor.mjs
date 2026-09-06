/** Keep the Open cursor aligned with the live link under the pointer. */
export function setupProjectCursor({ cursor, enabled, doc = document, win = window }) {
  const root = doc.documentElement;
  let point = null;
  let frame = 0;

  function hide() {
    cursor.classList.remove('is-active');
    delete root.dataset.cursorActive;
  }
  function draw() {
    frame = 0;
    if (!point || !enabled() || doc.hidden) { hide(); return; }
    const target = doc.elementFromPoint(point.x, point.y);
    if (!target?.closest('[data-cursor]')) { hide(); return; }
    cursor.style.transform = `translate3d(${point.x - cursor.offsetWidth / 2}px,${point.y - cursor.offsetHeight / 2}px,0)`;
    cursor.classList.add('is-active');
    root.dataset.cursorActive = 'true';
  }
  function refresh() { if (!frame) frame = win.requestAnimationFrame(draw); }
  function leave() { point = null; hide(); }
  function track(event) {
    if (event.pointerType === 'touch') { leave(); return; }
    point = { x: event.clientX, y: event.clientY };
    refresh();
  }

  doc.addEventListener('pointermove', track, { passive: true });
  doc.addEventListener('pointerover', track, { passive: true });
  doc.addEventListener('pointerout', event => {
    if (!event.relatedTarget) leave(); else refresh();
  }, { passive: true });
  win.addEventListener('scroll', refresh, { passive: true, capture: true });
  win.addEventListener('resize', refresh, { passive: true });
  win.addEventListener('blur', leave);
  doc.addEventListener('visibilitychange', () => {
    if (doc.hidden) leave(); else refresh();
  });
  return { refresh, hide };
}
