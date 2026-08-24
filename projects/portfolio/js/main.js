/* ============================================================
   Portfolio — main application script
   Single source of truth for copy is the I18N object below. The static
   HTML ships Arabic defaults (so the page works without JS); on load the
   script applies the active language (Arabic or English) from that same
   object, so JS is always authoritative and the two cannot drift.
   GitHub data is fetched once, cached, and re-rendered — language
   switching never refetches.
   ============================================================ */
(() => {
  "use strict";

  const rootEl = document.documentElement;
  const body = document.body;

  const store = {
    get(key) {
      try { return localStorage.getItem(key); } catch (_) { return null; }
    },
    set(key, value) {
      try { localStorage.setItem(key, value); } catch (_) { /* ignore */ }
    },
  };

  /* ---------------- I18N single source ---------------- */
  const I18N = {
    ar: {
      lang: "ar", dir: "rtl",
      title: "عبدالرحمن الربيعي — خريج هندسة الحاسب",
      metaDesc: "خريج هندسة الحاسب يبني أنظمة ذكية تربط البرمجيات بالعالم الحقيقي: الذكاء الاصطناعي، الرؤية الحاسوبية، تطوير الويب، الروبوتات والأنظمة المضمنة.",
      skipLink: "تخطَّ إلى المحتوى",
      brand: "عبدالرحمن الربيعي",
      themeLabel: "تبديل المظهر",
      langLabel: "التبديل إلى الإنجليزية",
      langText: "EN",
      navCta: "تواصل",
      navAria: "التنقل الرئيسي",
      marquee: ["ذكاء اصطناعي","رؤية حاسوبية","تطوير ويب","روبوتات و ROS","أنظمة مدمجة و IoT","أنظمة ذكية","ذكاء اصطناعي","رؤية حاسوبية","تطوير ويب","روبوتات و ROS","أنظمة مدمجة و IoT","أنظمة ذكية"],

      menuLabel: "فتح القائمة",
      navLinks: ["عني", "المجالات", "المستودعات", "الرحلة", "تواصل"],
      hero: {
        kicker: "متاح للفرص والتعاون المهني",
        titleA: "خريج هندسة حاسب",
        titleB: "يبني أنظمة ذكية",
        sub: "تُدمج البرمجيات بالعالم الحقيقي — من الذكاء الاصطناعي والرؤية الحاسوبية إلى الويب والروبوتات والأنظمة المضمنة.",
        identity: "أنا <strong>عبدالرحمن الربيعي</strong>، خريج هندسة حاسب أحوّل الأفكار التقنية إلى حلول عملية قابلة للتطوّر.",
        primary: "استكشف المستودعات",
        secondary: "تواصل معي",
        github: "GitHub",
        caption: "النظام المتكامل يعمل الآن",
      },
      about: {
        tag: "عني",
        titleA: "خريج هندسة حاسب بتركيز على",
        titleB: "دمج البرمجيات بالعالم الحقيقي",
        p1: "أنا <strong>عبدالرحمن الربيعي</strong>، خريج هندسة الحاسب. عملي لا يقف عند كتابة الكود، بل في بناء أنظمة ذكية تدمج البرمجيات مع الأنظمة المادية لحلول عملية.",
        p2: "أتنقّل بين الذكاء الاصطناعي، الرؤية الحاسوبية، تطوير الويب، الروبوتات، الأنظمة المضمنة وإنترنت الأشياء. أركّز على مشاريع عملية، تعلّم مستمر، وتحويل الفكرة إلى منتج يعمل فعلًا.",
        link: "رؤية مستودعاتي",
        f1l: "تخصصي", f1v: "هندسة الحاسب",
        f2l: "الحالة", f2v: "خريج",
        f3l: "التركيز", f3v: "أنظمة ذكية عملية",
      },
      expertise: {
        tag: "المجالات",
        titleFull: "خبرات تقنية متنوّعة",
        items: [
          { title: "الذكاء الاصطناعي والرؤية الحاسوبية", cat: "AI & Vision", stack: ["Python", "OpenCV", "MediaPipe", "Scikit-learn", "Whisper"] },
          { title: "تطوير الويب الكامل", cat: "Full-Stack Web", stack: ["HTML5", "CSS3", "JavaScript", "React", "Node.js"] },
          { title: "الروبوتات والأنظمة المضمنة", cat: "Robotics & Embedded", stack: ["Rust", "SwiftUI", "BLE", "Raspberry Pi", "C++"] },
          { title: "الهندسة الميكانيكية والروبوتات", cat: "Mechanical", stack: ["Quadruped Robot", "CAD", "ROS"] },
          { title: "إنترنت الأشياء", cat: "IoT", stack: ["C++", "Arduino", "ESP32", "MQTT"] },
        ],
      },
      repos: {
        tag: "مشاريعي",
        titleA: "مستودعاتي على",
        titleB: "GitHub",
        sub: "تُحدَّث تلقائيًا من مستودعاتي العامة.",
        searchPlaceholder: "ابحث في المستودعات…",
        searchAria: "ابحث في المستودعات",
        filtersAria: "تصفية المستودعات",
        all: "الكل",
        loading: "جارٍ تحميل المستودعات…",
        errorMsg: "تعذَّر تحميل المستودعات حاليًا.",
        retry: "إعادة المحاولة",
        empty: "لا توجد مستودعات بعد.",
        noResults: "لا نتائج مطابقة لبحثك.",
        count: "مستودع",
        updated: "آخر تحديث",
        stars: "نجوم",
        forks: "تفرّعات",
        archived: "مؤرشف",
        forkBadge: "نسخة",
        noDesc: "بدون وصف",
        lang: "لغة",
        open: "فتح",
        live: "عرض مباشر",
      },
      journey: {
        tag: "رحلة التدريب",
        titleA: "تدريب تعاوني في",
        sub: "مسار متعدّد التخصصات أراني كيف تتكامل التقنيات لصناعة أنظمة ذكية وروبوتات.",
        note: "علّمني المسار أن الأنظمة الذكية لا تُبنى بأداة واحدة، بل بتكامل الذكاء الاصطناعي مع الويب والكهرباء والميكانيكا — وهو ما أطبّقه في مشاريعي اليوم.",
        items: [
          { title: "الذكاء الاصطناعي والروبوتات", desc: "مشاريع بالرؤية الحاسوبية وتعلّم الآلة وتفاعل الروبوت." },
          { title: "تطوير الويب ومعالجة اللغة", desc: "تطبيقات ويب كاملة مع معالجة لغة طبيعية." },
          { title: "الهندسة الكهربائية والميكانيكا", desc: "دوائر وتحكّم وحركة لروبوتات مادية." },
          { title: "إنترنت الأشياء والأنظمة المضمنة", desc: "دمج المستشعرات والمشغّلات في أنظمة محدودة الموارد." },
        ],
      },
      contact: {
        tag: "الخطوة التالية",
        titleA: "لنبنِ شيئًا",
        titleB: "عمليًّا",
        sub: "مفتوح للفرص المهنية والمشاريع والتعاون التقني. راسلني أو تابعني على GitHub.",
        github: "GitHub",
      },
      footer: {
        made: "بُنيت بعناية لصناعة الأنظمة الذكية",
        top: "للأعلى",
        topLabel: "العودة إلى الأعلى",
      },
      noScript: "الموقع يعمل بشكل أفضل مع تفعيل JavaScript لعرض مستودعات GitHub مباشرة.",
      skeletonLabel: "جاري تحميل بطاقة",
    },
    en: {
      lang: "en", dir: "ltr",
      title: "Abdulrahman Al-Rubaie — Computer Engineering Graduate",
      metaDesc: "Computer Engineering graduate building intelligent systems that connect software with the real world — AI, computer vision, web development, robotics, and embedded systems.",
      skipLink: "Skip to content",
      brand: "Abdulrahman Al-Rubaie",
      themeLabel: "Toggle theme",
      langLabel: "Switch to Arabic",
      langText: "ع",
      navCta: "Contact",
      navAria: "Main navigation",
      marquee: ["Artificial Intelligence","Computer Vision","Web Development","Robotics & ROS","Embedded & IoT","Intelligent Systems","Artificial Intelligence","Computer Vision","Web Development","Robotics & ROS","Embedded & IoT","Intelligent Systems"],

      menuLabel: "Open menu",
      navLinks: ["About", "Expertise", "Repos", "Journey", "Contact"],
      hero: {
        kicker: "Open to professional opportunities and collaborations",
        titleA: "Computer Engineering Graduate",
        titleB: "building intelligent systems",
        sub: "Connecting software with the real world — from AI and computer vision to web, robotics, and embedded systems.",
        identity: "I'm <strong>Abdulrahman Al-Rubaie</strong>, a Computer Engineering graduate turning technical ideas into practical, scalable solutions.",
        primary: "Explore repositories",
        secondary: "Get in touch",
        github: "GitHub",
        caption: "Integrated system online",
      },
      about: {
        tag: "About",
        titleA: "Computer Engineering graduate focused on",
        titleB: "connecting software to the real world",
        p1: "I'm <strong>Abdulrahman Al-Rubaie</strong>, a Computer Engineering graduate. I care about more than just code — I build intelligent systems that combine software with physical systems for practical results.",
        p2: "I move across AI, computer vision, web development, robotics, embedded systems, and IoT. I focus on practical projects, continuous learning, and turning an idea into something that actually works.",
        link: "View my repositories",
        f1l: "Field", f1v: "Computer Engineering",
        f2l: "Status", f2v: "Graduate",
        f3l: "Focus", f3v: "Practical intelligent systems",
      },
      expertise: {
        tag: "Expertise",
        titleFull: "Diverse technical expertise",
        items: [
          { title: "Artificial Intelligence & Computer Vision", cat: "AI & Vision", stack: ["Python", "OpenCV", "MediaPipe", "Scikit-learn", "Whisper"] },
          { title: "Full-Stack Web Development", cat: "Full-Stack Web", stack: ["HTML5", "CSS3", "JavaScript", "React", "Node.js"] },
          { title: "Robotics & Embedded Systems", cat: "Robotics & Embedded", stack: ["Rust", "SwiftUI", "BLE", "Raspberry Pi", "C++"] },
          { title: "Mechanical Engineering & Robots", cat: "Mechanical", stack: ["Quadruped Robot", "CAD", "ROS"] },
          { title: "Internet of Things", cat: "IoT", stack: ["C++", "Arduino", "ESP32", "MQTT"] },
        ],
      },
      repos: {
        tag: "Projects",
        titleA: "My GitHub",
        titleB: "repositories",
        sub: "Fetched automatically from my public repositories.",
        searchPlaceholder: "Search repositories…",
        searchAria: "Search repositories",
        filtersAria: "Filter repositories",
        all: "All",
        loading: "Loading repositories…",
        errorMsg: "Could not load repositories right now.",
        retry: "Retry",
        empty: "No repositories yet.",
        noResults: "No matches for your search.",
        count: "repositories",
        updated: "Updated",
        stars: "stars",
        forks: "forks",
        archived: "archived",
        forkBadge: "fork",
        noDesc: "No description",
        lang: "language",
        open: "Open",
        live: "Live demo",
      },
      journey: {
        tag: "Journey",
        titleA: "Cooperative training at",
        sub: "A multi-track path that showed me how disciplines combine to build intelligent systems.",
        note: "The program taught me that intelligent systems aren't built with a single tool — they need AI combined with web, electronics, and mechanics, which is exactly what I apply in my projects today.",
        items: [
          { title: "AI & Robotics", desc: "Projects in computer vision, machine learning, and robot interaction." },
          { title: "Web Development & NLP", desc: "Full web applications with natural-language processing." },
          { title: "Electrical & Mechanical Engineering", desc: "Circuits, control, and movement for physical robots." },
          { title: "IoT & Embedded Systems", desc: "Merging sensors and actuators into constrained systems." },
        ],
      },
      contact: {
        tag: "Next step",
        titleA: "Let's build something",
        titleB: "practical",
        sub: "Open to professional opportunities, projects, and collaborations. Reach out or follow me on GitHub.",
        github: "GitHub",
      },
      footer: {
        made: "Built with care for building intelligent systems",
        top: "Back to top",
        topLabel: "Back to top",
      },
      noScript: "This site works best with JavaScript enabled to display GitHub repositories live.",
      skeletonLabel: "Loading card",
    },
  };

  /* ---------------- GitHub language colors ---------------- */
  const LANG_COLORS = {
    JavaScript: "#f1e05a", TypeScript: "#3178c6", Python: "#3572A5", "C++": "#f34b7d",
    Rust: "#dea584", Swift: "#F05138", HTML: "#e34c26", CSS: "#563d7c", C: "#555555",
    Java: "#b07219", PHP: "#4F5D95", "C#": "#178600", Go: "#00ADD8", Dart: "#00B4AB",
    Kotlin: "#A97BFF", Ruby: "#701516", Shell: "#89e051", Makefile: "#427819",
  };
  const colorFor = (lang) => LANG_COLORS[lang] || "#8b93a7";

  /* ---------------- Repo category mapping ---------------- */
  // Derived from real repo names. Order matters (Web repo is a meta repo).
  const classifyRepo = (name, lang) => {
    const n = name.toLowerCase();
    if (n.includes("mechanical") || (lang === null && n.includes("eng"))) return { cat: "mechanical", color: "#d97757" };
    if (n.includes("ai") || n.includes("robot")) return { cat: "ai", color: "#3572A5" };
    if (n.includes("bridge") || n.includes("iot") || n.includes("electronic") || n.includes("embedded")) return { cat: "iot", color: "#0fa3c9" };
    if (n.includes("web")) return { cat: "web", color: "#563d7c" };
    return { cat: "other", color: "#8b93a7" };
  };

  /* ============================================================
     Helpers
     ============================================================ */
  const $ = (sel, ctx = document) => ctx.querySelector(sel);
  const $$ = (sel, ctx = document) => [...ctx.querySelectorAll(sel)];
  const reduceMotion = !!(window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches);
  const finePointer = !!(window.matchMedia && window.matchMedia("(hover: hover) and (pointer: fine)").matches);

  let currentLang = store.get("lang") === "en" ? "en" : "ar";

  const setText = (sel, value) => { const n = $(sel); if (n && typeof value === "string") n.textContent = value; };
  const setHtml = (sel, value) => { const n = $(sel); if (n && typeof value === "string") n.innerHTML = value; };

  /* ---------------- Icons (inline SVG strings, trusted) ---------------- */
  const ICONS = {
    ai: '<svg viewBox="0 0 24 24" class="ex-icon" aria-hidden="true"><path d="M12 2 4 6v6c0 5 3.4 8.5 8 10 4.6-1.5 8-5 8-10V6z"/><circle cx="12" cy="12" r="3"/></svg>',
    web: '<svg viewBox="0 0 24 24" class="ex-icon" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.6 3.8 5.7 3.8 9S14.5 18.4 12 21c-2.5-2.6-3.8-5.7-3.8-9S9.5 5.6 12 3z"/></svg>',
    robot: '<svg viewBox="0 0 24 24" class="ex-icon" aria-hidden="true"><rect x="4" y="8" width="16" height="11" rx="3"/><circle cx="9" cy="13.5" r="1.5"/><circle cx="15" cy="13.5" r="1.5"/><path d="M12 8V5M9 5h6"/><path d="M4 12H2M20 12h2M12 19v2"/></svg>',
    gear: '<svg viewBox="0 0 24 24" class="ex-icon" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"/></svg>',
    chip: '<svg viewBox="0 0 24 24" class="ex-icon" aria-hidden="true"><rect x="6" y="6" width="12" height="12" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3"/></svg>',
    lock: '<svg viewBox="0 0 24 24" class="lock" aria-hidden="true"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>',
    star: '<svg viewBox="0 0 24 24" class="stat-icon" aria-hidden="true"><path d="M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9 6.8 19l1-5.8L3.5 9.2l5.9-.9z"/></svg>',
    fork: '<svg viewBox="0 0 24 24" class="stat-icon" aria-hidden="true"><circle cx="6" cy="5" r="2"/><circle cx="18" cy="5" r="2"/><circle cx="12" cy="19" r="2"/><path d="M6 7v2a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V7M12 11v6"/></svg>',
    clock: '<svg viewBox="0 0 24 24" class="stat-icon" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 3"/></svg>',
    search: '<svg viewBox="0 0 24 24" class="search-icon" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
    external: '<svg viewBox="0 0 24 24" class="ext" aria-hidden="true"><path d="M14 4h6v6M20 4 10 14M18 13v6a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1h6"/></svg>',
  };

  const CAT_ICONS = { web: "web", ai: "ai", iot: "chip", mechanical: "gear", other: "robot" };

  /* ============================================================
     Apply language (single source → DOM; no GitHub refetch)
     ============================================================ */
  const applyLanguage = (lang) => {
    const t = I18N[lang];
    currentLang = lang;
    rootEl.lang = t.lang;
    rootEl.dir = t.dir;
    body.classList.toggle("lang-en", lang === "en");

    // document / meta
    document.title = t.title;
    const md = $('meta[name="description"]');
    if (md) md.content = t.metaDesc;

    setText(".skip-link", t.skipLink);
    $$(".brand-name").forEach((n) => (n.textContent = t.brand));
    setText(".lang-toggle", t.langText);
    $(".lang-toggle")?.setAttribute("aria-label", t.langLabel);
    setText(".nav-cta", t.navCta);
    setText(".menu-toggle", ""); // aria-label via attribute
    $(".menu-toggle")?.setAttribute("aria-label", t.menuLabel);
    $$(".nav-links a[data-nav]").forEach((a, i) => {
      if (t.navLinks[i]) a.textContent = t.navLinks[i];
    });

    // hero
    setText(".hero .kicker", t.hero.kicker);
    const h1a = $("#hero-title-a"); if (h1a) h1a.textContent = t.hero.titleA;
    const h1b = $("#hero-title-b"); if (h1b) h1b.textContent = t.hero.titleB;
    setText(".hero-sub", t.hero.sub);
    setHtml(".hero-identity", t.hero.identity);
    setText(".hero-actions .primary .lbl", t.hero.primary);
    setText(".hero-actions .ghost .lbl", t.hero.secondary);
    setText(".hero-actions .link .lbl", t.hero.github);
    setText(".visual-caption .caption-text", t.hero.caption);

    // marquee
    const track = $(".marquee-track");
    if (track) {
      const words = [...t.marquee];
      // build twice for seamless loop; use stable key via data-w
      track.replaceChildren(...words.flatMap((w) => {
        const s = document.createElement("span"); s.textContent = w;
        const i = document.createElement("i"); i.textContent = "✦";
        return [s, i];
      }));
    }

    // about
    setText("#about .tag-text", t.about.tag);
    setText("#about-title-a", t.about.titleA);
    setText("#about-title-b", t.about.titleB);
    setHtml(".about-copy .lead", t.about.p1);
    setText(".about-copy p:not(.lead)", t.about.p2);
    setText(".about-copy .inline-link .lbl", t.about.link);
    setText(".fact-card:nth-child(1) .fact-label", t.about.f1l);
    setText(".fact-card:nth-child(1) .fact-value", t.about.f1v);
    setText(".fact-card:nth-child(2) .fact-label", t.about.f2l);
    setText(".fact-card:nth-child(2) .fact-value", t.about.f2v);
    setText(".fact-card:nth-child(3) .fact-label", t.about.f3l);
    setText(".fact-card:nth-child(3) .fact-value", t.about.f3v);

    // expertise
    setText("#expertise .tag-text", t.expertise.tag);
    setText("#expertise-title", t.expertise.titleFull);

    // repos header
    setText("#projects .tag-text", t.repos.tag);
    const rt=$("#repos-title");
    if (rt) {
      const gradEl = rt.querySelector(".grad-text");
      rt.textContent = t.repos.titleA + " ";
      if (gradEl) rt.appendChild(gradEl);
      gradEl.textContent = t.repos.titleB;
    }
    setText(".repos-sub", t.repos.sub);

    // journey
    renderJourney(t);

    // contact
    setText(".contact .kicker", t.contact.tag);
    setText("#contact-title-a", t.contact.titleA);
    const ctB=$("#contact .section-title .grad-text"); if(ctB) ctB.textContent=t.contact.titleB;
    setText("#contact .contact-sub", t.contact.sub);
    setText(".contact .github-btn .lbl", t.contact.github);

    // footer
    setText(".footer-note", "© " + new Date().getFullYear() + " — " + t.footer.made);
    setText(".footer-top span", t.footer.top);
    $(".footer-top")?.setAttribute("aria-label", t.footer.topLabel);

    // nav aria
    $(".nav-shell")?.setAttribute("aria-label", t.navAria);

    // re-render repo filters (labels) without refetch
    if (window.__reposLoaded) renderRepoControls();

    // reveal
    rootEl.classList.add("has-js");
  };

  /* ============================================================
     Expertise render
     ============================================================ */
  const renderExpertise = (t) => {
    const grid = $("#expertise-grid");
    if (!grid) return;
    grid.replaceChildren(...t.expertise.items.map((item, i) => {
      const card = document.createElement("article");
      card.className = "expertise-card";
      card.setAttribute("data-reveal", "");
      card.style.transitionDelay = `${(i % 3) * 60}ms`;
      const icon = document.createElement("span");
      icon.innerHTML = ICONS[["ai", "web", "robot", "gear", "chip"][i % 5]];
      const h = document.createElement("h3"); h.textContent = item.title;
      const cat = document.createElement("p"); cat.className = "ecat"; cat.textContent = item.cat;
      const ul = document.createElement("ul");
      item.stack.forEach((tech) => {
        const li = document.createElement("li"); li.textContent = tech; ul.appendChild(li);
      });
      card.append(icon, h, cat, ul);
      return card;
    }));
    bindReveal();
  };

  /* ============================================================
     Journey render
     ============================================================ */
  const renderJourney = (t) => {
    setText("#journey .tag-text", t.journey.tag);
    setText("#journey-title-a", t.journey.titleA);
    setText(".journey-sub", t.journey.sub);
    setText(".journey-note p", t.journey.note);
    const grid = $("#journey-grid");
    if (!grid) return;
    const icons = ["robot", "web", "gear", "chip"];
    grid.replaceChildren(...t.journey.items.map((item, i) => {
      const card = document.createElement("article");
      card.className = "journey-card";
      const ic = document.createElement("span");
      ic.innerHTML = ICONS[icons[i % 4]];
      const h = document.createElement("h3"); h.textContent = item.title;
      const p = document.createElement("p"); p.textContent = item.desc;
      card.append(ic, h, p);
      return card;
    }));
  };

  /* ============================================================
     GitHub data: fetch once + cache + re-render
     ============================================================ */
  const GH_URL = "https://api.github.com/users/DevRah0/repos?sort=updated&per_page=100&type=all";
  const CACHE_KEY = "portfolio-repos-v1";
  const CACHE_TTL = 15 * 60 * 1000; // 15 minutes
  const IGNORED = [".github"];

  let reposCache = null;      // [{...}] normalized
  let reposLoaded = false;
  let loadError = false;

  const getCached = () => {
    const raw = store.get(CACHE_KEY);
    if (!raw) return null;
    try {
      const parsed = JSON.parse(raw);
      if (parsed.ts && Date.now() - parsed.ts < CACHE_TTL) return parsed.repos;
    } catch (_) { /* fall through */ }
    return null;
  };

  const normalize = (items) => items
    .filter((r) => !IGNORED.includes(r.name))
    .map((r) => {
      const cls = classifyRepo(r.name, r.language);
      return {
        name: r.name,
        desc: r.description || "",
        lang: r.language || null,
        topics: Array.isArray(r.topics) ? r.topics : [],
        stars: r.stargazers_count || 0,
        forks: r.forks_count || 0,
        updated: r.updated_at || "",
        pushed: r.pushed_at || "",
        archived: !!r.archived,
        isFork: !!r.fork,
        homepage: r.homepage || "",
        url: r.html_url || "",
        cat: cls.cat,
        catColor: cls.color,
        private: !!r.private,
      };
    });

  const fetchRepos = async (force = false) => {
    const list = $("#repo-list");
    if (!list) return;
    if (!force && reposCache) { renderRepoList(reposCache); return; }
    if (!force) {
      const cached = getCached();
      if (cached) {
        reposCache = cached;
        reposLoaded = true;
        window.__reposLoaded = true;
        renderRepoControls();
        renderRepoList(cached);
        return;
      }
    }

    renderSkeleton(list);
    try {
      const res = await fetch(GH_URL, { headers: { Accept: "application/vnd.github+json" } });
      if (!res.ok) {
        if (res.status === 403 || res.status === 429) throw new Error("rate-limit");
        if (res.status === 404) throw new Error("not-found");
        throw new Error("http-" + res.status);
      }
      const items = await res.json();
      if (!Array.isArray(items)) throw new Error("bad-payload");
      reposCache = normalize(items);
      reposLoaded = true;
      loadError = false;
      store.set(CACHE_KEY, JSON.stringify({ ts: Date.now(), repos: reposCache }));
      window.__reposLoaded = true;
      renderRepoControls();
      renderRepoList(reposCache);
    } catch (err) {
      loadError = true;
      renderError(list, err.message === "rate-limit" ? "rate" : err.message === "not-found" ? "not-found" : "generic");
    }
  };

  /* ---------------- render controls ---------------- */
  let activeFilter = "all";
  let searchQuery = "";
  const PER_PAGE = 6;
  let page = 1;

  const repoFilterSet = () => [...new Set((reposCache || []).map((r) => r.cat))];
  const catLabel = (cat) => {
    const map = { web: "Web", ai: "AI & Robotics", iot: "Electronics & IoT", mechanical: "Mechanical Engineering", other: "Other" };
    return map[cat] || cat;
  };

  const renderRepoControls = () => {
    const t = I18N[currentLang];
    const filters = $("#repo-filters");
    if (!filters) return;
    const cats = repoFilterSet();
    const labels = [t.repos.all, ...cats.map(catLabel)];
    const values = ["all", ...cats];
    filters.replaceChildren(...labels.map((label, i) => {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "filter-btn" + (values[i] === activeFilter ? " is-active" : "");
      btn.textContent = label;
      btn.setAttribute("aria-pressed", String(values[i] === activeFilter));
      btn.addEventListener("click", () => {
        activeFilter = values[i];
        page = 1;
        renderRepoControls();
        renderRepoList(reposCache);
      });
      return btn;
    }));
    // search placeholder per language
    const search = $("#repo-search");
    if (search) { search.placeholder = t.repos.searchPlaceholder; search.setAttribute("aria-label", t.repos.searchAria); }
    filters.setAttribute("aria-label", t.repos.filtersAria);
  };

  /* ---------------- render list (from cache only) ---------------- */
  const visibleRepos = () => {
    if (!reposCache) return [];
    return reposCache.filter((r) => {
      const okCat = activeFilter === "all" || r.cat === activeFilter;
      const q = searchQuery.trim().toLowerCase();
      const okQ = !q || r.name.toLowerCase().includes(q) ||
        (r.desc && r.desc.toLowerCase().includes(q)) ||
        (r.lang && r.lang.toLowerCase().includes(q)) ||
        (r.topics && r.topics.some((x) => x.toLowerCase().includes(q)));
      return okCat && okQ;
    });
  };

  const renderRepoList = (repos) => {
    const list = $("#repo-list");
    if (!list) return;
    const t = I18N[currentLang];
    const filtered = visibleRepos();

    // count badge
    const count = $("#repos-count");
    if (count) count.textContent = `${filtered.length} ${t.repos.count}`;

    if (filtered.length === 0) {
      renderEmpty(list, repos.length === 0 ? "empty" : "noResults");
      return;
    }

    const totalPages = Math.max(1, Math.ceil(filtered.length / PER_PAGE));
    if (page > totalPages) page = totalPages;
    const start = (page - 1) * PER_PAGE;
    const slice = filtered.slice(start, start + PER_PAGE);

    const frag = document.createDocumentFragment();
    slice.forEach((r, i) => frag.appendChild(buildCard(r, start + i, t)));
    list.replaceChildren(frag);

    renderPagination(totalPages);
  };

  /* Build one repo card using DOM APIs (no untrusted innerHTML) */
  const buildCard = (r, index, t) => {
    const card = document.createElement("article");
    card.className = "repo-card";
    card.setAttribute("data-cat", r.cat);
    if (r.archived) card.setAttribute("data-archived", "true");
    card.style.setProperty("--card-accent", r.catColor);

    // top row
    const top = document.createElement("div");
    top.className = "repo-top";
    const idx = document.createElement("span");
    idx.className = "repo-idx";
    idx.textContent = String(index + 1).padStart(2, "0");
    const badges = document.createElement("div");
    badges.className = "repo-badges";
    if (r.archived) { const b = document.createElement("span"); b.className = "repo-badge repo-badge-archived"; b.textContent = t.repos.archived; badges.appendChild(b); }
    if (r.isFork) { const b = document.createElement("span"); b.className = "repo-badge repo-badge-fork"; b.textContent = t.repos.forkBadge; badges.appendChild(b); }
    if (badges.childNodes.length) top.append(idx, badges);
    else top.appendChild(idx);

    // name
    const nameRow = document.createElement("h3");
    nameRow.className = "repo-name";
    const nameSpan = document.createElement("span");
    nameSpan.textContent = r.name;
    nameRow.appendChild(nameSpan);

    // description
    const desc = document.createElement("p");
    desc.className = "repo-desc";
    if (r.desc) desc.textContent = r.desc;
    else { desc.textContent = t.repos.noDesc; desc.classList.add("placeholder"); }

    // meta: language + topics
    const langRow = document.createElement("div");
    langRow.className = "repo-lang-inline";
    const dot = document.createElement("span");
    dot.style.width = "9px"; dot.style.height = "9px";
    dot.style.borderRadius = "50%"; dot.style.background = colorFor(r.lang || "");
    dot.style.display = "inline-block";
    dot.style.marginInlineEnd = "0.4rem";
    langRow.appendChild(dot);
    langRow.appendChild(document.createTextNode(r.lang || t.repos.noDesc));

    // topics
    const topicsRow = document.createElement("ul");
    topicsRow.className = "repo-topics";
    (r.topics || []).slice(0, 4).forEach((topic) => {
      const li = document.createElement("li"); li.textContent = topic; topicsRow.appendChild(li);
    });

    // stats row
    const stats = document.createElement("div");
    stats.className = "repo-stats";
    const starSpan = document.createElement("span");
    starSpan.innerHTML = ICONS.star; starSpan.appendChild(document.createTextNode(" " + r.stars));
    const forkSpan = document.createElement("span");
    forkSpan.innerHTML = ICONS.fork; forkSpan.appendChild(document.createTextNode(" " + r.forks));
    const updSpan = document.createElement("span");
    updSpan.innerHTML = ICONS.clock;
    const updText = document.createTextNode(" " + t.repos.updated + " " + (r.pushed ? fmtDate(r.pushed) : "—"));
    updSpan.appendChild(updText);
    if (r.stars) stats.appendChild(starSpan);
    if (r.forks) stats.appendChild(forkSpan);
    stats.appendChild(updSpan);

    // actions
    const actions = document.createElement("div");
    actions.className = "repo-actions";
    const ghBtn = document.createElement("a");
    ghBtn.className = "btn-repo btn-repo-github";
    ghBtn.href = r.url;
    ghBtn.target = "_blank";
    ghBtn.rel = "noopener noreferrer";
    const ghLbl = document.createElement("span"); ghLbl.textContent = t.repos.open + " · GitHub";
    ghBtn.appendChild(ghLbl);
    actions.appendChild(ghBtn);
    if (r.homepage && /^https?:\/\//i.test(r.homepage)) {
      const demo = document.createElement("a");
      demo.className = "btn-repo btn-repo-demo";
      demo.href = r.homepage;
      demo.target = "_blank";
      demo.rel = "noopener noreferrer";
      demo.textContent = t.repos.live;
      actions.appendChild(demo);
    }

    card.append(top, nameRow, desc, langRow);
    if (topicsRow.childNodes.length) card.appendChild(topicsRow);
    card.appendChild(stats);
    card.appendChild(actions);

    return card;
  };

  const fmtDate = (iso) => {
    if (!iso) return "—";
    try {
      const d = new Date(iso);
      return d.toLocaleDateString(currentLang === "ar" ? "ar-SA" : "en-US", { year: "numeric", month: "short", day: "numeric" });
    } catch (_) { return "—"; }
  };

  const renderPagination = (totalPages) => {
    const nav = $("#repo-pagination");
    if (!nav) return;
    if (totalPages <= 1) { nav.replaceChildren(); return; }
    const frag = document.createDocumentFragment();
    for (let p = 1; p <= totalPages; p++) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "page-btn" + (p === page ? " is-active" : "");
      btn.textContent = String(p);
      btn.setAttribute("aria-current", p === page ? "page" : "false");
      btn.addEventListener("click", () => { page = p; renderRepoList(reposCache); });
      frag.appendChild(btn);
    }
    nav.replaceChildren(frag);
  };

  /* ---------------- states ---------------- */
  const renderSkeleton = (list) => {
    const t = I18N[currentLang];
    const frag = document.createDocumentFragment();
    for (let i = 0; i < 3; i++) {
      const s = document.createElement("div");
      s.className = "repo-skeleton";
      s.setAttribute("role", "status");
      s.setAttribute("aria-label", t.skeletonLabel);
      s.innerHTML = `
        <span class="sk-line short" style="margin-bottom:.8rem"></span>
        <span class="sk-line tall" style="margin-bottom:.5rem"></span>
        <span class="sk-line short"></span>
      `;
      frag.appendChild(s);
    }
    list.replaceChildren(frag);
    const count = $("#repos-count");
    if (count) count.textContent = t.repos.loading;
  };

  const renderEmpty = (list, kind) => {
    const t = I18N[currentLang];
    const state = document.createElement("div");
    state.className = "repo-state";
    const icon = document.createElement("div");
    icon.className = "repo-state-icon";
    icon.innerHTML = ICONS.search;
    const h = document.createElement("h3");
    h.textContent = kind === "empty" ? t.repos.empty : t.repos.noResults;
    const p = document.createElement("p");
    p.textContent = kind === "empty" ? "" : t.repos.searchAria;
    state.append(icon, h, p);
    list.replaceChildren(state);
  };

  const renderError = (list, kind) => {
    const t = I18N[currentLang];
    const state = document.createElement("div");
    state.className = "repo-state";
    const icon = document.createElement("div");
    icon.className = "repo-state-icon";
    icon.innerHTML = ICONS.chip;
    const h = document.createElement("h3");
    h.textContent = t.repos.errorMsg;
    const p = document.createElement("p");
    p.textContent = kind === "rate" ? "Rate limit" : "";
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "btn btn-primary retry-btn";
    btn.textContent = t.repos.retry;
    btn.addEventListener("click", () => fetchRepos(true));
    state.append(icon, h, p, btn);
    list.replaceChildren(state);
    const count = $("#repos-count");
    if (count) count.textContent = "—";
  };

  /* ============================================================
     Reveal on scroll (gated by .has-js + .is-visible)
     ============================================================ */
  let revealObserver = null;
  const bindReveal = () => {
    if (reduceMotion) {
      $$("[data-reveal]").forEach((el) => el.classList.add("is-visible"));
      return;
    }
    if (!("IntersectionObserver" in window)) {
      $$("[data-reveal]").forEach((el) => el.classList.add("is-visible"));
      return;
    }
    if (!revealObserver) {
      revealObserver = new IntersectionObserver((entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) { entry.target.classList.add("is-visible"); revealObserver.unobserve(entry.target); }
        });
      }, { threshold: 0.1, rootMargin: "0px 0px -40px 0px" });
    }
    const pending = $$("[data-reveal]").filter((el) => !el.classList.contains("is-visible"));
    pending.forEach((el) => revealObserver.observe(el));
    /* Safety net: never allow content to stay hidden. If the observer fails
       to fire for any element within 3s (e.g. unsupported env), reveal all. */
    if (pending.length) {
      const ids = new Set(pending.map((el) => el));
      setTimeout(() => {
        ids.forEach((el) => { if (el && el.classList && !el.classList.contains("is-visible")) el.classList.add("is-visible"); });
      }, 3000);
    }
  };

  /* ============================================================
     Active nav link
     ============================================================ */
  const setupActiveNav = () => {
    const sections = $$("main section[id]");
    const links = $$(".nav-links a[data-nav]");
    const map = new Map(links.map((l) => [l.getAttribute("href").slice(1), l]));
    if (!("IntersectionObserver" in window)) return;
    const obs = new IntersectionObserver((entries) => {
      const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
      if (!visible) return;
      links.forEach((l) => l.classList.remove("active"));
      map.get(visible.target.id)?.classList.add("active");
    }, { rootMargin: "-45% 0px -45% 0px", threshold: 0.2 });
    sections.forEach((s) => obs.observe(s));
  };

  /* ============================================================
     Tilt (fine pointer + no reduced motion)
     ============================================================ */
  const setupTilt = () => {
    if (!finePointer || reduceMotion || !window.matchMedia) return;
    const tiltables = () => $$(".repo-card, .expertise-card");
    let raf = 0;
    const onMove = (e, el) => {
      const r = el.getBoundingClientRect();
      const px = (e.clientX - r.left) / r.width - 0.5;
      const py = (e.clientY - r.top) / r.height - 0.5;
      el.style.transform = `perspective(700px) rotateY(${px * 5}deg) rotateX(${-py * 5}deg) translateY(-2px)`;
    };
    document.addEventListener("pointermove", (e) => {
      if (!raf) raf = requestAnimationFrame(() => {
        raf = 0;
        const t = e.target && e.target.closest ? e.target.closest(".repo-card, .expertise-card") : null;
        tiltables().forEach((el) => { if (el !== t) el.style.transform = ""; });
        if (t) onMove(e, t);
      });
    }, { passive: true });
  };

  /* ============================================================
     Init
     ============================================================ */
  const init = () => {
    rootEl.classList.add("has-js");
    applyLanguage(currentLang);

    // theme
    applyTheme();

    // menu
    const menuToggle = $(".menu-toggle");
    const navLinks = $(".nav-links");
    const setMenu = (open) => {
      navLinks.classList.toggle("is-open", open);
      menuToggle?.classList.toggle("is-open", open);
      menuToggle?.setAttribute("aria-expanded", String(open));
      body.classList.toggle("menu-open", open);
    };
    menuToggle?.addEventListener("click", () => setMenu(!navLinks.classList.contains("is-open")));
    navLinks?.querySelectorAll("a").forEach((a) => a.addEventListener("click", () => setMenu(false)));
    document.addEventListener("keydown", (e) => { if (e.key === "Escape") setMenu(false); });

    // lang
    $(".lang-toggle")?.addEventListener("click", () => {
      const next = currentLang === "ar" ? "en" : "ar";
      applyLanguage(next);
      store.set("lang", next);
      // repo list text re-rendered in applyLanguage (renderRepoControls),
      // but cards built with old lang — re-render cards if loaded
      if (reposLoaded) renderRepoList(reposCache);
    });

    // theme
    $(".theme-toggle")?.addEventListener("click", () => {
      const next = rootEl.dataset.theme === "dark" ? "light" : "dark";
      rootEl.dataset.theme = next;
      store.set("theme", next);
      const tc = $('meta[name="theme-color"]');
      if (tc) tc.content = next === "dark" ? "#070a16" : "#f6f8fc";
    });

    // scroll
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    $(".to-top")?.addEventListener("click", () =>
      window.scrollTo({ top: 0, behavior: reduceMotion ? "auto" : "smooth" })
    );

    // search
    const search = $("#repo-search");
    if (search) {
      let debounce;
      search.addEventListener("input", () => {
        clearTimeout(debounce);
        debounce = setTimeout(() => { searchQuery = search.value; page = 1; if (reposLoaded) renderRepoList(reposCache); }, 200);
      });
    }

    // footer year
    const y = $("#year");
    if (y) y.textContent = new Date().getFullYear();

    // nav scroll smoothing for same-page anchors
    $$('a[href^="#"]').forEach((a) => a.addEventListener("click", (e) => {
      const target = $(a.getAttribute("href"));
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
        history.replaceState(null, "", a.getAttribute("href"));
      }
    }));

    bindReveal();
    setupActiveNav();
    setupTilt();
    fetchRepos();
  };

  // theme applied before first paint for FOUC control
  const applyTheme = () => {
    const saved = store.get("theme");
    const light = saved === "light" || (!saved && window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches);
    rootEl.dataset.theme = light ? "light" : "dark";
  };

  const onScroll = () => {
    $(".to-top")?.classList.toggle("visible", window.scrollY > 600);
    $(".site-header")?.classList.toggle("scrolled", window.scrollY > 8);
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();