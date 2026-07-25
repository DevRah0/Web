# 🎙️ Voice Chatbot

A web-based AI Voice Chatbot built with **HTML, CSS, JavaScript, and PHP**. The application captures the user's voice, converts it into text, sends the request to AI models through **OpenRouter API**, and displays responses in real time.

روبوت محادثة صوتي يعمل عبر الويب باستخدام **HTML وCSS وJavaScript وPHP**، يستقبل صوت المستخدم، يحوله إلى نص، ثم يرسل الطلب إلى نماذج الذكاء الاصطناعي عبر **OpenRouter API** ويعرض الرد مباشرة.

---

# 🌐 Live Demo | التجربة المباشرة

🔗 **Live Website**

> https://abdulrahman0.nfy.fyi/

---

# ✨ Features | المميزات

- 🎤 Voice recognition using the browser Speech Recognition API.
  - التعرف على الصوت باستخدام واجهة Speech Recognition.

- 🤖 AI-powered conversations using OpenRouter API.
  - محادثات ذكية باستخدام OpenRouter API.

- ⚡ Lightweight PHP backend.
  - Backend خفيف وسريع باستخدام PHP.

- 🌍 Responsive web interface.
  - واجهة متجاوبة تعمل على مختلف الأجهزة.

- 🔒 Secure API key configuration.
  - حفظ مفتاح API بشكل آمن داخل ملف الإعدادات.

- 🖥️ Compatible with shared PHP hosting.
  - يعمل على الاستضافات التي تدعم PHP.

---

# 🛠️ Technologies | التقنيات المستخدمة

- HTML5
- CSS3
- JavaScript (ES6)
- PHP
- OpenRouter API

---

# 📂 Project Structure | هيكلة المشروع

```text
voice-chatbot/
│
├── api/
│   └── bot.php
│
├── index.html
├── app.js
├── style.css
├── config.php
├── .htaccess
└── README.md
```

---

# 🚧 Challenge | التحدي

During deployment, the chatbot backend returned **HTTP 403** errors because the original PHP file (`chat.php`) conflicted with the hosting environment. This prevented the application from processing requests correctly and communicating with the AI service.

أثناء نشر المشروع، كان الـ Backend يعيد خطأ **HTTP 403** بسبب تعارض ملف **`chat.php`** مع بيئة الاستضافة، مما منع التطبيق من معالجة الطلبات والتواصل مع خدمة الذكاء الاصطناعي بشكل صحيح.

---

# ✅ Solution | الحل

The backend structure was reorganized by moving the PHP file into the `api` directory and renaming `chat.php` to `bot.php`. The PHP backend was then updated to support the **OpenRouter Chat Completions API**, ensuring reliable communication with AI models and compatibility with standard PHP hosting environments.

تمت إعادة تنظيم هيكلة الـ Backend بنقل ملف **PHP** إلى مجلد **`api`** وإعادة تسمية **`chat.php`** إلى **`bot.php`**، ثم تم تعديل كود **PHP** ليدعم **OpenRouter Chat Completions API**، مما وفر اتصالًا مستقرًا مع نماذج الذكاء الاصطناعي وتوافقًا مع بيئات الاستضافة التي تدعم PHP.

---

# 🚀 Getting Started | التشغيل

### 1. Clone the repository | استنساخ المستودع

```bash
git clone https://github.com/DevRah0/Web.git
```

### 2. Open the project | افتح المشروع

```text
projects/voice-chatbot
```

### 3. Configure your API key | أضف مفتاح OpenRouter

Edit:

```text
config.php
```

Replace:

```php
define('OPENROUTER_API_KEY', 'YOUR_API_KEY');
```

with your own API key.

استبدل القيمة السابقة بمفتاح OpenRouter الخاص بك.

---

# 📄 License | الترخيص

This project is intended for educational purposes and portfolio demonstration.

هذا المشروع مخصص للأغراض التعليمية ولعرض الأعمال (Portfolio).

---

# 👨‍💻 Author | المطور

**Abdulrahman Al-Rubaie**

- **GitHub:** https://github.com/DevRah0
- **Portfolio:** https://devrah0.github.io/Web/