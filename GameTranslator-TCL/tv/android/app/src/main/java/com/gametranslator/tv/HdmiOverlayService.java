// SPDX-License-Identifier: AGPL-3.0-only
// TCL compatibility layer for GameTranslator v1.7.0.
// Keeps the manufacturer's native HDMI input on screen. No HDMI capture, decoding or scaling.
package com.gametranslator.tv;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.util.Log;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.Toast;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

public final class HdmiOverlayService extends Service {
    private static final String TAG = "GT-TCL-HDMI";
    private static final String CHANNEL = "gametranslator_hdmi_overlay";
    private final Handler ui = new Handler(Looper.getMainLooper());
    private WindowManager windowManager;
    private WebView webView;
    private volatile String launchParams = "";
    private boolean pageLoaded;
    private int currentPort = -1;

    @Override
    public void onCreate() {
        super.onCreate();
        startPersistentNotification();
        createTransparentWindow();
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent != null && intent.hasExtra("params")) {
            String params = intent.getStringExtra("params");
            if (params != null && !params.isEmpty()) {
                launchParams = params;
                if (pageLoaded) evaluate("window.__onRelaunch(" + quoted(params) + ")");
            }
        }
        if (!pageLoaded) {
            pageLoaded = true;
            webView.loadUrl("file:///android_asset/tv/index.html");
            webView.requestFocus();
        }
        return START_STICKY;
    }

    private void startPersistentNotification() {
        NotificationManager nm = (NotificationManager) getSystemService(NOTIFICATION_SERVICE);
        if (Build.VERSION.SDK_INT >= 26) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL, "GameTranslator HDMI", NotificationManager.IMPORTANCE_LOW);
            channel.setDescription("Original-quality HDMI subtitle overlay");
            nm.createNotificationChannel(channel);
        }
        Intent back = new Intent(this, MainActivity.class);
        back.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        int flags = PendingIntent.FLAG_UPDATE_CURRENT;
        if (Build.VERSION.SDK_INT >= 23) flags |= PendingIntent.FLAG_IMMUTABLE;
        PendingIntent pending = PendingIntent.getActivity(this, 0, back, flags);
        Notification.Builder builder = Build.VERSION.SDK_INT >= 26
            ? new Notification.Builder(this, CHANNEL)
            : new Notification.Builder(this);
        Notification notification = builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle("GameTranslator")
            .setContentText("HDMI subtitles — direct HDMI picture")
            .setContentIntent(pending)
            .setOngoing(true)
            .build();
        startForeground(1701, notification);
    }

    private void createTransparentWindow() {
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        webView = new WebView(this) {
            @Override
            public boolean dispatchKeyEvent(KeyEvent event) {
                int code = pageKey(event.getKeyCode());
                if (code != 0) {
                    if (event.getAction() == KeyEvent.ACTION_DOWN) {
                        evaluate("window.__onKey(" + code + ")");
                    }
                    return true;
                }
                return super.dispatchKeyEvent(event);
            }
        };
        webView.setBackgroundColor(Color.TRANSPARENT);
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        webView.setInitialScale(fitScalePercent());
        webView.addJavascriptInterface(new Bridge(), "AndroidTV");
        webView.setWebChromeClient(new android.webkit.WebChromeClient() {
            @Override public boolean onConsoleMessage(android.webkit.ConsoleMessage message) {
                Log.d(TAG, message.message() + " [" + message.sourceId() + ":" + message.lineNumber() + "]");
                return true;
            }
        });
        webView.setWebViewClient(new android.webkit.WebViewClient() {
            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                Log.e(TAG, "WebView " + errorCode + ": " + description + " @ " + failingUrl);
            }
        });

        int flags = WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            | WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
            | WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED;
        WindowManager.LayoutParams lp = new WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            flags, PixelFormat.TRANSLUCENT);
        lp.gravity = Gravity.TOP | Gravity.START;
        lp.setTitle("GameTranslator subtitles overlay");
        windowManager.addView(webView, lp);
    }

    private int fitScalePercent() {
        DisplayMetrics metrics = new DisplayMetrics();
        windowManager.getDefaultDisplay().getRealMetrics(metrics);
        int width = Math.max(metrics.widthPixels, metrics.heightPixels);
        return width > 0 ? Math.max(1, Math.round(width * 100f / 1920f)) : 100;
    }

    private void evaluate(String js) {
        ui.post(() -> {
            if (webView != null) webView.evaluateJavascript(js, null);
        });
    }

    private void status(String value) {
        evaluate("window.__onHdmiStatus(" + quoted(value) + ")");
    }

    private static String quoted(String s) {
        return org.json.JSONObject.quote(s);
    }

    private static int pageKey(int keyCode) {
        switch (keyCode) {
            case KeyEvent.KEYCODE_BACK: return 4;
            case KeyEvent.KEYCODE_PROG_RED: return 403;
            case KeyEvent.KEYCODE_PROG_GREEN: return 404;
            case KeyEvent.KEYCODE_PROG_BLUE: return 406;
            default: return 0;
        }
    }

    private List<TvInputInfo> hdmiInputs() {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
        if (manager == null) return inputs;
        try {
            for (TvInputInfo input : manager.getTvInputList()) {
                if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput()) inputs.add(input);
            }
        } catch (Exception error) {
            Log.w(TAG, "Cannot list HDMI sources", error);
        }
        Collections.sort(inputs, Comparator.comparing(TvInputInfo::getId));
        return inputs;
    }

    private void openNativeHdmi(int port) {
        List<TvInputInfo> inputs = hdmiInputs();
        if (port < 1 || port > inputs.size()) {
            status("sourceError");
            Log.w(TAG, "No HDMI input " + port + " exposed by this TV");
            return;
        }
        try {
            String inputId = inputs.get(port - 1).getId();
            Intent openTv = new Intent(Intent.ACTION_VIEW,
                TvContract.buildChannelUriForPassthroughInput(inputId));
            openTv.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            // Intent is delegated to the vendor's native TV input application.
            startActivity(openTv);
            status("ready");
        } catch (Exception e) {
            // Overlay stays alive: the user can switch to HDMI with the TV's input/source key.
            status("sourceError");
            Log.w(TAG, "Native HDMI intent unavailable. Select HDMI on TV remote.", e);
            Toast.makeText(this, "افتح مدخل HDMI من زر Source بالشاشة", Toast.LENGTH_LONG).show();
        }
    }

    private final class Bridge {
        @JavascriptInterface
        public String launchParams() {
            return launchParams;
        }

        @JavascriptInterface
        public void showHdmi(int port) {
            ui.post(() -> {
                if (currentPort == port) return;
                currentPort = port;
                openNativeHdmi(port);
            });
        }

        @JavascriptInterface
        public int consolePort() {
            TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
            if (manager == null) return 0;
            List<TvInputInfo> inputs = hdmiInputs();
            int found = 0;
            for (int i = 0; i < inputs.size(); i++) {
                if (manager.getInputState(inputs.get(i).getId())
                    != TvInputManager.INPUT_STATE_CONNECTED) continue;
                if (found != 0) return 0;
                found = i + 1;
            }
            return found;
        }

        @JavascriptInterface
        public String localAddress() {
            try {
                for (NetworkInterface face : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                    if (!face.isUp() || face.isLoopback()) continue;
                    for (InetAddress address : Collections.list(face.getInetAddresses())) {
                        if (address instanceof Inet4Address && address.isSiteLocalAddress()) {
                            return address.getHostAddress();
                        }
                    }
                }
            } catch (Exception ignored) {}
            return "";
        }

        @JavascriptInterface
        public void exit() {
            ui.post(HdmiOverlayService.this::stopSelf);
        }
    }

    @Override
    public void onDestroy() {
        if (webView != null) {
            try { windowManager.removeViewImmediate(webView); }
            catch (Exception ignored) {}
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
