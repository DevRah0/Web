// SPDX-License-Identifier: AGPL-3.0-only
package com.gametranslator.tv;

import android.app.Activity;
import android.app.AlertDialog;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.content.Intent;
import android.graphics.Color;
import android.media.tv.TvContract;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;
import android.media.tv.TvView;
import android.os.Bundle;
import android.util.DisplayMetrics;
import android.view.KeyEvent;
import android.view.View;
import android.view.WindowManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;

import java.net.Inet4Address;
import java.net.InetAddress;
import java.net.NetworkInterface;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * HDMI girişini TvView ile tam ekran gösterir; üstünde şeffaf WebView'de LG ve Samsung'la ortak arayüz çalışır.
 */
public class MainActivity extends Activity {
    private TvView tvView;
    private WebView webView;
    private String launchParams = "";
    private boolean legacyMode;
    private boolean overlayLaunched;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        launchParams = paramsOf(getIntent());
        // TCL: keep console HDMI on the manufacturer's native input, not in a secondary TvView.
        // The original TvView remains available when overlay permission cannot be granted.
        if (getIntent().getBooleanExtra("legacy_tvview", false)) {
            initializeLegacyUi();
        } else if (Settings.canDrawOverlays(this)) {
            launchDirectHdmiOverlay();
        } else {
            showOverlayPermission();
        }
    }

    private void showOverlayPermission() {
        if (isFinishing()) return;
        new AlertDialog.Builder(this)
            .setTitle("GameTranslator — TCL HDMI")
            .setMessage("للحفاظ على صورة البلايستيشن الأصلية دون بث أو ضغط، اسمح بإظهار الترجمة فوق التطبيقات. إذا لم يسمح التلفزيون بذلك، يمكنك استعمال وضع HDMI السابق.")
            .setPositiveButton("السماح بالظهور فوق التطبيقات", (dialog, which) -> {
                try {
                    Intent settings = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                        Uri.parse("package:" + getPackageName()));
                    startActivityForResult(settings, 7010);
                } catch (Exception error) {
                    android.util.Log.w("GameTranslator", "No overlay permission settings", error);
                    initializeLegacyUi();
                }
            })
            .setNegativeButton("وضع HDMI السابق", (dialog, which) -> initializeLegacyUi())
            .setNeutralButton("إغلاق", (dialog, which) -> finish())
            .setCancelable(false)
            .show();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == 7010) {
            if (Settings.canDrawOverlays(this)) launchDirectHdmiOverlay();
            else showOverlayPermission();
        }
    }

    private void launchDirectHdmiOverlay() {
        if (overlayLaunched) return;
        overlayLaunched = true;
        Intent service = new Intent(this, HdmiOverlayService.class);
        service.putExtra("params", launchParams);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(service);
            else startService(service);
            finish();
        } catch (Exception error) {
            overlayLaunched = false;
            android.util.Log.e("GameTranslator", "Overlay startup failed, preserving original TV mode", error);
            initializeLegacyUi();
        }
    }

    /** Original unmodified TV input view, retained solely as a compatibility fallback. */
    private void initializeLegacyUi() {
        if (legacyMode) return;
        legacyMode = true;
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        if (getSystemService(TV_INPUT_SERVICE) != null) {
            tvView = new TvView(this);
            tvView.setCallback(new TvView.TvInputCallback() {
                @Override public void onConnectionFailed(String inputId) { status("inputError"); }
                @Override public void onDisconnected(String inputId) { status("inputError"); }
                @Override public void onVideoAvailable(String inputId) { status("playing"); }
                @Override public void onVideoUnavailable(String inputId, int reason) { status("inputError"); }
            });
            root.addView(tvView);
        }

        webView = new WebView(this);
        webView.setBackgroundColor(Color.TRANSPARENT);
        webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
        WebView.setWebContentsDebuggingEnabled(true);
        WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowFileAccessFromFileURLs(true);
        settings.setAllowUniversalAccessFromFileURLs(true);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);
        // Türkçe dublaj: bilgisayardan gelen ses kumandaya basılmadan çalabilsin.
        settings.setMediaPlaybackRequiresUserGesture(false);
        // Sayfanın 1920 piksellik viewport'u kullanılır ve ekrana sığdırılır (bkz. index.html); yoksa yazılar iki kat büyük.
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        settings.setSupportZoom(false);
        // Ölçek fiziksel piksel başına yüzde: 1920 CSS pikseli ekranın tam genişliğine sığar (1080p'de %100).
        webView.setInitialScale(fitScalePercent());
        webView.addJavascriptInterface(new Bridge(), "AndroidTV");
        webView.setWebChromeClient(new android.webkit.WebChromeClient() {
            @Override
            public boolean onConsoleMessage(android.webkit.ConsoleMessage consoleMessage) {
                android.util.Log.d("TVConsole", consoleMessage.message() + " [" + consoleMessage.sourceId() + ":" + consoleMessage.lineNumber() + "]");
                return true;
            }
        });
        webView.setWebViewClient(new android.webkit.WebViewClient() {
            @Override
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                android.util.Log.e("TVConsole", "WebView error " + errorCode + ": " + description + " at " + failingUrl);
            }
        });
        root.addView(webView);
        setContentView(root);
        webView.loadUrl("file:///android_asset/tv/index.html");
        webView.requestFocus();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String params = paramsOf(intent);
        if (!params.isEmpty()) {
            launchParams = params;
        }
        if (!legacyMode && Settings.canDrawOverlays(this)) {
            launchDirectHdmiOverlay();
            return;
        }
        if (legacyMode && !params.isEmpty()) {
            evaluate("window.__onRelaunch(" + quoted(params) + ")");
        }
    }

    /** Sayfanın 1920 CSS piksellik genişliğini ekranın fiziksel genişliğine sığdıran WebView ölçeği (yüzde). */
    private int fitScalePercent() {
        DisplayMetrics metrics = new DisplayMetrics();
        getWindowManager().getDefaultDisplay().getRealMetrics(metrics);
        int width = Math.max(metrics.widthPixels, metrics.heightPixels);
        return width > 0 ? Math.max(1, Math.round(width * 100f / 1920f)) : 0;
    }

    private static String paramsOf(Intent intent) {
        if (intent == null) return "";
        String params = intent.getStringExtra("params");
        if (params != null && !params.isEmpty()) return params;
        String server = intent.getStringExtra("server");
        if (server != null && !server.isEmpty()) {
            return "{\"server\":\"" + server + "\"}";
        }
        return "";
    }

    /** Geri ve renk tuşlarını sayfaya bildirir; diğerleri WebView'e kendiliğinden gider. */
    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        int code = pageKey(event.getKeyCode());
        if (code == 0) return super.dispatchKeyEvent(event);
        if (event.getAction() == KeyEvent.ACTION_DOWN) evaluate("window.__onKey(" + code + ")");
        return true;
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

    @Override
    protected void onDestroy() {
        if (tvView != null) tvView.reset();
        if (webView != null) webView.destroy();
        super.onDestroy();
    }

    private void status(String kind) {
        evaluate("window.__onHdmiStatus(" + quoted(kind) + ")");
    }

    private void evaluate(String script) {
        if (webView != null) runOnUiThread(() -> webView.evaluateJavascript(script, null));
    }

    private static String quoted(String text) {
        return "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"") + "\"";
    }

    /** TV'nin HDMI girişleri, kimliğe göre sıralı. Girişin numarası sıradaki yeridir. */
    private List<TvInputInfo> hdmiInputs() {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
        if (manager == null) return inputs;
        for (TvInputInfo input : manager.getTvInputList()) {
            if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput()) inputs.add(input);
        }
        Collections.sort(inputs, Comparator.comparing(TvInputInfo::getId));
        return inputs;
    }

    private class Bridge {
        @JavascriptInterface
        public String launchParams() { return launchParams; }

        @JavascriptInterface
        public void showHdmi(int port) {
            runOnUiThread(() -> {
                List<TvInputInfo> inputs = hdmiInputs();
                if (tvView == null || port < 1 || port > inputs.size()) {
                    status("sourceError");
                    return;
                }
                String id = inputs.get(port - 1).getId();
                tvView.tune(id, TvContract.buildChannelUriForPassthroughInput(id));
            });
        }

        /** Tek bağlı HDMI girişi varsa onun numarası, yoksa 0. */
        @JavascriptInterface
        public int consolePort() {
            TvInputManager manager = (TvInputManager) getSystemService(TV_INPUT_SERVICE);
            if (manager == null) return 0;
            List<TvInputInfo> inputs = hdmiInputs();
            int found = 0;
            for (int i = 0; i < inputs.size(); i++) {
                if (manager.getInputState(inputs.get(i).getId()) != TvInputManager.INPUT_STATE_CONNECTED) continue;
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
                        if (address instanceof Inet4Address && address.isSiteLocalAddress()) return address.getHostAddress();
                    }
                }
            } catch (Exception ignored) {
                return "";
            }
            return "";
        }

        @JavascriptInterface
        public void exit() { runOnUiThread(MainActivity.this::finish); }
    }
}
