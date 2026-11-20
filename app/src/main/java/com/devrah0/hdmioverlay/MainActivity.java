package com.devrah0.hdmioverlay;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.net.Inet4Address;
import java.net.NetworkInterface;
import java.util.Collections;

public final class MainActivity extends Activity {
    private static final int BACKGROUND = Color.rgb(12,18,31);
    private static final int WHITE = Color.rgb(244,248,255);
    private static final int MUTED = Color.rgb(181,195,209);
    private static final int ACCENT = Color.rgb(87,225,194);
    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView diagnostic;
    private LinearLayout screen;
    private Button grantButton;
    private final Runnable refresher = new Runnable() {
        @Override public void run() { refresh(); handler.postDelayed(this, 850); }
    };

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(BACKGROUND);
        screen = new LinearLayout(this);
        screen.setPadding(dp(50),dp(32),dp(50),dp(30));
        screen.setOrientation(LinearLayout.VERTICAL);
        screen.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        scroll.addView(screen);
        setContentView(scroll);
        label("HDMI • LIVE CAPTIONS", 13, ACCENT, true);
        gap(10);
        label("ترجمة الألعاب على التلفزيون", 30, WHITE, true);
        label("اختبر ظهور النص فوق مدخل HDMI الأصلي أولاً، ثم فعّل استقبال الترجمة من هاتفك على نفس شبكة Wi-Fi.", 17, MUTED, false);
        gap(22);
        grantButton = button("١ • السماح بالظهور فوق التطبيقات", () -> {
            try { startActivity(new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:"+getPackageName()))); }
            catch (Exception e) { startActivity(new Intent(Settings.ACTION_SETTINGS)); }
        });
        button("٢ • اختبار الترجمة فوق HDMI (٦٠ ثانية)", () -> startServiceAction(CaptionService.ACTION_TEST));
        button("٣ • تشغيل استقبال الترجمة", () -> startServiceAction(CaptionService.ACTION_START));
        button("٤ • تجربة سطور ترجمة متحركة", () -> startServiceAction(CaptionService.ACTION_DEMO));
        button("إيقاف الترجمة", () -> startServiceAction(CaptionService.ACTION_STOP));
        gap(18);
        diagnostic = label("", 17, ACCENT, true);
        gap(12);
        label("طريقة الفحص: اضغط الاختبار، ثم غيّر مصدر التلفزيون إلى HDMI الخاص بالبلايستيشن. إن لم تظهر الكتابة فوق اللعبة، فهذا قيد في طريقة عرض HDMI في التلفزيون، وليس إذن التطبيق.", 16, MUTED, false);
        gap(8);
        label("بعد بدء الاستقبال، افتح عنوان التلفزيون من Safari على الآيفون لإرسال جمل تجريبية. هذا التطبيق مستقبل للترجمة ولا يلتقط صوت اللعبة أو يترجمه تلقائيًا.", 15, MUTED, false);
        grantButton.requestFocus();
    }
    private void startServiceAction(String action) {
        if (!CaptionService.ACTION_STOP.equals(action) && !Settings.canDrawOverlays(this)) {
            Toast.makeText(this,"فعّل إذن الظهور فوق التطبيقات أولاً", Toast.LENGTH_LONG).show();
            grantButton.requestFocus(); return;
        }
        Intent i = new Intent(this, CaptionService.class).setAction(action);
        try {
            if (CaptionService.ACTION_STOP.equals(action)) startService(i);
            else if (Build.VERSION.SDK_INT>=26) startForegroundService(i);
            else startService(i);
        } catch (Exception e) {
            Toast.makeText(this,"تعذر بدء الخدمة: " + e.getClass().getSimpleName(), Toast.LENGTH_LONG).show();
        }
    }
    private void refresh() {
        if (diagnostic==null) return;
        boolean allowed = Settings.canDrawOverlays(this);
        String ip = localAddress();
        String web = ip==null ? "اتصل بشبكة Wi-Fi لعرض عنوان التلفزيون" : "http://"+ip+":"+CaptionService.PORT+"/";
        String status = allowed ? "إذن Overlay: مفعّل ✓" : "إذن Overlay: غير مفعّل";
        diagnostic.setText(status+"\n"+"الخدمة: "+CaptionService.status+"\n"+"العنوان من الآيفون: "+web+"\n"+
             (CaptionService.running ? "رمز الإرسال: "+CaptionService.pairCode : "رمز الإرسال يظهر بعد تشغيل الاستقبال"));
        grantButton.setText(allowed ? "١ • إذن الظهور مفعّل ✓" : "١ • السماح بالظهور فوق التطبيقات");
    }
    @Override protected void onResume() { super.onResume(); handler.removeCallbacks(refresher); refresher.run(); }
    @Override protected void onPause() { handler.removeCallbacks(refresher); super.onPause(); }
    private int dp(int v) { return (int)(getResources().getDisplayMetrics().density*v+0.5f); }
    private void gap(int h) { View v=new View(this);screen.addView(v,new LinearLayout.LayoutParams(1,dp(h))); }
    private TextView label(String s,int size,int color,boolean bold) {
        TextView t=new TextView(this);t.setText(s);t.setTextSize(size);t.setTextColor(color);
        t.setGravity(Gravity.RIGHT);t.setPadding(0,dp(3),0,dp(5));
        if(bold)t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        screen.addView(t,new LinearLayout.LayoutParams(-1,-2));return t;
    }
    private Button button(String title,Runnable action) {
        Button b=new Button(this);b.setText(title);b.setTextSize(17);b.setAllCaps(false);
        b.setTextColor(WHITE);b.setGravity(Gravity.CENTER);
        GradientDrawable bg=new GradientDrawable();bg.setColor(0xff203348);bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1),0xff416575);b.setBackground(bg);
        LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-1,dp(56));lp.bottomMargin=dp(9);
        screen.addView(b,lp);b.setOnClickListener(v->action.run());return b;
    }
    private static String localAddress() {
        try {
            for(NetworkInterface n:Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if(!n.isUp()||n.isLoopback())continue;
                for(java.net.InetAddress a:Collections.list(n.getInetAddresses())) {
                    if(a instanceof Inet4Address && a.isSiteLocalAddress())return a.getHostAddress();
                }
            }
        } catch (Exception ignored) { }
        return null;
    }
}
