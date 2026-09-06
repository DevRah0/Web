# Abdulrahman — Portfolio | عبدالرحمن

[الموقع المباشر · Live website](https://devrah0.github.io/Web/)

موقعي الشخصي لعرض أعمالي في البرمجة والذكاء الاصطناعي والروبوتات، ومؤهلي في هندسة الحاسب وتدريبي التعاوني. المحتوى متاح بالعربية والإنجليزية.

My personal portfolio: programming, AI, and robotics projects, education, and cooperative training. Available in Arabic and English.

## Design and interaction

An ivory and burgundy editorial layout with an A monogram, original glass artwork, and a repository list paired with a changing preview. Native scrolling drives restrained parallax and a reading indicator. Entry animations, pointer interactions, an animated technology strip, and an expandable skills list give the page movement.

The motion control saves the visitor’s preference. Device reduced-motion settings always take priority. Content and links remain available when motion is disabled. Both themes, mobile navigation, keyboard focus, and RTL/LTR layouts are supported.

## Repository data

`js/repositories.mjs` retrieves public repositories belonging to `DevRah0`, follows API pagination, validates links, and excludes private repositories and `.github`. The gallery has search, category filters, and pagination. Results are cached for 15 minutes; language changes reuse the same data.

`data/repositories.json` provides a public fallback snapshot dated 2026-09-05. Known repositories have concise descriptions in both languages. New repositories use their GitHub descriptions. The interface identifies saved results when GitHub cannot be reached.

## Development and publishing

The site uses HTML, CSS, and JavaScript modules without a build step or package dependencies. Serve this directory over HTTP, for example with `python -m http.server 8000`.

The existing `.github/workflows/deploy.yml` publishes `projects/portfolio` to GitHub Pages when `main` changes. The other projects in this repository are independent.

- `index.html`: semantic content, a monogram identity, and accessible first-name labels.
- `css/styles.css`: responsive layouts, themes, and CSS animation.
- `js/main.js`: translation, repository views, navigation, and preferences.
- `js/motion.mjs`: optional scroll, reveal, pointer, and accordion motion.
- `404.html`: bilingual error page with the same identity.

## Assets

IBM Plex Sans Arabic, Space Grotesk, and Cormorant Garamond are hosted locally in `assets/fonts/`, with their open font licenses. The outlined A monogram in `assets/monogram.svg` uses Cormorant Garamond and is shared by the hero, navigation, footer, and error page; the favicon uses the same mark. The hero artwork uses compressed WebP assets in two sizes. It is original AI-generated decorative artwork, not a photograph of a project.
