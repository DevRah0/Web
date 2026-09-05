# Abdulrahman Al-Rubaie — Portfolio | عبدالرحمن الربيعي

A bilingual Computer Engineering portfolio with a graphite-and-lime visual identity, original engineering artwork, and an automatic public GitHub repository showcase.

موقع شخصي ثنائي اللغة لهندسة الحاسب، بهوية فحمية وأخضر مضيء، وعنصر بصري هندسي أصلي، واستعراض تلقائي لمستودعات GitHub العامة.

**[Live website | الموقع المباشر](https://devrah0.github.io/Web/)**

## Project objective | هدف المشروع

Present my background, practical skills, cooperative training, and engineering work clearly. The project gallery displays repositories and links to their documentation on GitHub; it does not enumerate folders inside them.

عرض خلفيتي ومهاراتي العملية وتدريبي التعاوني وأعمالي الهندسية بوضوح. يعرض قسم الأعمال المستودعات وروابط توثيقها على GitHub، دون تحويل المجلدات داخلها إلى مشاريع منفصلة.

## Experience | تجربة الموقع

- Arabic by default, complete English translation, and native RTL/LTR layouts. اللغة العربية افتراضيًا، مع ترجمة إنجليزية كاملة واتجاه عرض مناسب لكل لغة.
- Responsive layouts, local fonts, light/dark themes, accessible navigation, and reduced-motion support. تصميم متجاوب وخطوط محلية ومظهر فاتح وداكن وتنقل سهل ودعم تقليل الحركة.
- Live repositories, search, category filters, pagination, and remembered language/theme preferences. مستودعات مباشرة وبحث وتصفية وصفحات، مع حفظ تفضيلات اللغة والمظهر.
- A bundled public snapshot keeps projects visible if GitHub is unavailable; the interface identifies the saved copy. نسخة محلية من المستودعات العامة تُبقي الأعمال ظاهرة عند تعذّر الاتصال، مع توضيح عرض النسخة المحفوظة.
- Education, Saudi Council of Engineers membership, and cooperative training with AI & Robotics as the primary track. المؤهل وعضوية الهيئة السعودية للمهندسين والتدريب التعاوني مع توضيح المسار الرئيسي للذكاء الاصطناعي والروبوتات.

## Repository data | بيانات المستودعات

`js/repositories.mjs` fetches public repositories from `DevRah0`, follows GitHub pagination, validates returned fields and links, and excludes private repositories and `.github`. Results are cached locally for 15 minutes. Language changes re-render the same data without another API request. Known repositories have short bilingual descriptions; new repositories use their GitHub descriptions.

يجلب الملف `js/repositories.mjs` المستودعات العامة للحساب `DevRah0`، ويتابع صفحات GitHub ويتحقق من البيانات والروابط، ويستبعد المستودعات الخاصة و`.github`. تُحفظ النتائج محليًا لمدة 15 دقيقة. لا يؤدي تبديل اللغة إلى إعادة طلب البيانات. للمستودعات المعروفة أوصاف مختصرة باللغتين، بينما تستخدم المستودعات الجديدة أوصافها من GitHub.

`data/repositories.json` is a public snapshot captured on 2026-09-05. To refresh the fallback, replace its `items` array with current public GitHub repository objects and update `savedAt`. Normal online updates require no manual edits.

الملف `data/repositories.json` نسخة عامة محفوظة بتاريخ 2026-09-05. لتحديث النسخة البديلة، تُستبدل مصفوفة `items` ببيانات المستودعات العامة الحالية ويُحدّث `savedAt`. التحديث المعتاد عند الاتصال لا يحتاج إلى تعديل يدوي.

## Development & deployment | التطوير والنشر

Plain HTML, CSS, and JavaScript modules; no package installation or build step is required. Serve this directory with any static HTTP server (for example, `python -m http.server 8000`) because browser modules require HTTP. Opening the HTML directly through `file://` is not supported.

الموقع مبني باستخدام HTML وCSS ووحدات JavaScript، ولا يحتاج إلى تثبيت حزم أو خطوة بناء. يُشغّل هذا المجلد عبر خادم HTTP ثابت، مثل `python -m http.server 8000`، لأن وحدات المتصفح تحتاج إلى HTTP، ولا يدعم فتح الصفحة مباشرة عبر `file://`.

The existing workflow at `.github/workflows/deploy.yml` publishes `projects/portfolio` to GitHub Pages after changes to `main`. Other projects in the `Web` repository remain independent.

ينشر مسار العمل الموجود في `.github/workflows/deploy.yml` مجلد `projects/portfolio` على GitHub Pages بعد تحديث `main`. تبقى المشاريع الأخرى في مستودع `Web` مستقلة.

## Assets | الأصول

- IBM Plex Sans Arabic and Space Grotesk are self-hosted under `assets/fonts/`, with their SIL Open Font License files included. الخطوط مستضافة محليًا وملفات تراخيصها مضمنة.
- The compressed WebP hero is original AI-generated decorative artwork, not a photograph of a completed project. صورة الواجهة الفنية بصيغة WebP مولّدة بالذكاء الاصطناعي لأغراض التصميم، وليست صورة لمشروع منفّذ.
- The existing social-preview image is retained. تم الاحتفاظ بصورة معاينة المشاركة السابقة.
