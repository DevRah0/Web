# Outlook V3 — نظام التقديم الآمن عبر Microsoft Graph

تم تنفيذ هذا الإصدار لمشروع التوظيف **jclycoagtotikxskgkju** فقط.

## الحالة الحالية
- محرك جدولة Supabase: `job-office-outlook-worker-5m` كل خمس دقائق، مستقل عن تبويب المتصفح.
- تتولى `job-outlook-connect` التفويض وتعرض حالة الربط والتخزين. يتولى `job-outlook-worker` الإرسال والتحقق ومتابعة الردود المرتبطة بالتقديمات.
- جداول `job_outlook_queue`, `job_outlook_oauth_states`, `job_outlook_connections`.
- الإرسال معطّل افتراضيًا `job_system_settings.outlook_auto_send_enabled=false`. **لا يتحول إلى true إلا بناء على تفعيل صريح داخل مكتب المدير**.
- لا تُعاد محاولات الإرسال التي قبلتها Microsoft Graph دون التحقق؛ أي حالة غير مؤكدة تُعلّق للفحص.

## إعداد Microsoft Graph لمرة واحدة
1. افتح [Microsoft Entra - App registrations](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade) وسجّل تطبيقًا جديدًا يدعم *personal Microsoft accounts*.
2. ضمن Authentication أضف منصة **Web** وحدّد Redirect URI كما هو حرفيًا:
```
https://jclycoagtotikxskgkju.supabase.co/functions/v1/job-outlook-connect
```
3. في API permissions أضف Microsoft Graph **delegated** scopes: `User.Read`, `Mail.Send`, `Mail.ReadBasic`, `offline_access`. لا تمنح application-wide permissions. إضافة هذه الصلاحيات/الموافقة عليها تخضع لإعدادات Microsoft والحساب.
4. أنشئ Client Secret من صفحة Certificates & secrets. انسخ **Value** إلى **Supabase Dashboard > Edge Functions > Secrets**.
5. أضف متغيري:
   - `OUTLOOK_GRAPH_CLIENT_ID` = Application (client) ID.
   - `OUTLOOK_GRAPH_CLIENT_SECRET` = قيمة Client Secret.
6. افتح [مكتب المدير](https://devrah0.github.io/Web/job-office/manager.html)، وسجّل دخول حساب Supabase ثم اضغط **ربط Outlook**. وافق من Microsoft باستخدام نفس عنوان البريد الموجود في ملف المرشح. إذا اختلف العنوان فالنظام يرفض الربط.
7. تحقق من ظهور «السيرة PDF مرفوعة» في مكتب المدير. تستطيع رفعها أو استبدالها في التخزين الخاص بحد أقصى 3 MB.
8. اضغط **تشغيل الإرسال التلقائي** وأكّد الموافقة. بعدها يجهّز Cron الطلبات المقبولة فقط، كل خمس دقائق، ويرفق PDF ويتحقق من العناصر المرسلة.

## قواعد السلامة
- لا ترسل وظائف غير مدققة أو غير معتمدة `job_reviews.approved_to_apply=true`.
- يجب أن يكون البريد محدّدًا في صفحة التوظيف الرسمية وتوثّق `email_verified_at` و `email_verification_source_url`.
- يُمنع التقديم المكرر لنفس الإعلان أو إذا استخدم عنوان المستلم في سجل التقديم السابق؛ هذه قاعدة تحفظية قابلة للمراجعة اليدوية.
- مستخدم ChatGPT لديه موصل Outlook منفصل؛ **لا تُحوَّل توكنات موصل ChatGPT إلى Supabase**.
- بعد قبول Microsoft طلب الإرسال، يطابق العامل عنوان المستلم والموضوع ووقت الإرسال ووجود مرفق في Sent Items. تسجل المعاملة الواحدة الدليل وحالة التقديم.
- عند الشك في نجاح الإرسال: `pending_verification` أو `manual_review`، بدون إعادة إرسال تلقائية.
- تستطيع إيقاف الإرسال التلقائي من مكتب المدير مع استمرار فحص الردود. فصل حساب Outlook يوقف المتابعة أيضًا.
- تقرأ المتابعة عنوان الرسالة والمرسل والوقت، وتطابقها مع تقديم موثق. يظهر الرد المطابق في المكتب للمراجعة.
- تظهر الوظائف المعتمدة التي تستخدم بوابة الشركة في قائمة منفصلة عن طابور Outlook. افتح رابط الإعلان لإكمالها من البوابة.

## اختبار التشغيل
- `SELECT * FROM cron.job WHERE jobname='job-office-outlook-worker-5m';`
- `SELECT status,count(*) FROM public.job_outlook_queue GROUP BY status;`
- دون `OUTLOOK_GRAPH_CLIENT_ID` و`OUTLOOK_GRAPH_CLIENT_SECRET`، تعيد Edge Function `awaiting_microsoft_app_registration` ولا ترسل بريدًا.
- الطلبات غير المصرّح بها إلى `job-outlook-worker` و`job-outlook-connect` يجب أن تعيد `401`.
- اختبر حساب المستخدم المرتبط من واجهة المكتب بعد الإعداد، ولا تشارك كلمة المرور أو Client Secret.

**ملاحظة:** نجاح الاختبارات بدون بيانات Microsoft يثبت حماية المحرك وجاهزية الهيكل، وليس نجاح أول رسالة عبر Graph. يجب تنفيذ الاختبار النهائي بعد الربط.
