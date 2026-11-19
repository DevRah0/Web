(() => {
  "use strict";
  const paths = {
    brand:'<path d="M3 15l8-10 3 4-8 10zM12 16l6-8 3 4-6 8z"/>',
    overview:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
    case:'<rect x="3" y="7" width="18" height="14" rx="3"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2M3 12a23 23 0 0 0 18 0M10 13h4"/>',
    activity:'<path d="M2 12h5l3-8 4 16 3-8h5"/>',
    links:'<path d="M10 13a4 4 0 0 0 6 0l3-3a4 4 0 0 0-6-6l-2 2M14 11a4 4 0 0 0-6 0l-3 3a4 4 0 0 0 6 6l2-2"/>',
    chat:'<path d="M20 12a8 8 0 0 1-9 8l-6 1 1-4a8 8 0 1 1 14-5z"/><path d="M8 10h8M8 14h5"/>',
    pin:'<path d="M19 10c0 6-7 11-7 11S5 16 5 10a7 7 0 1 1 14 0z"/><circle cx="12" cy="10" r="2"/>',
    menu:'<path d="M3 6h18M3 12h18M3 18h18"/>', refresh:'<path d="M20 7v5h-5M4 17v-5h5"/><path d="M5.5 8a7 7 0 0 1 12-3L20 8M4 16l2.5 3a7 7 0 0 0 12-3"/>',
    user:'<circle cx="12" cy="8" r="3.5"/><path d="M5 21v-2a7 7 0 0 1 14 0v2"/>',
    check:'<path d="m4.5 12.5 5 5 10-11"/>', chart:'<path d="M3 3v17h18M7 15l4-5 4 2 5-7"/>',
    layers:'<path d="m12 3 9 5-9 5-9-5zM3 12l9 5 9-5M3 16l9 5 9-5"/>',
    search:'<circle cx="10" cy="10" r="6"/><path d="m15 15 6 6"/>',
    mail:'<rect x="3" y="5" width="18" height="14" rx="3"/><path d="m4 7 8 6 8-6"/>',
    send:'<path d="m21 3-6 18-4-8-8-4zM11 13l10-10"/>', x:'<path d="m6 6 12 12M18 6 6 18"/>',
    lock:'<rect x="5" y="10" width="14" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3M12 14v3"/>',
    clock:'<circle cx="12" cy="12" r="9"/><path d="M12 7v6l4 2"/>',
    chevron:'<path d="m14 6-6 6 6 6"/>', file:'<path d="M6 3h8l4 4v14H6zM14 3v5h4M9 12h6M9 16h6"/>',
    review:'<path d="M8 4h8M6 5H4v16h16V5h-2M8 13l3 3 5-6"/>'
  };
  const node = (tag, cls, text) => {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text !== undefined) e.textContent = text;
    return e;
  };
  function icon(name, cls) {
    const e = node("i", cls); e.setAttribute("aria-hidden","true");
    e.innerHTML = '<svg class="ico" viewBox="0 0 24 24" focusable="false">' + paths[name] + '</svg>';
    return e;
  }
  function setIcons(root=document) {
    root.querySelectorAll("[data-icon]").forEach(e => {
      e.setAttribute("aria-hidden","true"); e.replaceChildren(icon(e.dataset.icon).firstElementChild);
    });
  }
  window.OfficeUI = { node, icon, setIcons };
})();
