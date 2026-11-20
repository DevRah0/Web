# HDMI Translator TV — fresh rebuild

## العربية
تطبيق Android TV جديد من الصفر، بمعرّف جديد تمامًا `com.devrah0.hdmisubtitles.fresh`.
يعرض شريط الترجمة بواسطة نافذة `TYPE_APPLICATION_OVERLAY` مع خدمة أمامية، ويوفر اختبارًا مدته 60 ثانية، وتطبيق ويب محليًا في الهاتف لإرسال نص إلى التلفزيون على نفس الشبكة.

**القيود:** هذا تطبيق **استقبال وعرض ترجمة**، وليس نظام تعرّف على صوت اللعبة أو ترجمة تلقائية. قد لا تظهر نافذة Android فوق HDMI على تلفزيونات تستخدم مسار عرض الأجهزة (TIF/Hardware video plane). الاختبار على الجهاز الفعلي ضروري.

1. ثبّت الـAPK الجديد؛ لا يحتاج إزالة التطبيقات السابقة.
2. افتح التطبيق على Android TV وفعّل إذن الظهور فوق التطبيقات.
3. اختر اختبار HDMI، ثم انتقل إلى مدخل البلايستيشن خلال 60 ثانية.
4. إذا ظهر النص، ارجع للتطبيق واختر تشغيل استقبال الترجمة.
5. افتح عنوان التلفزيون الظاهر على التطبيق في Safari، واكتب رمز الاقتران، ثم أرسل نصًا.

## English
New native Android TV receiver built from scratch with a unique package ID, an overlay permission flow, a 60-second real-input visibility test, and a local HTTP caption receiver.

The TV web endpoint is `http://TV-IP:9786/`; `POST /caption?code=PAIR_CODE` with a UTF-8 plain text body sends a caption. An on-screen 6-digit pairing code is required; keep both devices on the same local network.

**Important:** HDMI overlay depends on firmware. The app does not capture/decode HDMI or transcribe/translate game audio. The TV's actual HDMI compositor may suppress application overlay layers despite the overlay permission being granted.

## Build
JDK 17, Gradle 8.9, Android SDK 35, Android Gradle Plugin 8.6.1. Run `gradle :app:assembleDebug`; find `app/build/outputs/apk/debug/app-debug.apk`. APK is debug-signed for personal sideloading, not Play Store distribution.
