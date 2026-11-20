package com.devrah0.hdmioverlay;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.provider.Settings;
import android.view.Gravity;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.TextView;
import java.io.BufferedInputStream;
import java.io.OutputStream;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Locale;

public final class CaptionService extends Service {
    public static final String ACTION_START="com.devrah0.hdmi.START";
    public static final String ACTION_TEST="com.devrah0.hdmi.TEST";
    public static final String ACTION_DEMO="com.devrah0.hdmi.DEMO";
    public static final String ACTION_STOP="com.devrah0.hdmi.STOP";
    public static final int PORT=9786;
    public static volatile boolean running=false;
    public static volatile String status="متوقفة";
    public static volatile String pairCode="------";
    private final Handler main=new Handler(Looper.getMainLooper());
    private WindowManager wm;
    private View overlay;
    private TextView caption;
    private ServerSocket listener;
    private Thread thread;
    private final SecureRandom random=new SecureRandom();
    private volatile boolean accepting=false;
    private int session=0;

    @Override public IBinder onBind(Intent intent) { return null; }
    @Override public int onStartCommand(Intent intent,int flags,int startId) {
        String action=intent==null?ACTION_STOP:intent.getAction();
        if(ACTION_STOP.equals(action)) { status="متوقفة";stopSelf();return START_NOT_STICKY; }
        if(!Settings.canDrawOverlays(this)) { status="إذن Overlay غير مفعّل";stopSelf();return START_NOT_STICKY; }
        try {
            ensureForeground();
            removeTimersAndServer();
            attachOverlay();
            running=true;
            if(ACTION_TEST.equals(action)) {
                status="اختبار فوق HDMI لمدة 60 ثانية";
                showText("✅ هذا اختبار ظهور الترجمة فوق HDMI");
                final int current=++session;
                main.postDelayed(()->{if(session==current)stopSelf();},60000);
            } else if(ACTION_DEMO.equals(action)) {
                status="عرض ترجمة تجريبية";
                runDemo();
            } else {
                pairCode=String.valueOf(100000+random.nextInt(900000));
                status="بانتظار النص من الهاتف";
                showText("جاهز لاستقبال الترجمة من الآيفون");
                beginServer();
            }
        } catch(Exception e) {
            status="فشل تشغيل Overlay: "+e.getClass().getSimpleName();
            stopSelf();
        }
        return START_NOT_STICKY;
    }
    private void ensureForeground() {
        NotificationManager nm=(NotificationManager)getSystemService(NOTIFICATION_SERVICE);
        final String channel="hdmi_caption_session";
        if(Build.VERSION.SDK_INT>=26) {
            nm.createNotificationChannel(new NotificationChannel(channel,"ترجمة HDMI",NotificationManager.IMPORTANCE_LOW));
        }
        Notification.Builder b=Build.VERSION.SDK_INT>=26?new Notification.Builder(this,channel):new Notification.Builder(this);
        b.setContentTitle("ترجمة HDMI تعمل")
          .setContentText("تظهر الترجمة حتى تقوم بإيقاف الخدمة")
          .setSmallIcon(android.R.drawable.ic_dialog_info)
          .setOngoing(true);
        startForeground(9786,b.build());
    }
    private void attachOverlay() {
        if(overlay!=null)return;
        wm=(WindowManager)getSystemService(WINDOW_SERVICE);
        FrameLayout base=new FrameLayout(this);
        base.setPadding(dp(45),dp(8),dp(45),dp(55));
        TextView tv=new TextView(this);
        tv.setTextSize(28);tv.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        tv.setTextColor(Color.WHITE);tv.setGravity(Gravity.CENTER);
        tv.setPadding(dp(24),dp(13),dp(24),dp(13));
        tv.setMaxLines(3);
        tv.setShadowLayer(5,2,2,0xff111111);
        GradientDrawable bg=new GradientDrawable();bg.setColor(0xe5121925);bg.setCornerRadius(dp(16));
        bg.setStroke(dp(1),0x8857e1c2);tv.setBackground(bg);
        FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER_HORIZONTAL|Gravity.BOTTOM);
        base.addView(tv,cp);
        WindowManager.LayoutParams lp=new WindowManager.LayoutParams(
            -1,-2,WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                |WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
                |WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT);
        lp.gravity=Gravity.BOTTOM|Gravity.CENTER_HORIZONTAL;
        lp.setTitle("HDMI Translator Captions");
        wm.addView(base,lp);
        overlay=base;caption=tv;
    }
    private int dp(int n){return (int)(getResources().getDisplayMetrics().density*n+0.5f);}
    private void showText(String text) {
        if(caption==null)return;
        String value=text==null?"":text.trim();
        if(value.length()>200)value=value.substring(0,200);
        caption.setText(value);
        caption.setVisibility(value.isEmpty()?View.GONE:View.VISIBLE);
    }
    private void runDemo() {
        final String[] lines={"مرحبًا، هذه ترجمة تجريبية.","انتبه! هناك حركة أمامك.","اتجه نحو الهدف المحدد.","يمكن تعديل النص المرسل من الآيفون."};
        int current=++session;
        for(int i=0;i<lines.length;i++) {
            final String line=lines[i];
            main.postDelayed(()->{if(session==current)showText(line);},i*3500L);
        }
        main.postDelayed(()->{if(session==current)stopSelf();},lines.length*3500L+3500);
    }
    private void beginServer() throws Exception {
        listener=new ServerSocket(PORT);
        listener.setReuseAddress(true);
        accepting=true;
        final ServerSocket srv=listener;
        thread=new Thread(()->{
            while(accepting&&!srv.isClosed()) {
                try(Socket socket=srv.accept()) {
                    socket.setSoTimeout(4000);
                    handleClient(socket);
                } catch(Exception ignored) {
                    if(!accepting)break;
                }
            }
        },"caption-http");
        thread.setDaemon(true);
        thread.start();
    }
    private void handleClient(Socket client) throws Exception {
        BufferedInputStream in=new BufferedInputStream(client.getInputStream());
        byte[] headers=new byte[8192];int got=0;
        while(got<headers.length) {
            int c=in.read();if(c==-1)return;
            headers[got++]=(byte)c;
            if(got>=4&&headers[got-4]=='\r'&&headers[got-3]=='\n'&&headers[got-2]=='\r'&&headers[got-1]=='\n')break;
        }
        if(got==headers.length) {reply(client,431,"text/plain; charset=utf-8","Headers too long");return;}
        String block=new String(headers,0,got,StandardCharsets.ISO_8859_1);
        String[] rows=block.split("\r\n");
        if(rows.length==0)return;
        String[] first=rows[0].split(" ");
        if(first.length<2)return;
        String verb=first[0];String path=first[1];
        if("GET".equals(verb)&&(path.equals("/")||path.startsWith("/?"))) {
            reply(client,200,"text/html; charset=utf-8",webPage());return;
        }
        if(!"POST".equals(verb)||!path.startsWith("/caption")) {
            reply(client,404,"text/plain; charset=utf-8","Not found");return;
        }
        String receivedCode="";int length=-1;
        for(String row:rows) {
            String lower=row.toLowerCase(Locale.ROOT);
            if(lower.startsWith("content-length:")) {
                try{length=Integer.parseInt(row.substring(row.indexOf(':')+1).trim());}
                catch(NumberFormatException ignored) { }
            }
            if(lower.startsWith("x-pair-code:"))receivedCode=row.substring(row.indexOf(':')+1).trim();
        }
        if(path.indexOf("code=")>=0) {
            String q=path.substring(path.indexOf("code=")+5);
            int end=q.indexOf('&');if(end>=0)q=q.substring(0,end);
            receivedCode=URLDecoder.decode(q,"UTF-8");
        }
        if(!pairCode.equals(receivedCode)) {
            reply(client,403,"text/plain; charset=utf-8","Wrong pairing code");return;
        }
        if(length<=0||length>4096) {
            reply(client,413,"text/plain; charset=utf-8","Body must be 1 to 4096 bytes");return;
        }
        byte[] bytes=new byte[length];int off=0;
        while(off<length) {
            int n=in.read(bytes,off,length-off);if(n<0)break;off+=n;
        }
        if(off!=length) {reply(client,400,"text/plain; charset=utf-8","Incomplete body");return;}
        String received=new String(bytes,StandardCharsets.UTF_8);
        main.post(()->showText(received));
        reply(client,200,"text/plain; charset=utf-8","OK");
    }
    private static void reply(Socket socket,int code,String type,String body) throws Exception {
        byte[] bytes=body.getBytes(StandardCharsets.UTF_8);
        String status=code==200?"OK":code==403?"Forbidden":code==404?"Not Found":"Bad Request";
        byte[] h=("HTTP/1.1 "+code+" "+status+"\r\nContent-Type: "+type+"\r\nContent-Length: "+bytes.length+
            "\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n").getBytes(StandardCharsets.US_ASCII);
        OutputStream out=socket.getOutputStream();out.write(h);out.write(bytes);out.flush();
    }
    private static String webPage() {
        return "<!doctype html><html lang='ar' dir='rtl'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'>"+
            "<title>ترجمة HDMI</title><style>body{font:18px system-ui;background:#0d1423;color:#f3f8ff;max-width:520px;margin:60px auto;padding:25px}h1{color:#57e1c2}"+
            "input,textarea,button{box-sizing:border-box;width:100%;padding:16px;margin:9px 0;border-radius:12px;border:1px solid #426574;background:#203449;color:white;font:inherit}"+
            "button{background:#126f65;border:0;font-weight:bold}</style><h1>ترجمة HDMI</h1><p>اكتب رمز الإرسال الظاهر على التلفزيون، ثم أرسل نصًا تجريبيًا.</p>"+
            "<input id='code' placeholder='رمز الإرسال المكون من ٦ أرقام' inputmode='numeric' maxlength='6'>"+
            "<textarea id='text' rows='4' placeholder='اكتب الترجمة هنا'></textarea><button onclick='send()'>إظهار النص على الشاشة</button><p id='result'></p>"+
            "<script>async function send(){const code=document.getElementById('code').value.trim(),value=document.getElementById('text').value;"+
            "try{const r=await fetch('/caption?code='+encodeURIComponent(code),{method:'POST',headers:{'Content-Type':'text/plain; charset=UTF-8'},body:value});"+
            "document.getElementById('result').textContent=r.ok?'تم الإرسال ✓':'فشل الإرسال: تحقق من الرمز ('+r.status+')'}"+
            "catch(e){document.getElementById('result').textContent='تعذر الاتصال بالتلفزيون'}}</script></html>";
    }
    private void removeTimersAndServer() {
        session++;
        main.removeCallbacksAndMessages(null);
        accepting=false;
        if(listener!=null){try{listener.close();}catch(Exception ignored){}listener=null;}
        if(thread!=null) {thread.interrupt();thread=null;}
    }
    @Override public void onDestroy() {
        removeTimersAndServer();
        if(wm!=null&&overlay!=null) {
            try{wm.removeViewImmediate(overlay);}catch(Exception ignored) { }
        }
        overlay=null;caption=null;
        pairCode="------";running=false;
        if(!status.startsWith("فشل"))status="متوقفة";
        super.onDestroy();
    }
}
