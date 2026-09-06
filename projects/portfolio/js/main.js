import { CACHE_KEY, normalizeRepositories, repositoryPresentation, filterRepositories, readRepositoryCache, fetchPublicRepositories } from './repositories.mjs';
import { setupMotion } from './motion.mjs?v=interaction-1';

const $ = selector => document.querySelector(selector);
const $$ = selector => [...document.querySelectorAll(selector)];
const root = document.documentElement;
const preferences = {
  get(key) { try { return localStorage.getItem(key); } catch (_) { return null; } },
  set(key, value) { try { localStorage.setItem(key, value); } catch (_) {} },
};

const COPY = {
  ar: {
    title: 'عبدالرحمن — هندسة الحاسب',
    description: 'الموقع الشخصي لعبدالرحمن، مهندس حاسب من جامعة الطائف. أعمال في البرمجة والذكاء الاصطناعي والروبوتات.',
    name: 'عبدالرحمن', discipline: 'هندسة الحاسب', skip: 'تجاوز إلى المحتوى',
    brandLabel: 'عبدالرحمن — الرئيسية', navLabel: 'التنقل الرئيسي',
    navProjects: 'الأعمال', navAbout: 'نبذة', navExpertise: 'المهارات', navJourney: 'التدريب', navContact: 'التواصل',
    available: 'متاح للفرص الوظيفية',
    heroDescription: 'درست هندسة الحاسب في جامعة الطائف. أعرض هنا أعمالي في البرمجة والذكاء الاصطناعي والروبوتات.',
    explore: 'تصفّح الأعمال', location: 'الرياض، المملكة العربية السعودية',
    projectsLabel: 'الأعمال', projectsTitle: 'من أعمالي.',
    projectsDescription: 'أعرض هنا مشاريعي البرمجية والهندسية، مع نبذة عن كل مشروع ورابط لملفاته على GitHub.',
    allOnGithub: 'جميع المستودعات على GitHub', filtersLabel: 'تصفية المستودعات', previewLabel: 'من مستودعاتي',
    searchPlaceholder: 'البحث في الأعمال', searchLabel: 'البحث في الأعمال', paginationLabel: 'صفحات المستودعات',
    aboutLabel: 'نبذة', aboutA: 'عنّي.',
    aboutLead: 'مهندس حاسب وخريج جامعة الطائف. أهتم بتطوير البرمجيات وتطبيقات الذكاء الاصطناعي والأنظمة المضمّنة.',
    aboutBody: 'شملت أعمالي تطبيقات للتعرّف على إيماءات اليد، ومساعدات صوتية، ومشاريع لربط الأجهزة والتحكّم بها. أنجزت عددًا منها خلال الدراسة والتدريب التعاوني.',
    educationLabel: 'المؤهل', education: 'بكالوريوس هندسة الحاسب', university: 'جامعة الطائف',
    accreditationLabel: 'العضوية المهنية', accreditation: 'الهيئة السعودية للمهندسين',
    expertiseLabel: 'المهارات', expertiseTitle: 'أدوات العمل.', expertiseNote: 'تقنيات استخدمتها في مشاريعي، وأواصل تطوير معرفتي بها.',
    journeyLabel: 'التدريب التعاوني', journeyTitle: 'شركة الأساليب الذكية.',
    journeyDescription: 'كان مساري الرئيسي في الذكاء الاصطناعي والروبوتات وROS، مع تدريب في تطوير الويب والإلكترونيات والتصميم الميكانيكي.',
    contactLabel: 'التواصل', contactA: 'يسعدني تواصلكم.',
    contactDescription: 'للفرص الوظيفية أو المشاريع المشتركة، يمكنكم التواصل معي عبر البريد الإلكتروني.',
    emailLabel: 'التواصل مع عبدالرحمن عبر البريد الإلكتروني', emailText: 'البريد الإلكتروني', backTop: 'إلى الأعلى',
    openMenu: 'فتح القائمة', closeMenu: 'إغلاق القائمة', lightTheme: 'تفعيل المظهر الفاتح', darkTheme: 'تفعيل المظهر الداكن',
    pauseMotion: 'إيقاف الحركة', playMotion: 'تفعيل الحركة', systemMotion: 'الحركة متوقفة وفق إعدادات الجهاز', cursorLabel: 'فتح',
    retry: 'إعادة المحاولة', reset: 'مسح البحث والتصفية', loading: 'جارٍ تحديث المستودعات…', cached: 'آخر نسخة محفوظة',
    error: 'تعذّر التحديث؛ تظهر المستودعات المحفوظة.', failed: 'تعذّر تحميل المستودعات. يمكنكم استعراضها على GitHub.',
    rate: 'الاتصال بـGitHub غير متاح مؤقتًا؛ تظهر النسخة المحفوظة.',
    emptyTitle: 'لا توجد مستودعات عامة حاليًا.', noResults: 'لا توجد نتائج لهذا البحث.', noResultsHint: 'يمكنكم تعديل كلمة البحث أو اختيار مجال آخر.',
    repositoryCount: count => `${count.toLocaleString('ar-SA')} مستودع`,
    pageLabel: page => `الصفحة ${page}`, pageStatus: (count, page, pages) => `${count} مستودع، الصفحة ${page} من ${pages}`,
    openRepository: name => `استعراض ${name} على GitHub`, live: 'الموقع', updated: 'آخر تعديل', stars: 'نجوم', forks: 'تفرّعات', archived: 'مؤرشف', fork: 'نسخة',
    categories: { all: 'الجميع', ai: 'الذكاء الاصطناعي', web: 'الويب', systems: 'الأنظمة', iot: 'الإلكترونيات', mechanical: 'الميكانيكا', other: 'أخرى' },
    expertise: [
      ['الذكاء الاصطناعي والرؤية الحاسوبية', 'التعرّف على إيماءات اليد والتعامل مع الصور والصوت.'],
      ['تطوير الويب', 'بناء الواجهات وربطها بالخدمات وواجهات البرمجة.'],
      ['الروبوتات والأنظمة المضمّنة', 'برمجة الأجهزة والتواصل بينها والعمل مع ROS.'],
      ['الإلكترونيات وإنترنت الأشياء', 'توصيل المستشعرات وبرمجة المتحكّمات ودوائر التحكّم.'],
      ['التصميم الميكانيكي', 'تصميم أجزاء الروبوتات ونماذجها ثلاثية الأبعاد.'],
    ],
    tracks: [
      ['الذكاء الاصطناعي والروبوتات', 'المسار الرئيسي، وشمل الرؤية الحاسوبية والتعامل مع ROS.'],
      ['تطوير الويب ومعالجة اللغة', 'تطوير واجهات وتطبيقات ومساعدات صوتية.'],
      ['الهندسة الكهربائية وإنترنت الأشياء', 'دوائر ومستشعرات وبرمجة متحكّمات.'],
      ['الهندسة الميكانيكية', 'نمذجة أجزاء الروبوتات وتصميمها.'],
    ],
  },
  en: {
    title: 'Abdulrahman — Computer Engineering',
    description: 'Abdulrahman’s portfolio. Computer Engineering, Taif University. Work in programming, artificial intelligence, and robotics.',
    name: 'Abdulrahman', discipline: 'Computer Engineering', skip: 'Skip to content',
    brandLabel: 'Abdulrahman — Home', navLabel: 'Main navigation',
    navProjects: 'Work', navAbout: 'About', navExpertise: 'Skills', navJourney: 'Training', navContact: 'Contact',
    available: 'Open to job opportunities',
    heroDescription: 'I studied Computer Engineering at Taif University. This is a collection of my work in programming, AI, and robotics.',
    explore: 'Explore work', location: 'Riyadh, Saudi Arabia',
    projectsLabel: 'Work', projectsTitle: 'Selected work.',
    projectsDescription: 'A brief introduction to each repository. The code and project documentation are available on GitHub.',
    allOnGithub: 'All repositories on GitHub', filtersLabel: 'Filter repositories', previewLabel: 'From my repositories',
    searchPlaceholder: 'Search my work', searchLabel: 'Search my work', paginationLabel: 'Repository pages',
    aboutLabel: 'About', aboutA: 'A little about me.',
    aboutLead: 'I’m a Computer Engineering graduate from Taif University. My interests include software development, AI applications, and embedded systems.',
    aboutBody: 'My work includes hand-gesture recognition, voice assistants, and projects for connecting and controlling devices. Several were completed during my degree and cooperative training.',
    educationLabel: 'Education', education: 'Bachelor’s in Computer Engineering', university: 'Taif University',
    accreditationLabel: 'Membership', accreditation: 'Saudi Council of Engineers',
    expertiseLabel: 'Skills', expertiseTitle: 'Tools I work with.', expertiseNote: 'Technologies I have used in my projects and continue to learn.',
    journeyLabel: 'Cooperative training', journeyTitle: 'Smart Methods.',
    journeyDescription: 'My main track covered AI, robotics, and ROS, alongside training in web development, electronics, and mechanical design.',
    contactLabel: 'Contact', contactA: 'Get in touch.',
    contactDescription: 'For job opportunities or collaborative projects, you’re welcome to contact me by email.',
    emailLabel: 'Contact Abdulrahman by email', emailText: 'Email me', backTop: 'Back to top',
    openMenu: 'Open menu', closeMenu: 'Close menu', lightTheme: 'Switch to light theme', darkTheme: 'Switch to dark theme',
    pauseMotion: 'Pause motion', playMotion: 'Enable motion', systemMotion: 'Motion paused by device settings', cursorLabel: 'Open',
    retry: 'Try again', reset: 'Clear search and filters', loading: 'Updating repositories…', cached: 'Latest saved copy',
    error: 'Refresh unavailable. Showing saved repositories.', failed: 'Repositories could not be loaded. You can view them on GitHub.',
    rate: 'GitHub is temporarily unavailable. Showing the saved copy.',
    emptyTitle: 'No public repositories yet.', noResults: 'No results for this search.', noResultsHint: 'Try a different search or category.',
    repositoryCount: count => `${count} ${count === 1 ? 'repository' : 'repositories'}`,
    pageLabel: page => `Page ${page}`, pageStatus: (count, page, pages) => `${count} repositories. Page ${page} of ${pages}.`,
    openRepository: name => `View ${name} on GitHub`, live: 'Website', updated: 'Updated', stars: 'stars', forks: 'forks', archived: 'Archived', fork: 'Fork',
    categories: { all: 'All', ai: 'AI', web: 'Web', systems: 'Systems', iot: 'Electronics', mechanical: 'Mechanical', other: 'Other' },
    expertise: [
      ['AI & Computer Vision', 'Hand-gesture recognition and working with images and audio.'],
      ['Web Development', 'Building interfaces and connecting them to services and APIs.'],
      ['Robotics & Embedded Systems', 'Device programming, communication, and working with ROS.'],
      ['Electronics & IoT', 'Sensors, microcontrollers, and control circuits.'],
      ['Mechanical Design', 'Designing robot parts and their 3D models.'],
    ],
    tracks: [
      ['AI & Robotics', 'My main track, including computer vision and working with ROS.'],
      ['Web Development & NLP', 'Interfaces, applications, and voice assistants.'],
      ['Electrical Engineering & IoT', 'Circuits, sensors, and microcontroller programming.'],
      ['Mechanical Engineering', 'Modelling and designing robot parts.'],
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
let motion = null;
let activePreview = '';
let previewSequence = 0;
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
  if (className === 'repo-link' || className === 'repo-title-link') link.setAttribute('data-cursor', '');
  link.append(element('span', '', label), externalIcon());
  return link;
}
function updateTheme() {
  const t = COPY[language];
  const isDark = root.dataset.theme !== 'light';
  $('.theme-toggle').setAttribute('aria-label', isDark ? t.lightTheme : t.darkTheme);
  $('.theme-toggle').title = isDark ? t.lightTheme : t.darkTheme;
  $('meta[name="theme-color"]').content = isDark ? '#191517' : '#f5f4f1';
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
  // Keep the first-name identity consistent in visible text and metadata.
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
  $$('#expertise-grid details').forEach((card, i) => {
    card.querySelector('h3').textContent = t.expertise[i][0];
    card.querySelector('p').textContent = t.expertise[i][1];
  });
  $$('#journey-tracks article').forEach((card, i) => {
    card.querySelector('h3').textContent = t.tracks[i][0];
    card.querySelector('p').textContent = t.tracks[i][1];
  });
  $('.menu-toggle').setAttribute('aria-label', $('.menu-toggle').getAttribute('aria-expanded') === 'true' ? t.closeMenu : t.openMenu);
  updateTheme();
  motion?.updateControls();
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
  const card = element('article', 'repo-row');
  card.dataset.repository = repo.name;
  card.addEventListener('pointerenter', () => updatePreview(repo, index));
  card.addEventListener('focusin', () => updatePreview(repo, index));
  const top = element('div', 'repo-top');
  const label = element('span', 'repo-category', t.categories[repo.category]);
  if (repo.archived) label.append(element('span', 'repo-badge', t.archived));
  if (repo.isFork) label.append(element('span', 'repo-badge', t.fork));
  top.append(label, element('span', 'repo-index', String(index + 1).padStart(2, '0')));
  const heading = element('h3', 'repo-name');
  const titleLink = externalLink(repo.url, presentation.title, 'repo-title-link');
  titleLink.dir = 'ltr';
  titleLink.setAttribute('aria-label', t.openRepository(repo.name));
  heading.append(titleLink);
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
function updatePreview(repo, index) {
  if (!repo || activePreview === repo.name) return;
  activePreview = repo.name;
  const sequence = ++previewSequence;
  const presentation = repositoryPresentation(repo, language);
  const panel = $('#work-preview');
  const content = $('.preview-content');
  const apply = () => {
    if (sequence !== previewSequence) return;
    panel.dataset.category = repo.category;
    $('#preview-number').textContent = String(index + 1).padStart(2, '0');
    $('#preview-title').textContent = presentation.title;
    $('#preview-category').textContent = COPY[language].categories[repo.category];
    $('#preview-category').dir = language === 'ar' ? 'rtl' : 'ltr';
    $('#preview-stack').textContent = presentation.tags.slice(0, 3).join(' / ');
    if (motion?.enabled()) content.animate([{ opacity: 0, transform: 'translateY(22px)' }, { opacity: 1, transform: 'translateY(0)' }], { duration: 480, easing: 'cubic-bezier(.2,.7,.1,1)' });
  };
  content.getAnimations?.().forEach(animation => animation.cancel());
  apply();
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
  $('#work-preview').hidden = filtered.length === 0;
  if (filtered.length) {
    list.replaceChildren(...filtered.slice(start, start + PAGE_SIZE).map((repo, i) => repoCard(repo, start + i)));
    activePreview = '';
    updatePreview(filtered[start], start);
    if (motion?.enabled()) motion.animateList(list);
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
  motion?.refreshCursor();
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
motion = setupMotion({ copy: () => COPY[language], storage: preferences });
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
