import { CACHE_KEY, normalizeRepositories, repositoryPresentation, filterRepositories, readRepositoryCache, fetchPublicRepositories } from './repositories.mjs';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const root = document.documentElement;
const preferences = {
  get(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch (_) {} },
};

const COPY = {
  ar: {
    title: 'عبدالرحمن الربيعي | هندسة الحاسب',
    description: 'عبدالرحمن الربيعي، مهندس حاسب. مشاريع عملية في الذكاء الاصطناعي، تطوير الويب، الروبوتات والأنظمة المضمنة. الرياض، السعودية.',
    name: 'عبدالرحمن الربيعي', discipline: 'هندسة الحاسب', skip: 'تخطَّ إلى المحتوى',
    brandLabel: 'عبدالرحمن الربيعي — الرئيسية', navLabel: 'التنقل الرئيسي',
    navProjects: 'المشاريع', navAbout: 'عني', navExpertise: 'المهارات', navJourney: 'التجربة', navContact: 'تواصل',
    available: 'متاح للفرص المهنية', intro: 'مرحبًا، أنا عبدالرحمن الربيعي',
    heroA: 'أربط الفكرة', heroB: 'بالعالم الحقيقي.',
    heroDescription: 'مهندس حاسب أبني مشاريع تجمع بين البرمجيات والأنظمة الذكية؛ من الرؤية الحاسوبية إلى الويب والروبوتات.',
    explore: 'استكشف أعمالي', location: 'الرياض، المملكة العربية السعودية', scroll: 'تعرّف على عملي',
    projectsLabel: 'من الفكرة إلى التطبيق', projectsTitle: 'مساحات أبني فيها.',
    projectsDescription: 'مجموعة أعمالي في البرمجيات والهندسة. كل مستودع يجمع مشاريعه وتوثيقها، ويتحدث هذا القسم تلقائيًا مع إضافة أعمال جديدة.',
    allOnGithub: 'جميع المستودعات على GitHub', filtersLabel: 'تصفية المستودعات',
    searchPlaceholder: 'ابحث عن مستودع…', searchLabel: 'ابحث عن مستودع', paginationLabel: 'صفحات المستودعات',
    aboutLabel: 'خلف كل مشروع', aboutA: 'فضول هندسي.', aboutB: 'وتعلّم بالممارسة.',
    aboutLead: 'أنا عبدالرحمن الربيعي، حاصل على بكالوريوس هندسة الحاسب من جامعة الطائف. أهتم بما يحدث عندما تلتقي البرمجيات بالعالم المادي.',
    aboutBody: 'أطوّر مهاراتي عبر مشاريع في الذكاء الاصطناعي وتطوير الويب والأنظمة المضمنة. يجذبني العمل على النظام كاملًا: كيف يستشعر، وكيف يعالج البيانات، وكيف يتفاعل مع المستخدم.',
    educationLabel: 'التعليم', education: 'بكالوريوس هندسة الحاسب', university: 'جامعة الطائف',
    accreditationLabel: 'الاعتماد المهني', accreditation: 'عضو الهيئة السعودية للمهندسين', focus: 'هندسة الحاسب والأنظمة الذكية',
    expertiseLabel: 'الأدوات التي أعمل بها', expertiseTitle: 'أكثر من زاوية للحل.', expertiseNote: 'مهارات طوّرتها بالتعلّم والتطبيق في مشاريعي.',
    journeyLabel: 'تجربة عملية', journeyTitle: 'التخصص يتكامل.',
    journeyDescription: 'تدريبي التعاوني في شركة الأساليب الذكية جمعني بأربعة مسارات هندسية، بتركيز رئيسي على الذكاء الاصطناعي والروبوتات وROS.',
    trainingLabel: 'تدريب تعاوني · AI & Robotics',
    contactLabel: 'لنبدأ محادثة', contactA: 'فرصة جديدة؟', contactB: 'يسعدني التواصل.',
    contactDescription: 'مفتوح للفرص المهنية والتعاون في المجالات التقنية والهندسية المرتبطة بهندسة الحاسب.',
    emailLabel: 'راسل عبدالرحمن بالبريد الإلكتروني', sayHello: 'تواصل معي', backTop: 'العودة للأعلى',
    openMenu: 'فتح القائمة', closeMenu: 'إغلاق القائمة', lightTheme: 'تفعيل المظهر الفاتح', darkTheme: 'تفعيل المظهر الداكن',
    retry: 'إعادة المحاولة', reset: 'مسح البحث والتصفية', loading: 'جارٍ تحديث المستودعات…', cached: 'من آخر نسخة محفوظة',
    error: 'تعذّر التحديث الآن؛ أعرض آخر نسخة محفوظة.', failed: 'تعذّر تحميل المستودعات. يمكنك استعراضها على GitHub.',
    rate: 'GitHub غير متاح مؤقتًا؛ أعرض آخر نسخة محفوظة.',
    emptyTitle: 'لا توجد مستودعات عامة بعد.', noResults: 'ما لقينا نتيجة مطابقة.', noResultsHint: 'جرّب اسمًا آخر أو غيّر التصفية.',
    repositoryCount: count => `${count.toLocaleString('ar-SA')} مستودع`,
    pageLabel: page => `الصفحة ${page}`, pageStatus: (count, page, pages) => `${count} مستودع، الصفحة ${page} من ${pages}`,
    openRepository: name => `استعراض مستودع ${name} على GitHub`, live: 'عرض مباشر', updated: 'آخر تعديل', stars: 'نجوم', forks: 'تفرّعات', archived: 'مؤرشف', fork: 'نسخة',
    categories: { all: 'الكل', ai: 'الذكاء الاصطناعي', web: 'الويب', systems: 'الأنظمة', iot: 'الإلكترونيات', mechanical: 'الميكانيكا', other: 'أخرى' },
    expertise: [
      ['الذكاء الاصطناعي والرؤية الحاسوبية', 'نماذج تتعامل مع الصور والصوت.'],
      ['تطوير الويب', 'من واجهة المستخدم إلى التكامل مع الخدمات.'],
      ['الروبوتات والأنظمة المضمنة', 'ربط البرمجيات بالأجهزة والتحكّم.'],
      ['الإلكترونيات وإنترنت الأشياء', 'دوائر ومستشعرات وتطبيقات تحكّم.'],
      ['التصميم الميكانيكي', 'تصميم أجزاء الروبوت وفهم حركته.'],
    ],
    tracks: [
      ['الذكاء الاصطناعي والروبوتات', 'المسار الرئيسي: الرؤية الحاسوبية وROS وتفاعل الإنسان مع الأنظمة.'],
      ['تطوير الويب ومعالجة اللغة', 'واجهات وتطبيقات ومساعدات صوتية.'],
      ['الهندسة الكهربائية وإنترنت الأشياء', 'المستشعرات والدوائر وبرمجة المتحكمات.'],
      ['الهندسة الميكانيكية', 'التصميم ثلاثي الأبعاد وأجزاء الروبوت.'],
    ],
  },
  en: {
    title: 'Abdulrahman Al-Rubaie | Computer Engineering',
    description: 'Abdulrahman Al-Rubaie, Computer Engineer. Hands-on projects in AI, web development, robotics, and embedded systems. Based in Riyadh, Saudi Arabia.',
    name: 'Abdulrahman Al-Rubaie', discipline: 'Computer Engineering', skip: 'Skip to content',
    brandLabel: 'Abdulrahman Al-Rubaie — Home', navLabel: 'Main navigation',
    navProjects: 'Projects', navAbout: 'About', navExpertise: 'Skills', navJourney: 'Experience', navContact: 'Contact',
    available: 'Open to opportunities', intro: 'Hello, I’m Abdulrahman Al-Rubaie',
    heroA: 'Ideas meet', heroB: 'the real world.',
    heroDescription: 'Computer Engineer building at the intersection of software and intelligent systems. From computer vision to the web and robotics.',
    explore: 'Explore my work', location: 'Riyadh, Saudi Arabia', scroll: 'Discover my work',
    projectsLabel: 'From ideas to implementation', projectsTitle: 'Where I build.',
    projectsDescription: 'My work across software and engineering. Each repository brings its projects and documentation together. New public repositories appear here automatically.',
    allOnGithub: 'All repositories on GitHub', filtersLabel: 'Filter repositories',
    searchPlaceholder: 'Search repositories…', searchLabel: 'Search repositories', paginationLabel: 'Repository pages',
    aboutLabel: 'Behind the projects', aboutA: 'Curious by nature.', aboutB: 'Learning by building.',
    aboutLead: 'I’m Abdulrahman Al-Rubaie, with a bachelor’s degree in Computer Engineering from Taif University. I’m interested in what happens when software meets the physical world.',
    aboutBody: 'I develop my skills through projects in AI, web development, and embedded systems. I enjoy thinking about the whole system: how it senses, processes data, and interacts with people.',
    educationLabel: 'Education', education: 'Bachelor’s in Computer Engineering', university: 'Taif University',
    accreditationLabel: 'Professional accreditation', accreditation: 'Member, Saudi Council of Engineers', focus: 'Computer engineering & intelligent systems',
    expertiseLabel: 'Tools of the trade', expertiseTitle: 'More ways to solve.', expertiseNote: 'Skills developed through learning and hands-on projects.',
    journeyLabel: 'Hands-on experience', journeyTitle: 'Connected disciplines.',
    journeyDescription: 'My cooperative training at Smart Methods covered four engineering tracks, with a primary focus on AI, robotics, and ROS.',
    trainingLabel: 'Cooperative training · AI & Robotics',
    contactLabel: 'Start a conversation', contactA: 'A new opportunity?', contactB: 'Let’s connect.',
    contactDescription: 'Open to professional opportunities and collaboration across technical and engineering fields related to Computer Engineering.',
    emailLabel: 'Email Abdulrahman', sayHello: 'Say hello', backTop: 'Back to top',
    openMenu: 'Open menu', closeMenu: 'Close menu', lightTheme: 'Switch to light theme', darkTheme: 'Switch to dark theme',
    retry: 'Try again', reset: 'Clear search and filters', loading: 'Updating repositories…', cached: 'From the latest saved copy',
    error: 'Could not refresh. Showing the latest saved copy.', failed: 'Could not load repositories. You can explore them on GitHub.',
    rate: 'GitHub is temporarily unavailable. Showing the latest saved copy.',
    emptyTitle: 'No public repositories yet.', noResults: 'No matching repositories.', noResultsHint: 'Try another name or change the filter.',
    repositoryCount: count => `${count} ${count === 1 ? 'repository' : 'repositories'}`,
    pageLabel: page => `Page ${page}`, pageStatus: (count, page, pages) => `${count} repositories. Page ${page} of ${pages}.`,
    openRepository: name => `Explore ${name} on GitHub`, live: 'Live demo', updated: 'Updated', stars: 'stars', forks: 'forks', archived: 'Archived', fork: 'Fork',
    categories: { all: 'All', ai: 'AI & Robotics', web: 'Web', systems: 'Systems', iot: 'Electronics', mechanical: 'Mechanical', other: 'Other' },
    expertise: [
      ['AI & Computer Vision', 'Models that work with images and speech.'],
      ['Web Development', 'From the user interface to connected services.'],
      ['Robotics & Embedded Systems', 'Connecting software, devices, and control.'],
      ['Electronics & IoT', 'Circuits, sensors, and control applications.'],
      ['Mechanical Design', 'Designing robot parts and understanding motion.'],
    ],
    tracks: [
      ['AI & Robotics', 'Primary track: computer vision, ROS, and human-system interaction.'],
      ['Web Development & NLP', 'Interfaces, applications, and voice assistants.'],
      ['Electrical Engineering & IoT', 'Sensors, circuits, and microcontroller programming.'],
      ['Mechanical Engineering', '3D design and robot components.'],
    ],
  },
};

let language = preferences.get('lang') === 'en' ? 'en' : 'ar';
let repositories = [];
let category = 'all';
let query = '';
let page = 1;
let repositoryState = 'loading';
let loading = false;
const PAGE_SIZE = 6;
const externalPath = 'M7 17 17 7M7 7h10v10';
const cached = readRepositoryCache(preferences.get(CACHE_KEY));

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}
function externalIcon() {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('aria-hidden', 'true');
  const path = document.createElementNS('http://www.w3.org/2000/svg', 'path');
  path.setAttribute('d', externalPath);
  svg.append(path);
  return svg;
}
function externalLink(url, label, className = 'repo-link') {
  const link = element('a', className);
  link.href = url;
  link.target = '_blank';
  link.rel = 'noopener noreferrer';
  link.append(element('span', '', label), externalIcon());
  return link;
}
function updateTheme() {
  const t = COPY[language];
  const isDark = root.dataset.theme !== 'light';
  $('.theme-toggle').setAttribute('aria-label', isDark ? t.lightTheme : t.darkTheme);
  $('.theme-toggle').title = isDark ? t.lightTheme : t.darkTheme;
  $('meta[name="theme-color"]').content = isDark ? '#101211' : '#f4f6f0';
}
function setMenu(open, restoreFocus = false) {
  $('#nav-menu').classList.toggle('is-open', open);
  $('.menu-toggle').setAttribute('aria-expanded', String(open));
  $('.menu-toggle').setAttribute('aria-label', open ? COPY[language].closeMenu : COPY[language].openMenu);
  document.body.classList.toggle('menu-open', open);
  if (restoreFocus) $('.menu-toggle').focus();
}
function applyLanguage(next) {
  language = next;
  const t = COPY[language];
  root.lang = language;
  root.dir = language === 'ar' ? 'rtl' : 'ltr';
  document.title = t.title;
  $('meta[name="description"]').content = t.description;
  // Keep social metadata in sync, preserving the existing social image.
  $('meta[property="og:title"]').content = t.title;
  $('meta[property="og:description"]').content = t.description;
  $('meta[name="twitter:title"]').content = t.title;
  $('meta[name="twitter:description"]').content = t.description;
  $('meta[property="og:locale"]').content = language === 'ar' ? 'ar_AR' : 'en_US';
  $('meta[property="og:locale:alternate"]').content = language === 'ar' ? 'en_US' : 'ar_AR';
  $$('[data-i18n]').forEach(node => { if (typeof t[node.dataset.i18n] === 'string') node.textContent = t[node.dataset.i18n]; });
  $$('[data-i18n-aria]').forEach(node => node.setAttribute('aria-label', t[node.dataset.i18nAria]));
  const toggle = $('.lang-toggle');
  toggle.textContent = language === 'ar' ? 'EN' : 'ع';
  toggle.lang = language === 'ar' ? 'en' : 'ar';
  toggle.setAttribute('aria-label', language === 'ar' ? 'Switch to English' : 'التبديل إلى العربية');
  toggle.title = toggle.getAttribute('aria-label');
  $('#repo-search').placeholder = t.searchPlaceholder;
  $('#repo-search').setAttribute('aria-label', t.searchLabel);
  $$('#expertise-grid article').forEach((card, i) => {
    card.querySelector('h3').textContent = t.expertise[i][0];
    card.querySelector('p').textContent = t.expertise[i][1];
  });
  $$('#journey-tracks article').forEach((card, i) => {
    card.querySelector('h3').textContent = t.tracks[i][0];
    card.querySelector('p').textContent = t.tracks[i][1];
  });
  $('.menu-toggle').setAttribute('aria-label', $('.menu-toggle').getAttribute('aria-expanded') === 'true' ? t.closeMenu : t.openMenu);
  updateTheme();
  renderFilters();
  renderRepositories();
}
function renderFilters(focusCategory) {
  const categories = ['all', ...new Set(repositories.map(repo => repo.category))];
  if (!categories.includes(category)) category = 'all';
  $('#repo-filters').replaceChildren(...categories.map(value => {
    const button = element('button', 'filter-btn', COPY[language].categories[value]);
    button.type = 'button';
    button.dataset.category = value;
    button.setAttribute('aria-pressed', String(category === value));
    return button;
  }));
  if (focusCategory) [...$('#repo-filters').children].find(button => button.dataset.category === focusCategory)?.focus({ preventScroll: true });
}
function repoCard(repo, index) {
  const t = COPY[language];
  const presentation = repositoryPresentation(repo, language);
  const card = element('article', 'repo-card');
  const top = element('div', 'repo-top');
  const label = element('span', 'repo-category', t.categories[repo.category]);
  if (repo.archived) label.append(element('span', 'repo-badge', t.archived));
  if (repo.isFork) label.append(element('span', 'repo-badge', t.fork));
  top.append(label, element('span', 'repo-index', String(index + 1).padStart(2, '0')));
  const heading = element('h3', 'repo-name', presentation.title);
  heading.dir = 'ltr';
  const description = element('p', 'repo-description', presentation.description);
  description.dir = 'auto';
  const tags = element('ul', 'repo-tags');
  presentation.tags.forEach(tag => { const item = element('li', '', tag); item.dir = 'ltr'; tags.append(item); });
  const footer = element('div', 'repo-footer');
  const meta = element('div', 'repo-meta');
  const pushed = new Date(repo.pushed || repo.updated);
  if (Number.isFinite(pushed.getTime())) {
    const date = element('time', '', `${t.updated} ${new Intl.DateTimeFormat(language === 'ar' ? 'ar-SA-u-ca-gregory' : 'en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).format(pushed)}`);
    date.dateTime = pushed.toISOString();
    meta.append(date);
  }
  if (repo.stars) meta.append(element('span', '', `${repo.stars} ${t.stars}`));
  if (repo.forks) meta.append(element('span', '', `${repo.forks} ${t.forks}`));
  const actions = element('div', 'repo-actions');
  const github = externalLink(repo.url, 'GitHub');
  github.setAttribute('aria-label', t.openRepository(repo.name));
  actions.append(github);
  if (repo.homepage) actions.append(externalLink(repo.homepage, t.live));
  footer.append(meta, actions);
  card.append(top, heading, description, tags, footer);
  return card;
}
function renderStatus() {
  const t = COPY[language];
  const status = $('#repo-status');
  const fallbackState = ['error', 'rate'].includes(repositoryState) && repositories.length === 0 ? 'failed' : repositoryState;
  status.textContent = repositoryState === 'live' ? '' : (t[fallbackState] || '');
  $('#retry-repos').hidden = !['error', 'rate', 'failed'].includes(repositoryState);
  $('#retry-repos').disabled = loading;
  $('#repo-list').setAttribute('aria-busy', String(loading || repositoryState === 'loading'));
}
function renderRepositories() {
  const t = COPY[language];
  const filtered = filterRepositories(repositories, category, query);
  const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  page = Math.min(page, pages);
  const start = (page - 1) * PAGE_SIZE;
  const list = $('#repo-list');
  $('#repos-count').textContent = t.repositoryCount(filtered.length);
  $('#repo-announcement').textContent = t.pageStatus(filtered.length, page, pages);
  renderStatus();
  if (filtered.length) {
    list.replaceChildren(...filtered.slice(start, start + PAGE_SIZE).map((repo, i) => repoCard(repo, start + i)));
  } else if ((loading || repositoryState === 'loading') && !repositories.length) {
    list.replaceChildren();
  } else {
    const empty = element('div', 'repo-empty');
    const searching = Boolean(query.trim()) || category !== 'all';
    const failed = ['error', 'rate', 'failed'].includes(repositoryState);
    empty.append(element('h3', '', searching ? t.noResults : failed ? t.failed : t.emptyTitle));
    if (searching) {
      const reset = element('button', 'text-link', t.reset);
      reset.type = 'button';
      reset.addEventListener('click', () => {
        query = ''; category = 'all'; page = 1; $('#repo-search').value = '';
        renderFilters(); renderRepositories(); $('#repo-search').focus();
      });
      empty.append(element('p', '', t.noResultsHint), reset);
    } else empty.append(externalLink('https://github.com/DevRah0?tab=repositories', t.allOnGithub, 'text-link'));
    list.replaceChildren(empty);
  }
  $('#repo-pagination').replaceChildren();
  if (pages > 1) {
    for (let number = 1; number <= pages; number++) {
      const button = element('button', 'page-button', String(number));
      button.type = 'button';
      button.dataset.page = String(number);
      button.setAttribute('aria-label', t.pageLabel(number));
      if (number === page) button.setAttribute('aria-current', 'page');
      $('#repo-pagination').append(button);
    }
  }
}
async function loadRepositories(force = false) {
  if (loading) return;
  if (!force && cached?.fresh) {
    repositories = cached.repos;
    repositoryState = 'cached';
    renderFilters(); renderRepositories();
    return;
  }
  loading = true;
  repositoryState = 'loading';
  renderStatus();
  try {
    const items = await fetchPublicRepositories();
    repositories = normalizeRepositories(items);
    repositoryState = 'live';
    preferences.set(CACHE_KEY, JSON.stringify({ savedAt: Date.now(), items }));
  } catch (error) {
    repositoryState = error.message === 'rate-limit' ? 'rate' : 'error';
  } finally {
    loading = false;
    renderFilters(); renderRepositories();
  }
}

// Interactions keep data and language separate: toggling language never refetches.
$('.lang-toggle').addEventListener('click', () => {
  applyLanguage(language === 'ar' ? 'en' : 'ar');
  preferences.set('lang', language);
});
$('.theme-toggle').addEventListener('click', () => {
  root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
  preferences.set('theme', root.dataset.theme);
  updateTheme();
});
$('.menu-toggle').addEventListener('click', () => setMenu($('.menu-toggle').getAttribute('aria-expanded') !== 'true'));
$$('#nav-menu a').forEach(link => link.addEventListener('click', () => setMenu(false)));
document.addEventListener('keydown', event => {
  if (event.key === 'Escape' && $('.menu-toggle').getAttribute('aria-expanded') === 'true') setMenu(false, true);
});
document.addEventListener('click', event => {
  if ($('.menu-toggle').getAttribute('aria-expanded') === 'true' && !$('.site-header').contains(event.target)) setMenu(false);
});
const desktop = window.matchMedia('(min-width: 761px)');
const closeDesktopMenu = event => { if (event.matches) setMenu(false); };
if (desktop.addEventListener) desktop.addEventListener('change', closeDesktopMenu);
else desktop.addListener(closeDesktopMenu);
$('#repo-filters').addEventListener('click', event => {
  const button = event.target.closest('button[data-category]');
  if (!button) return;
  category = button.dataset.category; page = 1;
  renderFilters(category); renderRepositories();
});
$('#repo-pagination').addEventListener('click', event => {
  const button = event.target.closest('button[data-page]');
  if (!button) return;
  page = Number(button.dataset.page);
  renderRepositories();
  [...$('#repo-pagination').children].find(item => item.dataset.page === String(page))?.focus({ preventScroll: true });
  $('#repo-filters').scrollIntoView({ behavior: 'auto', block: 'start' });
});
$('#repo-search').addEventListener('input', event => {
  query = event.target.value; page = 1; renderRepositories();
});
$('#retry-repos').addEventListener('click', () => loadRepositories(true));
$$('.current-year').forEach(node => { node.textContent = new Date().getFullYear(); });

if ('IntersectionObserver' in window) {
  const links = $$('[data-nav]');
  const observer = new IntersectionObserver(entries => {
    const visible = entries.filter(entry => entry.isIntersecting).sort((a, b) => b.intersectionRatio - a.intersectionRatio)[0];
    if (!visible) return;
    links.forEach(link => {
      const active = link.getAttribute('href') === `#${visible.target.id}`;
      link.classList.toggle('active', active);
      if (active) link.setAttribute('aria-current', 'location'); else link.removeAttribute('aria-current');
    });
  }, { rootMargin: '-15% 0px -55% 0px', threshold: 0 });
  $$('main section[id]').forEach(section => observer.observe(section));
}

// Show a local public-repository snapshot immediately, then refresh from GitHub.
applyLanguage(language);
if (cached) {
  repositories = cached.repos;
  renderFilters(); renderRepositories();
} else {
  try {
    const response = await fetch(new URL('../data/repositories.json', import.meta.url));
    if (response.ok) repositories = normalizeRepositories((await response.json()).items);
    renderFilters(); renderRepositories();
  } catch (_) { /* Live fetch below still works when the bundled snapshot is unavailable. */ }
}
await loadRepositories();
