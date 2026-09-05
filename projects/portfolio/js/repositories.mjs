/** Public repository data. Network data is validated before it reaches the UI. */
export const OWNER = 'DevRah0';
export const CACHE_KEY = 'portfolio-repositories-v2';
export const CACHE_TTL = 15 * 60 * 1000;

export const REPOSITORY_DETAILS = {
  'ai-and-robotics': {
    title: 'AI & Robotics', category: 'ai', tags: ['Python', 'OpenCV', 'MediaPipe'],
    ar: 'تجارب في الرؤية الحاسوبية وتعلّم الآلة، من التعرّف على إيماءات اليد إلى المساعدات الصوتية.',
    en: 'Computer vision and machine learning projects, from hand-gesture recognition to voice assistants.',
  },
  bridgeos: {
    title: 'BridgeOS', category: 'systems', tags: ['Rust', 'SwiftUI', 'BLE / GATT'],
    ar: 'مشروع لربط إدخال لوحة المفاتيح من iOS بجهاز Raspberry Pi عبر Bluetooth Low Energy.',
    en: 'A project connecting keyboard input on iOS to a Raspberry Pi over Bluetooth Low Energy.',
  },
  web: {
    title: 'Web', category: 'web', tags: ['JavaScript', 'HTML / CSS', 'PHP'],
    ar: 'تطبيقات ويب تجمع الواجهات والخدمات: موقعي الشخصي، ومحادثة صوتية، وتطبيق لعرض الحالة الأكاديمية.',
    en: 'Web projects spanning interfaces and services: this portfolio, a voice chatbot, and a student-status application.',
  },
  electronics_and_iot: {
    title: 'Electronics & IoT', category: 'iot', tags: ['Arduino', 'C++', 'Sensors'],
    ar: 'دوائر ومستشعرات وبرمجة متحكّمات لتجارب عملية في التحكّم والأتمتة وإنترنت الأشياء.',
    en: 'Circuits, sensors, and microcontroller programming for hands-on control, automation, and IoT projects.',
  },
  mechanical_eng: {
    title: 'Mechanical Engineering', category: 'mechanical', tags: ['CAD', 'Onshape', 'Robotics'],
    ar: 'تصميمات ميكانيكية ونماذج أولية للروبوتات، منها تصميم روبوت رباعي الأرجل.',
    en: 'Mechanical designs and robot prototypes, including a quadruped robot design.',
  },
};

const text = value => typeof value === 'string' ? value : '';
const count = value => Number.isSafeInteger(value) && value >= 0 ? value : 0;
export function safeExternalURL(value) {
  try {
    const url = new URL(text(value));
    return ['https:', 'http:'].includes(url.protocol) && !url.username && !url.password ? url.href : '';
  } catch (_) { return ''; }
}
export function classifyRepository(name, language = '', topics = []) {
  const known = REPOSITORY_DETAILS[name.toLowerCase()];
  if (known) return known.category;
  const words = [name.replace(/[_-]/g, ' '), ...topics].join(' ').toLowerCase();
  if (/\b(ai|robotics?|vision|machine learning)\b/.test(words)) return 'ai';
  if (/\b(iot|electronic[sa]?|arduino|esp32)\b/.test(words)) return 'iot';
  if (/\b(mechanical|cad|solidworks)\b/.test(words)) return 'mechanical';
  if (/\b(embedded|ble|firmware|systems?)\b/.test(words)) return 'systems';
  if (/\b(web|frontend|backend|website)\b/.test(words) || ['HTML', 'CSS', 'JavaScript', 'TypeScript', 'PHP'].includes(language)) return 'web';
  return 'other';
}
export function normalizeRepositories(items) {
  if (!Array.isArray(items)) return [];
  const seen = new Set();
  return items.flatMap(item => {
    if (!item || typeof item !== 'object' || item.private === true) return [];
    const name = text(item.name);
    if (!/^[\w.-]{1,100}$/.test(name) || ['.', '..', '.github'].includes(name.toLowerCase()) || seen.has(name.toLowerCase())) return [];
    if (item.owner && (typeof item.owner.login !== 'string' || item.owner.login.toLowerCase() !== OWNER.toLowerCase())) return [];
    seen.add(name.toLowerCase());
    const topics = Array.isArray(item.topics) ? item.topics.filter(t => typeof t === 'string').slice(0,20) : [];
    return [{
      name, description: text(item.description), language: text(item.language), topics,
      url: `https://github.com/${OWNER}/${encodeURIComponent(name)}`,
      homepage: safeExternalURL(item.homepage),
      pushed: text(item.pushed_at), updated: text(item.updated_at),
      stars: count(item.stargazers_count), forks: count(item.forks_count),
      archived: item.archived === true, isFork: item.fork === true,
      category: classifyRepository(name, item.language, topics),
    }];
  }).sort((a,b) => (Date.parse(b.pushed || b.updated) || 0) - (Date.parse(a.pushed || a.updated) || 0));
}
export function repositoryPresentation(repo, language) {
  const details = REPOSITORY_DETAILS[repo.name.toLowerCase()];
  return {
    title: details?.title || repo.name,
    description: details?.[language] || repo.description || (language === 'ar' ? 'استكشف ملفات هذا المستودع وتوثيقه على GitHub.' : 'Explore this repository and its documentation on GitHub.'),
    tags: [...new Set([...(details?.tags || []), ...repo.topics, repo.language].filter(Boolean))].slice(0, 4),
  };
}
export function filterRepositories(repos, category = 'all', query = '') {
  const needle = query.trim().toLocaleLowerCase();
  return repos.filter(repo => {
    if (category !== 'all' && repo.category !== category) return false;
    const details = REPOSITORY_DETAILS[repo.name.toLowerCase()];
    const haystack = [repo.name, repo.description, repo.language, ...repo.topics, details?.title, details?.ar, details?.en, ...(details?.tags || [])].join(' ').toLocaleLowerCase();
    return !needle || haystack.includes(needle);
  });
}
export function readRepositoryCache(raw, now = Date.now()) {
  try {
    const cache = JSON.parse(raw);
    if (!Array.isArray(cache?.items) || !Number.isFinite(cache.savedAt) || cache.savedAt > now) return null;
    return { repos: normalizeRepositories(cache.items), fresh: now - cache.savedAt < CACHE_TTL };
  } catch (_) { return null; }
}
export async function fetchPublicRepositories(fetcher = fetch, timeout = 9000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const items = [];
    let page = 1;
    let hasNext = true;
    while (hasNext) {
      const response = await fetcher(`https://api.github.com/users/${OWNER}/repos?type=owner&sort=updated&per_page=100&page=${page}`, {
        headers: { Accept: 'application/vnd.github+json' }, signal: controller.signal,
      });
      if (!response.ok) throw new Error(response.status === 403 || response.status === 429 ? 'rate-limit' : 'network');
      const batch = await response.json();
      if (!Array.isArray(batch)) throw new Error('invalid-response');
      items.push(...batch);
      hasNext = /<[^>]+>;\s*rel="next"/.test(response.headers.get('Link') || '');
      page += 1;
    }
    return items;
  } finally { clearTimeout(timer); }
}
