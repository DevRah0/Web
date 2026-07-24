# Student Status System | نظام إدارة حالة الطلاب

A simple web application built with **PHP** and **MySQL** لتخزين وإدارة بيانات الطلاب، حيث يمكن للمستخدم إضافة اسم الطالب وعمره، وعرض جميع السجلات، وتغيير قيمة **Status** بين **0** و **1** بسهولة.

---

## 📸 Screenshot | صورة المشروع

> Add your project screenshot here | أضف صورة المشروع هنا.

![Student Status System](images/screenshot.png)

---

## ✨ Features | المميزات

- Add a student's name and age | إضافة اسم الطالب وعمره.
- Store data in a MySQL database | حفظ البيانات في قاعدة بيانات MySQL.
- Display all student records in a table | عرض جميع السجلات داخل جدول.
- Toggle the student's status between **0** and **1** | تغيير حالة الطالب بين **0** و **1**.
- Automatically refresh the page after each action | تحديث الصفحة تلقائيًا بعد كل عملية.

---

## 🛠️ Technologies Used | التقنيات المستخدمة

- HTML
- CSS
- PHP
- MySQL

---

## 📂 Project Structure | هيكل المشروع

```text
student-status/
├── images/
│   └── screenshot.png
├── index.php
├── style.css
└── README.md
```

---

## 🚀 Getting Started | طريقة التشغيل

1. Create a MySQL database | أنشئ قاعدة بيانات MySQL.
2. Create a table named `user` | أنشئ جدولًا باسم `user`.
3. Update the database connection in `index.php` | حدّث بيانات الاتصال بقاعدة البيانات داخل `index.php`.
4. Upload the project to a PHP hosting service (e.g., InfinityFree) | ارفع المشروع إلى استضافة تدعم PHP مثل InfinityFree.
5. Open the project in your browser | افتح المشروع من خلال المتصفح.

---

## 📌 Database Structure | بنية قاعدة البيانات

| Column | Description |
|--------|-------------|
| **id** | Primary Key & Auto Increment |
| **name** | Student Name |
| **age** | Student Age |
| **status** | Student Status (0 / 1) |

---

## 👨‍💻 Author | المطور

**Abdulrahman Al-Rubaie**
