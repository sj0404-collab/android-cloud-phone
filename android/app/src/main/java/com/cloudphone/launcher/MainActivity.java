package com.cloudphone.launcher;

import android.annotation.SuppressLint;
import android.app.DownloadManager;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Bundle;
import android.os.Process;
import android.util.Log;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.MimeTypeMap;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.webkit.ValueCallback;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import androidx.activity.ComponentActivity;
import androidx.activity.OnBackPressedCallback;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContracts;

import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;

/**
 * Cloud Phone shell, the same shape as the NPM Hub APK: no buttons in the
 * native UI. A connect page is served from inside the APK (assets/connect),
 * it knows the server address and sends this WebView to the noVNC page.
 * The only chrome is a progress bar and an error page with
 * retry / change-server. A crash reporter writes any uncaught exception to
 * files/crash.txt and the error page shows it, so failures are diagnosable.
 */
public class MainActivity extends ComponentActivity {

    private static final String CONNECT_HOST = "cp.local";
    private static final String CONNECT_URL = "https://" + CONNECT_HOST + "/index.html";
    private static final String CONNECT_SETUP_URL = CONNECT_URL + "?setup=1";
    private static final String PREFS = "cloud_phone";
    private static final String KEY_SERVER = "server_url";
    private static final String CRASH_FILE = "crash.txt";
    private static final int BG = Color.parseColor("#0d0d12");
    private static final int FG = Color.parseColor("#e8e8f0");
    private static final int MUTED = Color.parseColor("#8a8a9e");

    private WebView web;
    private ProgressBar bar;
    private LinearLayout errorView;
    private TextView crashInfo;

    private ValueCallback<Uri[]> fileChooser;
    private ActivityResultLauncher<Intent> filePicker;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        installCrashReporter();

        filePicker = registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(), res -> {
                    if (fileChooser != null) {
                        Uri[] uris = WebChromeClient.FileChooserParams
                                .parseResult(res.getResultCode(), res.getData());
                        fileChooser.onReceiveValue(uris == null ? new Uri[0] : uris);
                        fileChooser = null;
                    }
                });

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(BG);

        bar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        bar.setMax(100);
        bar.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 6));
        bar.setVisibility(View.GONE);

        web = new WebView(this);
        web.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        web.setBackgroundColor(BG);

        errorView = buildErrorView();

        root.addView(bar);
        root.addView(web);
        root.addView(errorView);
        setContentView(root);

        configureWebView();
        registerBackHandler();

        try {
            if (savedInstanceState == null) {
                String saved = serverUrl();
                web.loadUrl(saved == null || saved.isEmpty() ? CONNECT_URL : saved);
            } else {
                web.restoreState(savedInstanceState);
            }
        } catch (Exception e) {
            showError("Ошибка запуска: " + e);
        }
    }

    private void installCrashReporter() {
        final File logFile = new File(getFilesDir(), CRASH_FILE);
        Thread.setDefaultUncaughtExceptionHandler((t, e) -> {
            try (FileOutputStream fos = new FileOutputStream(logFile)) {
                String s = "Thread: " + t.getName() + "\n" +
                        Log.getStackTraceString(e);
                fos.write(s.getBytes(StandardCharsets.UTF_8));
            } catch (Exception ignored) {
            }
            Process.killProcess(Process.myPid());
            System.exit(2);
        });
    }

    private String crashReport() {
        try (InputStream is = openFileInput(CRASH_FILE)) {
            byte[] b = new byte[is.available()];
            int r = is.read(b);
            return r > 0 ? new String(b, StandardCharsets.UTF_8) : null;
        } catch (Exception e) {
            return null;
        }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private void configureWebView() {
        WebSettings w = web.getSettings();
        w.setJavaScriptEnabled(true);
        w.setDomStorageEnabled(true);
        w.setUseWideViewPort(true);
        w.setLoadWithOverviewMode(true);
        w.setCacheMode(WebSettings.LOAD_DEFAULT);
        w.setMediaPlaybackRequiresUserGesture(false);
        w.setAllowFileAccess(false);
        w.setAllowContentAccess(false);
        w.setJavaScriptCanOpenWindowsAutomatically(true);
        w.setSupportMultipleWindows(false);
        String ua = w.getUserAgentString();
        w.setUserAgentString(ua + " CloudPhone/" + BuildConfig.CP_VERSION);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                bar.setProgress(newProgress);
                bar.setVisibility(newProgress > 0 && newProgress < 100 ? View.VISIBLE : View.GONE);
            }

            @Override
            public boolean onShowFileChooser(
                    WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                fileChooser = callback;
                try {
                    Intent intent = params.createIntent();
                    if (intent == null) {
                        fileChooser.onReceiveValue(new Uri[0]);
                        fileChooser = null;
                        return false;
                    }
                    filePicker.launch(intent);
                    return true;
                } catch (Exception e) {
                    fileChooser = null;
                    return false;
                }
            }
        });

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return serveConnect(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleUrl(request.getUrl());
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) showError(null);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                bar.setVisibility(View.GONE);
                if (CONNECT_HOST.equals(Uri.parse(url).getHost())) {
                    String js = "window.CP_BUILD={versionCode:" + BuildConfig.CP_VERSION_CODE +
                            ",versionName:" + JSONObject.quote(BuildConfig.CP_VERSION) + "};" +
                            "if(window.onCpBuild)window.onCpBuild(window.CP_BUILD);";
                    view.evaluateJavascript(js, null);
                }
            }
        });

        web.setDownloadListener((url, userAgent, contentDisposition, mime, contentLength) -> {
            try {
                DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
                req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
                req.setMimeType(mime);
                ((DownloadManager) getSystemService(Context.DOWNLOAD_SERVICE)).enqueue(req);
                Toast.makeText(this, "Скачивается…", Toast.LENGTH_SHORT).show();
            } catch (Exception e) {
                startActivity(new Intent(Intent.ACTION_VIEW, Uri.parse(url)));
            }
        });
    }

    private WebResourceResponse serveConnect(Uri url) {
        if (!CONNECT_HOST.equals(url.getHost())) return null;
        String path = url.getPath() == null || url.getPath().isEmpty() ? "/index.html" : url.getPath();
        String asset = "connect" + path;
        try (InputStream is = getAssets().open(asset)) {
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(
                    path.substring(path.lastIndexOf('.') + 1));
            if (mime == null) mime = "application/octet-stream";
            return new WebResourceResponse(mime, "UTF-8", is);
        } catch (Exception e) {
            return null;
        }
    }

    private boolean handleUrl(Uri url) {
        String host = url.getHost();
        if (CONNECT_HOST.equals(host)) return false;
        String scheme = url.getScheme();
        if ("http".equals(scheme) || "https".equals(scheme)) {
            saveServerUrl(url.toString());
            return false;
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, url));
        } catch (Exception ignored) {
        }
        return true;
    }

    private LinearLayout buildErrorView() {
        LinearLayout v = new LinearLayout(this);
        v.setOrientation(LinearLayout.VERTICAL);
        v.setVisibility(View.GONE);
        v.setPadding(56, 56, 56, 56);
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        v.addView(makeText("Телефон не открылся", 19f, FG));
        v.addView(makeText("Проверьте адрес сервера и сеть. Если cloud-phone только запустился — " +
                "подождите минуту: noVNC поднимается после загрузки Android.", 14f, MUTED, 0, 16, 0, 24));

        Button retry = new Button(this);
        retry.setText("Повторить");
        retry.setOnClickListener(view -> {
            errorView.setVisibility(View.GONE);
            web.setVisibility(View.VISIBLE);
            String saved = serverUrl();
            web.loadUrl(saved == null || saved.isEmpty() ? CONNECT_URL : saved);
        });
        v.addView(retry);

        Button change = new Button(this);
        change.setText("Сменить сервер");
        change.setBackgroundColor(Color.TRANSPARENT);
        change.setTextColor(FG);
        change.setOnClickListener(view -> {
            errorView.setVisibility(View.GONE);
            web.setVisibility(View.VISIBLE);
            web.loadUrl(CONNECT_SETUP_URL);
        });
        v.addView(change);

        crashInfo = makeText("", 11f, Color.parseColor("#ffb3b3"), 24, 12, 0, 0);
        crashInfo.setVisibility(View.GONE);
        v.addView(crashInfo);

        Button copy = new Button(this);
        copy.setText("Скопировать журнал");
        copy.setVisibility(View.GONE);
        copy.setOnClickListener(view -> {
            String s = crashReport();
            if (s == null) return;
            ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
            cm.setPrimaryClip(ClipData.newPlainText("Cloud Phone crash", s));
            Toast.makeText(this, "Журнал скопирован", Toast.LENGTH_SHORT).show();
        });
        v.addView(copy);

        String cr = crashReport();
        if (cr != null && !cr.isEmpty()) {
            crashInfo.setText("Журнал прошлого краша:\n" + cr);
            crashInfo.setVisibility(View.VISIBLE);
            copy.setVisibility(View.VISIBLE);
        }

        return v;
    }

    private TextView makeText(String text, float size, int color) {
        return makeText(text, size, color, 0, 0, 0, 0);
    }

    private TextView makeText(String text, float size, int color, int pl, int pt, int pr, int pb) {
        TextView t = new TextView(this);
        t.setText(text);
        t.setTextColor(color);
        t.setTextSize(size);
        t.setPadding(pl, pt, pr, pb);
        return t;
    }

    private void showError(String detail) {
        web.setVisibility(View.GONE);
        errorView.setVisibility(View.VISIBLE);
        bar.setVisibility(View.GONE);
        if (detail != null) {
            crashInfo.setText(detail);
            crashInfo.setVisibility(View.VISIBLE);
        }
    }

    private void registerBackHandler() {
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (web.canGoBack()) web.goBack();
                else {
                    setEnabled(false);
                    getOnBackPressedDispatcher().onBackPressed();
                }
            }
        });
    }

    private String serverUrl() {
        return getSharedPreferences(PREFS, MODE_PRIVATE).getString(KEY_SERVER, null);
    }

    private void saveServerUrl(String url) {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit().putString(KEY_SERVER, url).apply();
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    @Override
    protected void onPause() {
        web.onPause();
        super.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        web.onResume();
    }

    @Override
    protected void onDestroy() {
        if (web.getParent() != null) ((ViewGroup) web.getParent()).removeView(web);
        web.destroy();
        super.onDestroy();
    }
}