(() => {
  "use strict";

  const root = document.documentElement;
  const body = document.body;

  const getSavedValue = (key) => {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  };
  const saveValue = (key, value) => {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Preferences still work for the current session when storage is unavailable.
    }
  };

  const translations = {
    ar: {
      htmlLang: "ar",
      htmlDir: "rtl",
      metaDescription: " عبدالرحمن الربيعي — مطور واجهات ويب يصمم تجارب رقمية واضحة وسريعة.",
      ogTitle: "عبدالرحمن الربيعي ",
      ogDescription: "مطور واجهات ويب يصمم تجارب رقمية واضحة وسريعة.",
      pageTitle: "عبدالرحمن الربيعي  ",
      skipLink: "تخطَّ إلى المحتوى",
      navAria: "التنقل الرئيسي",
      brandName: "عبدالرحمن الربيعي",
      themeLabel: "تبديل المظهر",
      langToggleText: "EN",
      langToggleLabel: "Switch language",
      navStart: "لنبدأ",
      menuText: "فتح القائمة",
      navLinks: ["عني", "أعمالي", "مهاراتي", "تواصل"],
      heroEyebrow: "متاح للتعاون في المشاريع المميزة",
      heroTitle: "طالب هندسة حاسب <em>أبني حلولًا ذكية</em>",
      heroIntro: "أنا <strong>عبدالرحمن الربيعي</strong>، طالب في تخصص هندسة الحاسب، مهتم بتطوير الويب والذكاء الاصطناعي والرؤية الحاسوبية. أسعى إلى تطوير مهاراتي من خلال تنفيذ مشاريع عملية واكتساب خبرات جديدة في مجال البرمجة والتقنيات الحديثة.",
      heroPrimaryButton: "استكشف أعمالي",
      heroSecondaryButton: "تواصل معي <span aria-hidden=\"true\">↙</span>",
      heroFootnote: "أبني حلولًا يثق بها المستخدمون<br />ويفخر بها أصحاب المشاريع.",
      codeFooter: "متصل وجاهز للبناء",
      floatingTop: "تصميم يضع<br />الإنسان أولًا",
      floatingBottom: "أفكار <strong>حيّة</strong><br />على الويب",
      monogram: "ع",
      scrollCue: "اسحب للأسفل",
      scrollCueAria: "انتقل إلى قسم عني",
      marquee: ["واجهات ويب", "تجربة مستخدم", "تصميم بصري", "تطوير حديث", "حلول رقمية"],
      aboutLabel: "نبذة مختصرة",
      aboutTitle: "أؤمن أن التفاصيل الصغيرة تصنع <em>فرقًا كبيرًا.</em>",
      aboutParagraphs: [
        "أنا طالب في تخصص هندسة الحاسب، مهتم بتطوير الويب والذكاء الاصطناعي والرؤية الحاسوبية. أسعى إلى تطوير مهاراتي من خلال تنفيذ مشاريع عملية واكتساب خبرات جديدة في مجال البرمجة والتقنيات الحديثة.",
        ""
      ],
      aboutLink: "لنتعاون في مشروعك <span aria-hidden=\"true\">←</span>",
      factTitle: "ما يهمني في كل مشروع",
      factItems: ["وضوح الفكرة", "جودة التنفيذ", "أثر قابل للقياس"],
      factSignature: "ع.",
      workLabel: "مختارات من أعمالي",
      workTitle: "مشاريع مطوّرة لحل مشاكل <em>حقيقية.</em>",
      workText: "هذا المشروع يوضح دمج الذكاء الاصطناعي مع الرؤية الحاسوبية في تجربة تفاعلية فورية.",
      projectTypes: ["ذكاء اصطناعي · رؤية حاسوبية"],
      projectTitles: ["DriveThruGestureAI — نظام ذكي للطلبات بالإيماءات"],
      projectAria: ["فتح مشروع DriveThruGestureAI على GitHub"],
      skillsLabel: "أدواتي ومهاراتي",
      skillsTitle: "من الفكرة الأولى حتى <em>الإطلاق.</em>",
      skillsText: "",
      skillTitles: ["HTML5", "CSS3", "JavaScript", "Git & GitHub", "الذكاء الاصطناعي", "الرؤية الحاسوبية", "تصميم متجاوب"],
      skillTexts: [
        "بناء هياكل صفحات ويب معيارية وسهلة الوصول.",
        "تصميم مرن وجذاب مع قواعد متقدمة واستجابة للشاشات.",
        "تفاعلات وصفحات ديناميكية باستخدام JS نظيف وفعال.",
        "إدارة الإصدارات، التعاون، ونشر المشاريع على GitHub.",
        "مبادئ ونماذج أساسية لتطبيقات الذكاء الاصطناعي.",
        "معالجة الصور والتعرف على الإيماءات والميزات البصرية.",
        "تصميم يتكيّف مع جميع أحجام الشاشات لتجربة موحدة."
      ],
      quote: "أفضل المواقع لا تحتاج أن تشرح نفسها؛ <em>تجربتها</em> تقول كل شيء.",
      contactEyebrow: "الخطوة التالية تبدأ برسالة",
      contactTitle: "هل لديك فكرة تستحق أن <em>تظهر؟</em>",
      contactText: "أخبرني عنها، ولنحوّلها إلى تجربة رقمية تترك انطباعًا حقيقيًا.",
      socialAria: "روابط التواصل الاجتماعي",
      contactCircle: "لنصنع<br />شيئًا<br /><i>مميزًا</i>",
      footerText: "صُنع بعناية وشغف <span aria-hidden=\"true\">✦</span> <span id=\"year\"></span>",
      footerTop: "للأعلى <span aria-hidden=\"true\">↑</span>",
      backToTopLabel: "العودة إلى أعلى الصفحة",
      dialogCloseLabel: "إغلاق نافذة المشروع",
      dialogEyebrow: "نموذج مشروع",
      dialogTitle: "مشروع",
      dialogText: "هذه بطاقة عرض تجريبية. استبدلها لاحقًا برابط المشروع وصوره ووصف مختصر للدور الذي قمت به والنتائج التي حققها المشروع.",
      dialogButton: "حسنًا",
      dialogFallbackTitle: "تفاصيل المشروع",
      codeName: "Abdulrahman Al-Rubaie",
      nawaGreeting: "صباح الخير، عبدالله <span>☀</span>",
      waslTrack: "تتبع طلبك",
      waslHeadline: "طريقك أقرب مما تتوقع.",
      waslStatus: "الطلب في الطريق إليك",
      auroraLabel: "ذكاء اصطناعي",
      auroraTitle: "نظام ذكي<br />للطلبات بالإيماءات",
    },
    en: {
      htmlLang: "en",
      htmlDir: "ltr",
      metaDescription: "Abdulrahman Al-Rubaie  — front-end developer crafting clear and fast digital experiences.",
      ogTitle: "Abdulrahman Al-Rubaie ",
      ogDescription: "Front-end developer crafting clear and fast digital experiences.",
      pageTitle: "Abdulrahman Al-Rubaie ",
      skipLink: "Skip to content",
      navAria: "Main navigation",
      brandName: "Abdulrahman Al-Rubaie",
      themeLabel: "Toggle theme",
      langToggleText: "ع",
      langToggleLabel: "تبديل اللغة",
      navStart: "Start a project",
      menuText: "Open menu",
      navLinks: ["About", "Work", "Skills", "Contact"],
      heroEyebrow: "Available for standout collaborations",
      heroTitle: "Computer Engineering Student <em>building intelligent solutions.</em>",
      heroIntro: "I am <strong>Abdulrahman Al-Rubaie</strong>, a Computer Engineering student interested in Web Development, Artificial Intelligence, and Computer Vision. I enjoy building practical projects and continuously improving my programming skills.",
      heroPrimaryButton: "Explore my work",
      heroSecondaryButton: "Contact me <span aria-hidden=\"true\">↘</span>",
      heroFootnote: "I build products users trust<br />and teams are proud to launch.",
      codeFooter: "Online and ready to build",
      floatingTop: "Human-first<br />design mindset",
      floatingBottom: "Ideas brought <strong>to life</strong><br />on the web",
      monogram: "A",
      scrollCue: "Scroll down",
      scrollCueAria: "Jump to about section",
      marquee: ["Web Interfaces", "User Experience", "Visual Design", "Modern Development", "Digital Solutions"],
      aboutLabel: "Quick profile",
      aboutTitle: "Small details make a <em>big difference.</em>",
      aboutParagraphs: [
        "I am a Computer Engineering student interested in Web Development, Artificial Intelligence, and Computer Vision. I enjoy building practical projects and continuously improving my programming skills.",
        ""
      ],
      aboutLink: "Let us collaborate on your project <span aria-hidden=\"true\">→</span>",
      factTitle: "What matters in every project",
      factItems: ["Clear idea", "Quality execution", "Measurable impact"],
      factSignature: "A.",
      workLabel: "Selected projects",
      workTitle: "Projects built to solve <em>real problems.</em>",
      workText: "This project demonstrates AI and computer vision in a real-time interactive use case.",
      projectTypes: ["Artificial Intelligence · Computer Vision"],
      projectTitles: ["DriveThruGestureAI — AI-Powered Gesture-Based Ordering System"],
      projectAria: ["Open DriveThruGestureAI on GitHub"],
      skillsLabel: "Tools and skills",
      skillsTitle: "From concept to <em>launch.</em>",
      skillsText: "I choose tools that make outcomes clearer, faster, and easier to scale.",
      skillTitles: ["HTML5", "CSS3", "JavaScript", "Git & GitHub", "Artificial Intelligence", "Computer Vision", "Responsive Web Design"],
      skillTexts: [
        "Building semantic, accessible page structures.",
        "Flexible and modern styling for responsive layouts.",
        "Interactive behavior and dynamic pages with clean JS.",
        "Version control, collaboration, and GitHub workflows.",
        "Fundamentals and applied models for AI applications.",
        "Image processing, gesture recognition, and visual features.",
        "Design that adapts across all screen sizes for a consistent experience."
      ],
      quote: "The best websites do not need to explain themselves; the <em>experience</em> says it all.",
      contactEyebrow: "The next step starts with a message",
      contactTitle: "Do you have an idea that deserves to <em>stand out?</em>",
      contactText: "Tell me about it, and we will turn it into a digital experience with real impact.",
      socialAria: "Social links",
      contactCircle: "Let us build<br />something<br /><i>remarkable</i>",
      footerText: "Crafted with care and passion <span aria-hidden=\"true\">✦</span> <span id=\"year\"></span>",
      footerTop: "Back to top <span aria-hidden=\"true\">↑</span>",
      backToTopLabel: "Back to top",
      dialogCloseLabel: "Close project dialog",
      dialogEyebrow: "Project preview",
      dialogTitle: "Project",
      dialogText: "This is a demo card. Replace it later with your project URL, visuals, your role, and measurable outcomes.",
      dialogButton: "Got it",
      dialogFallbackTitle: "Project details",
      codeName: "Abdulrahman Al-Rubaie",
      nawaGreeting: "Good morning, Abdullah <span>☀</span>",
      waslTrack: "Track your order",
      waslHeadline: "Your destination is closer than you think.",
      waslStatus: "Your order is on the way",
      auroraLabel: "Artificial Intelligence",
      auroraTitle: "AI-Powered Gesture<br />Ordering System",
    }
  };

  const setText = (selector, text) => {
    const node = document.querySelector(selector);
    if (node && typeof text === "string") node.textContent = text;
  };
  const setHTML = (selector, html) => {
    const node = document.querySelector(selector);
    if (node && typeof html === "string") node.innerHTML = html;
  };
  const setAttr = (selector, attr, value) => {
    const node = document.querySelector(selector);
    if (node && typeof value === "string") node.setAttribute(attr, value);
  };
  const setManyText = (selector, values) => {
    document.querySelectorAll(selector).forEach((node, index) => {
      const value = values[index];
      if (typeof value === "string") node.textContent = value;
    });
  };

  let currentLang = getSavedValue("portfolio-lang") === "en" ? "en" : "ar";
  const applyLanguage = (lang) => {
    const copy = translations[lang] || translations.ar;
    currentLang = lang;

    root.lang = copy.htmlLang;
    root.dir = copy.htmlDir;
    body?.classList.toggle("lang-en", lang === "en");

    const metaDescription = document.querySelector('meta[name="description"]');
    const ogTitle = document.querySelector('meta[property="og:title"]');
    const ogDescription = document.querySelector('meta[property="og:description"]');
    if (metaDescription) metaDescription.content = copy.metaDescription;
    if (ogTitle) ogTitle.content = copy.ogTitle;
    if (ogDescription) ogDescription.content = copy.ogDescription;
    document.title = copy.pageTitle;

    setText(".skip-link", copy.skipLink);
    setAttr(".nav", "aria-label", copy.navAria);
    setHTML(".site-header .brand > span:last-child", copy.brandName);
    setHTML(".site-footer .brand > span:last-child", copy.brandName);
    setAttr(".theme-toggle", "aria-label", copy.themeLabel);
    setAttr(".theme-toggle", "title", copy.themeLabel);
    setText(".lang-toggle", copy.langToggleText);
    setAttr(".lang-toggle", "aria-label", copy.langToggleLabel);
    setAttr(".lang-toggle", "title", copy.langToggleLabel);
    setText(".nav-cta", copy.navStart);
    setText(".menu-toggle .sr-only", copy.menuText);
    setManyText(".nav-links a", copy.navLinks);

    setHTML(".hero-copy .eyebrow", `<span class=\"status-dot\"></span> ${copy.heroEyebrow}`);
    setHTML("#hero-title", copy.heroTitle);
    setHTML(".hero-intro", copy.heroIntro);
    setHTML(
      ".hero-actions .button",
      `${copy.heroPrimaryButton}<svg viewBox=\"0 0 24 24\" aria-hidden=\"true\"><path d=\"M4 12h15M14 6l6 6-6 6\"></path></svg>`
    );
    setHTML(".hero-actions .text-link", copy.heroSecondaryButton);
    setHTML(".hero-footnote p", copy.heroFootnote);

    setHTML(".code-window pre code", `<span class=\"code-key\">const</span> <span class=\"code-variable\">creator</span> = {
  <span class=\"code-property\">name</span>: <span class=\"code-string\">'${copy.codeName}'</span>,
  <span class=\"code-property\">focus</span>: [
    <span class=\"code-string\">'Design'</span>,
    <span class=\"code-string\">'Development'</span>
  ],
  <span class=\"code-property\">goal</span>: <span class=\"code-string\">'Make it memorable'</span>
};`);
    setHTML(".code-footer", `<span>●</span> ${copy.codeFooter}`);
    setHTML(".card-top p", copy.floatingTop);
    setHTML(".card-bottom p", copy.floatingBottom);
    setText(".hero-monogram", copy.monogram);
    setText(".scroll-cue span", copy.scrollCue);
    setAttr(".scroll-cue", "aria-label", copy.scrollCueAria);

    const marqueeWords = [...copy.marquee, ...copy.marquee];
    setManyText(".marquee-track span", marqueeWords);

    setText("#about .section-label p", copy.aboutLabel);
    setHTML("#about-title", copy.aboutTitle);
    const aboutParagraphs = document.querySelectorAll(".about-copy > p");
    if (aboutParagraphs[0]) aboutParagraphs[0].textContent = copy.aboutParagraphs[0];
    if (aboutParagraphs[1]) aboutParagraphs[1].textContent = copy.aboutParagraphs[1];
    setHTML(".about-copy .inline-link", copy.aboutLink);
    setText(".fact-card-title", copy.factTitle);
    document.querySelectorAll(".fact-card li").forEach((item, index) => {
      const number = item.querySelector("span")?.textContent || String(index + 1).padStart(2, "0");
      const textNode = copy.factItems[index] || "";
      item.innerHTML = `<span>${number}</span> ${textNode}`;
    });
    setText(".fact-card-signature", copy.factSignature);

    setText("#work .section-label p", copy.workLabel);
    setHTML("#work-title", copy.workTitle);
    setText(".section-heading > p", copy.workText);
    setManyText(".project-type", copy.projectTypes);
    setManyText(".project-info h3", copy.projectTitles);
    setText("#aurora-label", copy.auroraLabel);
    setHTML("#aurora-title", copy.auroraTitle);
    document.querySelectorAll(".project-open").forEach((button, index) => {
      if (copy.projectTitles[index]) button.dataset.project = copy.projectTitles[index];
      if (copy.projectAria[index]) button.setAttribute("aria-label", copy.projectAria[index]);
    });
    setHTML(".nawa-dashboard > p", copy.nawaGreeting);
    setText(".wasl-top span", copy.waslTrack);
    setText(".wasl-main h4", copy.waslHeadline);
    setText(".wasl-main p", copy.waslStatus);

    setText("#skills .section-label p", copy.skillsLabel);
    setHTML("#skills-title", copy.skillsTitle);
    setText(".skills-intro > p", copy.skillsText);
    setManyText(".skill-list h3", copy.skillTitles);
    setManyText(".skill-list article p", copy.skillTexts);

    setHTML(".quote-section blockquote p", copy.quote);

    setHTML("#contact .contact-content .eyebrow", `<span class=\"status-dot\"></span> ${copy.contactEyebrow}`);
    setHTML("#contact-title", copy.contactTitle);
    setText(".contact-content > p:not(.eyebrow)", copy.contactText);
    setAttr(".social-links", "aria-label", copy.socialAria);
    setHTML(".contact-circle span", copy.contactCircle);

    setHTML(".site-footer > p", copy.footerText);
    setHTML(".footer-top", copy.footerTop);
    setAttr(".back-to-top", "aria-label", copy.backToTopLabel);

    setAttr(".dialog-close", "aria-label", copy.dialogCloseLabel);
    setText(".project-dialog .eyebrow", copy.dialogEyebrow);
    setText("#dialog-title", copy.dialogTitle);
    setText(".project-dialog > p:not(.eyebrow)", copy.dialogText);
    setText(".dialog-close-text", copy.dialogButton);

    const year = document.querySelector("#year");
    if (year) year.textContent = new Date().getFullYear();
  };

  applyLanguage(currentLang);

  const themeToggle = document.querySelector(".theme-toggle");
  const savedTheme = getSavedValue("portfolio-theme");
  const systemPrefersLight = window.matchMedia("(prefers-color-scheme: light)").matches;

  if (savedTheme === "light" || (!savedTheme && systemPrefersLight)) {
    root.dataset.theme = "light";
  }

  themeToggle?.addEventListener("click", () => {
    const isLight = root.dataset.theme === "light";
    if (isLight) {
      delete root.dataset.theme;
      saveValue("portfolio-theme", "dark");
    } else {
      root.dataset.theme = "light";
      saveValue("portfolio-theme", "light");
    }
  });

  const langToggle = document.querySelector(".lang-toggle");
  langToggle?.addEventListener("click", () => {
    const nextLang = currentLang === "ar" ? "en" : "ar";
    applyLanguage(nextLang);
    saveValue("portfolio-lang", nextLang);
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
      { rootMargin: "-45% 0px -45% 0px", threshold: 0.3 }
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
      if (dialogTitle) dialogTitle.textContent = button.dataset.project || translations[currentLang].dialogFallbackTitle;
      if (typeof dialog?.showModal === "function") dialog.showModal();
    });
  });
  document.querySelectorAll(".dialog-close, .dialog-close-text").forEach((button) => button.addEventListener("click", () => dialog?.close()));
  dialog?.addEventListener("click", (event) => {
    const bounds = dialog.getBoundingClientRect();
    const isOutside = event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom;
    if (isOutside) dialog.close();
  });

  if (!reducedMotion && window.matchMedia("(pointer: fine)").matches) {
    const glow = document.querySelector(".cursor-glow");
    window.addEventListener("pointermove", (event) => {
      if (glow) glow.style.transform = `translate(${event.clientX - 224}px, ${event.clientY - 224}px)`;
    }, { passive: true });
  }
})();
document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (e) => {
    e.preventDefault();

    const target = document.querySelector(link.getAttribute("href"));
    if (!target) return;

    target.scrollIntoView({
      behavior: "smooth",
      block: "start",
    });

    history.replaceState(
      null,
      "",
      window.location.pathname + window.location.search
    );
  });
});
