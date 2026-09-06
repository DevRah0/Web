import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { setupProjectCursor } from '../js/cursor.mjs';

class Events {
  listeners = new Map();
  addEventListener(type, handler, options = {}) {
    const list = this.listeners.get(type) || [];
    list.push({ handler, once: options.once });
    this.listeners.set(type, list);
  }
  emit(type, event = {}) {
    for (const item of [...(this.listeners.get(type) || [])]) {
      item.handler(event);
      if (item.once) this.listeners.set(type, this.listeners.get(type).filter(entry => entry !== item));
    }
  }
}

function navigationFixture(address = 'https://devrah0.github.io/Web/?v=monogram-1#expertise') {
  const win = new Events();
  const doc = new Events();
  const location = new URL(address);
  const history = { state: { retained: true }, scrollRestoration: 'auto', replaceState(state, _, url) {
    this.state = state;
    location.href = new URL(url, location).href;
  } };
  let reduced = false;
  const scrolls = [];
  win.scrollTo = options => scrolls.push(options);
  win.matchMedia = () => ({ matches: reduced });
  doc.documentElement = { dataset: { motion: 'on' } };
  const targets = new Map(['projects', 'about', 'expertise', 'journey', 'contact', 'top', 'main-content'].map(id => {
    const target = new Events();
    const attrs = new Map();
    Object.assign(target, {
      hasAttribute: key => attrs.has(key),
      setAttribute: (key, value) => attrs.set(key, value),
      removeAttribute: key => attrs.delete(key),
      scrollIntoView: options => { target.scroll = options; },
      focus: options => { target.focusOptions = options; },
    });
    return [id, target];
  }));
  doc.getElementById = id => targets.get(id);
  runInNewContext(readFileSync(new URL('../js/navigation.js', import.meta.url), 'utf8'), { window: win, document: doc, history, location });
  function click(id, options = {}) {
    const link = { target: '', hasAttribute: () => false, getAttribute: () => '#' + id };
    const event = { button: 0, detail: 1, target: { closest: () => link }, preventDefault() { this.defaultPrevented = true; }, ...options };
    doc.emit('click', event);
    return event;
  }
  return { win, doc, location, history, targets, scrolls, click, reduce: () => { reduced = true; } };
}

test('old section URLs and reloads start at the top without discarding query or history state', () => {
  const f = navigationFixture();
  assert.equal(f.location.href, 'https://devrah0.github.io/Web/?v=monogram-1');
  assert.equal(f.history.scrollRestoration, 'manual');
  assert.equal(f.history.state.retained, true);
  assert.equal(f.scrolls[0].top, 0);
  f.win.emit('pageshow', { persisted: false });
  assert.equal(f.scrolls.at(-1).top, 0);
  assert.equal(f.scrolls.at(-1).behavior, 'instant');
});

test('every section link scrolls without adding a hash; late loading does not undo the chosen section', () => {
  const f = navigationFixture('https://devrah0.github.io/Web/');
  for (const id of ['projects', 'about', 'expertise', 'journey', 'contact']) {
    assert.equal(f.click(id).defaultPrevented, true);
    assert.equal(f.targets.get(id).scroll.behavior, 'smooth');
    assert.equal(f.location.href, 'https://devrah0.github.io/Web/');
  }
  const count = f.scrolls.length;
  f.win.emit('pageshow', { persisted: false });
  assert.equal(f.scrolls.length, count);
  f.click('top');
  assert.equal(f.scrolls.at(-1).top, 0);
  assert.equal(f.location.hash, '');
});

test('keyboard focus, reduced motion, and modified native link clicks are preserved', () => {
  const f = navigationFixture();
  f.reduce();
  f.click('expertise', { detail: 0 });
  const target = f.targets.get('expertise');
  assert.equal(target.scroll.behavior, 'instant');
  assert.equal(target.focusOptions.preventScroll, true);
  assert.equal(target.hasAttribute('tabindex'), true);
  target.emit('blur');
  assert.equal(target.hasAttribute('tabindex'), false);
  for (const options of [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true }, { button: 1 }, { defaultPrevented: true }]) {
    const event = f.click('about', options);
    assert.equal(event.defaultPrevented, options.defaultPrevented);
    assert.equal(f.targets.get('about').scroll, undefined);
  }
  assert.equal(f.click('missing').defaultPrevented, undefined);
});

function cursorFixture() {
  const win = new Events();
  const doc = new Events();
  const frames = new Map();
  let id = 0;
  let enabled = true;
  let overLink = true;
  win.requestAnimationFrame = callback => { frames.set(++id, callback); return id; };
  const classes = new Set();
  const cursor = { offsetWidth: 74, offsetHeight: 74, style: {}, classList: {
    add: value => classes.add(value), remove: value => classes.delete(value),
  } };
  doc.documentElement = { dataset: {} };
  doc.elementFromPoint = () => ({ closest: () => overLink ? {} : null });
  const control = setupProjectCursor({ cursor, enabled: () => enabled, doc, win });
  const flush = () => { const pending = [...frames.values()]; frames.clear(); pending.forEach(callback => callback()); };
  const active = () => classes.has('is-active') && doc.documentElement.dataset.cursorActive === 'true';
  const move = () => { doc.emit('pointermove', { clientX: 300, clientY: 400, pointerType: 'mouse' }); flush(); };
  return { win, doc, cursor, control, flush, active, move, hit: value => { overLink = value; }, enable: value => { enabled = value; } };
}

test('Open remains visible during scrolling and reappears under a stationary pointer', () => {
  const f = cursorFixture();
  f.move();
  assert.equal(f.active(), true);
  assert.equal(f.cursor.style.transform, 'translate3d(263px,363px,0)');
  f.win.emit('scroll'); f.flush();
  assert.equal(f.active(), true);
  f.hit(false); f.win.emit('scroll'); f.flush();
  assert.equal(f.active(), false);
  f.hit(true); f.win.emit('scroll'); f.flush();
  assert.equal(f.active(), true);
});

test('replaced results and motion changes restore the normal pointer when Open is unavailable', () => {
  const f = cursorFixture(); f.move();
  f.hit(false); f.control.refresh(); f.flush();
  assert.equal(f.active(), false);
  assert.equal(f.doc.documentElement.dataset.cursorActive, undefined);
  f.hit(true); f.control.refresh(); f.flush();
  assert.equal(f.active(), true);
  f.enable(false); f.control.refresh(); f.flush();
  assert.equal(f.active(), false);
  f.enable(true); f.control.refresh(); f.flush();
  assert.equal(f.active(), true);
});

test('leaving the window, changing tabs, and touch input never leave a phantom cursor', () => {
  const f = cursorFixture();
  for (const leave of [() => f.doc.emit('pointerout', { relatedTarget: null }), () => f.win.emit('blur'), () => f.doc.emit('pointermove', { pointerType: 'touch' })]) {
    f.move(); assert.equal(f.active(), true);
    f.control.refresh(); leave(); f.flush();
    assert.equal(f.active(), false);
  }
  f.move(); f.doc.hidden = true; f.doc.emit('visibilitychange'); f.flush();
  assert.equal(f.active(), false);
});
