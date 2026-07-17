(() => {
  "use strict";

  const root = document.documentElement;
  const themeToggle = document.querySelector(".theme-toggle");
  const getSavedTheme = () => {
    try {
      return localStorage.getItem("portfolio-theme");
    } catch {
      return null;
    }
  };
  const saveTheme = (theme) => {
    try {
      localStorage.setItem("portfolio-theme", theme);
    } catch {
      // The visual preference still works when browser storage is unavailable.
    }
  };
  const savedTheme = getSavedTheme();
  const systemPrefersLight = window.matchMedia("(prefers-color-scheme: light)").matches;

  if (savedTheme === "light" || (!savedTheme && systemPrefersLight)) {
    root.dataset.theme = "light";
  }

  themeToggle?.addEventListener("click", () => {
    const isLight = root.dataset.theme === "light";
    if (isLight) {
      delete root.dataset.theme;
      saveTheme("dark");
    } else {
      root.dataset.theme = "light";
      saveTheme("light");
    }
  });

  const menuToggle = document.querySelector(".menu-toggle");
  const navMenu = document.querySelector(".nav-links");
  const setMenu = (open) => {
    navMenu?.classList.toggle("is-open", open);
    menuToggle?.classList.toggle("is-open", open);
    menuToggle?.setAttribute("aria-expanded", String(open));
    document.body.classList.toggle("menu-open", open);
  };

  menuToggle?.addEventListener("click", () => setMenu(!navMenu?.classList.contains("is-open")));
  navMenu?.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setMenu(false)));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape") setMenu(false);
  });

  const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const revealItems = document.querySelectorAll("[data-reveal]");
  revealItems.forEach((item) => {
    const delay = item.dataset.delay;
    if (delay) item.style.setProperty("--reveal-delay", `${delay}ms`);
  });

  if (reducedMotion || !("IntersectionObserver" in window)) {
    revealItems.forEach((item) => item.classList.add("is-visible"));
  } else {
    const revealObserver = new IntersectionObserver(
      (entries, observer) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    revealItems.forEach((item) => revealObserver.observe(item));
  }

  const sections = [...document.querySelectorAll("main section[id]")];
  const navLinks = [...document.querySelectorAll(".nav-links a")];
  const linkById = new Map(navLinks.map((link) => [link.getAttribute("href")?.slice(1), link]));

  if ("IntersectionObserver" in window) {
    const navObserver = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((entry) => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
        if (!visible) return;
        navLinks.forEach((link) => link.classList.remove("active"));
        linkById.get(visible.target.id)?.classList.add("active");
      },
      { rootMargin: "-35% 0px -55% 0px", threshold: [0, 0.2, 0.6] }
    );
    sections.forEach((section) => navObserver.observe(section));
  }

  const toTop = document.querySelector(".back-to-top");
  window.addEventListener("scroll", () => toTop?.classList.toggle("visible", window.scrollY > 700), { passive: true });
  toTop?.addEventListener("click", () => window.scrollTo({ top: 0, behavior: reducedMotion ? "auto" : "smooth" }));

  const dialog = document.querySelector(".project-dialog");
  const dialogTitle = document.querySelector("#dialog-title");
  document.querySelectorAll(".project-open").forEach((button) => {
    button.addEventListener("click", () => {
      if (dialogTitle) dialogTitle.textContent = button.dataset.project || "تفاصيل المشروع";
      if (typeof dialog?.showModal === "function") dialog.showModal();
    });
  });
  document.querySelectorAll(".dialog-close, .dialog-close-text").forEach((button) => button.addEventListener("click", () => dialog?.close()));
  dialog?.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    const isOutside = event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom;
    if (isOutside) dialog.close();
  });

  const year = document.querySelector("#year");
  if (year) year.textContent = new Date().getFullYear();

  if (!reducedMotion && window.matchMedia("(pointer: fine)").matches) {
    const glow = document.querySelector(".cursor-glow");
    window.addEventListener("pointermove", (event) => {
      if (glow) glow.style.transform = `translate(${event.clientX - 224}px, ${event.clientY - 224}px)`;
    }, { passive: true });
  }
})();
