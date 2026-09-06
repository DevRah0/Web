/** Optional motion. Native scrolling, links, and content work without this layer. */
import { setupProjectCursor } from './cursor.mjs?v=interaction-1';
export const clamp = (value, min, max) => Math.min(max, Math.max(min, value));
export function scrollProgress(scrollY, documentHeight, viewportHeight) {
  const distance = documentHeight - viewportHeight;
  return distance > 0 ? clamp(scrollY / distance, 0, 1) : 0;
}

export function setupMotion({ copy, storage }) {
  const root = document.documentElement;
  const reduce = window.matchMedia('(prefers-reduced-motion: reduce)');
  const fine = window.matchMedia('(hover: hover) and (pointer: fine)');
  const button = document.querySelector('.motion-toggle');
  const hero = document.querySelector('.hero');
  const art = document.querySelector('.hero-art');
  const header = document.querySelector('.site-header');
  const progress = document.querySelector('#reading-progress');
  const cursor = document.querySelector('.project-cursor');
  const preview = document.querySelector('#work-preview');
  const animations = new Set();
  let preference = storage.get('motion') !== 'off';
  let frame = 0;
  const enabled = () => preference && !reduce.matches && typeof Element.prototype.animate === 'function';
  const projectCursor = setupProjectCursor({ cursor, enabled: () => enabled() && fine.matches });

  function animate(node, frames, options = {}) {
    if (!node || !enabled()) return;
    const animation = node.animate(frames, { duration: 750, easing: 'cubic-bezier(.2,.7,.1,1)', ...options });
    animations.add(animation);
    const release = () => animations.delete(animation);
    animation.addEventListener('finish', release, { once: true });
    animation.addEventListener('cancel', release, { once: true });
    return animation;
  }

  function updateControls() {
    const active = enabled();
    root.dataset.motion = active ? 'on' : 'off';
    button.textContent = reduce.matches ? copy().systemMotion : active ? copy().pauseMotion : copy().playMotion;
    button.setAttribute('aria-pressed', String(active));
    button.disabled = reduce.matches || typeof Element.prototype.animate !== 'function';
    if (!active) {
      animations.forEach(animation => animation.cancel());
      // Include preview transitions owned by the repository interface.
      document.getAnimations?.().forEach(animation => animation.cancel());
      projectCursor.hide();
      document.querySelectorAll('[data-magnetic]').forEach(node => node.style.removeProperty('transform'));
    }
    projectCursor.refresh();
    schedule();
  }

  function draw() {
    frame = 0;
    const y = window.scrollY;
    progress.style.transform = `scaleX(${scrollProgress(y, root.scrollHeight, window.innerHeight)})`;
    header.classList.toggle('is-scrolled', y > 32);
    if (!enabled() || document.hidden) return;
    if (y < hero.offsetHeight + header.offsetHeight) {
      const offset = clamp(y * 0.1, 0, 90);
      art.style.setProperty('--art-y', `${offset}px`);
      art.style.setProperty('--art-r', `${clamp(y * 0.002, 0, 1.8)}deg`);
    }
  }
  function schedule() { if (!frame) frame = requestAnimationFrame(draw); }

  const observer = 'IntersectionObserver' in window ? new IntersectionObserver(entries => {
    entries.forEach(entry => {
      if (!entry.isIntersecting) return;
      observer.unobserve(entry.target);
      animate(entry.target, [{ opacity: 0, transform: 'translateY(28px)' }, { opacity: 1, transform: 'translateY(0)' }], {
        delay: Number(entry.target.dataset.motionDelay || 0),
      });
    });
  }, { threshold: 0.12 }) : null;
  document.querySelectorAll('[data-reveal]').forEach(node => observer?.observe(node));

  function animateList(list) {
    [...list.children].forEach((node, index) => {
      node.dataset.motionDelay = String(Math.min(index * 55, 220));
      if (observer) observer.observe(node);
      else animate(node, [{ opacity: 0 }, { opacity: 1 }], { duration: 400 });
    });
  }

  document.querySelectorAll('[data-magnetic]').forEach(node => {
    node.addEventListener('pointermove', event => {
      if (!enabled() || !fine.matches || event.pointerType === 'touch') return;
      const bounds = node.getBoundingClientRect();
      node.style.transform = `translate(${clamp((event.clientX - bounds.left - bounds.width / 2) * 0.18, -9, 9)}px,${clamp((event.clientY - bounds.top - bounds.height / 2) * 0.18, -9, 9)}px)`;
    }, { passive: true });
    node.addEventListener('pointerleave', () => {
      animate(node, [{ transform: node.style.transform || 'translate(0,0)' }, { transform: 'translate(0,0)' }], { duration: 450 });
      node.style.removeProperty('transform');
    });
  });
  preview.addEventListener('pointermove', event => {
    if (!enabled() || !fine.matches || event.pointerType === 'touch') return;
    const bounds = preview.getBoundingClientRect();
    const x = clamp((event.clientX - bounds.left) / bounds.width - 0.5, -0.5, 0.5);
    const y = clamp((event.clientY - bounds.top) / bounds.height - 0.5, -0.5, 0.5);
    preview.style.setProperty('--preview-x', `${x * 14}px`);
    preview.style.setProperty('--preview-y', `${y * 14}px`);
    preview.style.setProperty('--preview-angle', `${x * 24}deg`);
  }, { passive: true });
  preview.addEventListener('pointerleave', () => {
    ['--preview-x', '--preview-y', '--preview-angle'].forEach(property => preview.style.removeProperty(property));
  });

  document.querySelectorAll('.expertise-card').forEach(detail => {
    detail.addEventListener('toggle', () => {
      if (!detail.open || !enabled()) return;
      const content = detail.querySelector('.skill-content');
      content.getAnimations().forEach(animation => animation.cancel());
      animate(content, [{ height: '0px', opacity: 0, transform: 'translateY(-8px)' }, { height: `${content.offsetHeight}px`, opacity: 1, transform: 'translateY(0)' }], { duration: 450 });
    });
  });
  button.addEventListener('click', () => {
    preference = !preference;
    storage.set('motion', preference ? 'on' : 'off');
    updateControls();
  });
  const onMedia = (query, callback) => query.addEventListener ? query.addEventListener('change', callback) : query.addListener(callback);
  onMedia(reduce, updateControls);
  onMedia(fine, () => { projectCursor.hide(); projectCursor.refresh(); schedule(); });
  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule, { passive: true });
  document.addEventListener('visibilitychange', () => { root.dataset.paused = String(document.hidden); schedule(); });
  if ('ResizeObserver' in window) new ResizeObserver(() => { schedule(); projectCursor.refresh(); }).observe(document.body);

  updateControls();
  document.fonts?.ready.then(schedule);
  [document.querySelector('.hero-topline'), document.querySelector('.hero-title-wrap'), document.querySelector('.hero-note')].forEach((node, index) => {
    animate(node, [{ opacity: 0, transform: 'translateY(32px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 1050, delay: index * 110 });
  });
  return { enabled, updateControls, animateList, refreshCursor: projectCursor.refresh };
}
