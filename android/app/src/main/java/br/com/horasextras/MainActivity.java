package br.com.horasextras;

import android.app.Activity;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.print.PrintAttributes;
import android.print.PrintDocumentAdapter;
import android.print.PrintManager;
import android.provider.MediaStore;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import androidx.webkit.WebViewAssetLoader;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

/**
 * App Horas Extras: carrega o site (pasta web/) a partir dos arquivos do próprio APK,
 * servido em um endereço https local para que salvamento de dados e leitura de imagens funcionem.
 */
public class MainActivity extends Activity {

    private static final String HOST = "appassets.androidplatform.net";
    private static final String START = "https://" + HOST + "/assets/index.html";
    private static final int FILE_REQ = 41;

    private WebView web;
    private ValueCallback<Uri[]> fileCallback;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        web = new WebView(this);
        setContentView(web);

        final WebViewAssetLoader loader = new WebViewAssetLoader.Builder()
                .addPathHandler("/assets/", new WebViewAssetLoader.AssetsPathHandler(this))
                .build();

        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);

        web.setWebViewClient(new WebViewClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
                return loader.shouldInterceptRequest(request.getUrl());
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri u = request.getUrl();
                if (HOST.equals(u.getHost())) return false;
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, u));   // links externos abrem no navegador
                } catch (Exception ignored) { }
                return true;
            }
        });

        web.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (fileCallback != null) fileCallback.onReceiveValue(null);
                fileCallback = callback;
                // tipos aceitos pela página (ex.: "image/*,application/pdf,.pdf")
                java.util.ArrayList<String> mimes = new java.util.ArrayList<>();
                String[] accept = params.getAcceptTypes();
                if (accept != null) {
                    for (String a : accept) {
                        if (a == null) continue;
                        for (String part : a.split(",")) {
                            String t = part.trim();
                            if (t.equals(".pdf")) t = "application/pdf";
                            if (t.equals(".json")) t = "application/json";
                            if (t.contains("/") && !mimes.contains(t)) mimes.add(t);
                        }
                    }
                }
                Intent i = new Intent(Intent.ACTION_GET_CONTENT);
                i.addCategory(Intent.CATEGORY_OPENABLE);
                if (mimes.contains("application/json") || mimes.isEmpty()) {
                    i.setType("*/*");                 // backups .json podem vir sem tipo definido
                } else if (mimes.size() == 1) {
                    i.setType(mimes.get(0));
                } else {
                    i.setType("*/*");
                    i.putExtra(Intent.EXTRA_MIME_TYPES, mimes.toArray(new String[0]));
                }
                if (params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE) {
                    i.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
                }
                try {
                    startActivityForResult(Intent.createChooser(i, "Escolher arquivo"), FILE_REQ);
                } catch (Exception e) {
                    fileCallback = null;
                    return false;
                }
                return true;
            }
        });

        web.addJavascriptInterface(new Bridge(), "AndroidBridge");

        if (savedInstanceState != null) web.restoreState(savedInstanceState);
        else web.loadUrl(START);
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == FILE_REQ && fileCallback != null) {
            Uri[] result = null;
            if (resultCode == RESULT_OK && data != null) {
                if (data.getClipData() != null) {
                    int n = data.getClipData().getItemCount();
                    result = new Uri[n];
                    for (int k = 0; k < n; k++) result[k] = data.getClipData().getItemAt(k).getUri();
                } else if (data.getData() != null) {
                    result = new Uri[]{data.getData()};
                }
            }
            fileCallback.onReceiveValue(result);
            fileCallback = null;
            return;
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        web.saveState(outState);
    }

    @Override
    public void onBackPressed() {
        // o próprio app decide: fecha a janela de importação ou volta para "Lançamentos"
        web.evaluateJavascript("(window.appBack && window.appBack()) ? 'true' : 'false'", value -> {
            if (value != null && value.contains("true")) return;
            if (web.canGoBack()) web.goBack();
            else finish();
        });
    }

    private void toast(final String msg) {
        runOnUiThread(() -> Toast.makeText(MainActivity.this, msg, Toast.LENGTH_LONG).show());
    }

    /** Funções chamadas pela página (salvar arquivos e imprimir). */
    private class Bridge {

        @JavascriptInterface
        public boolean isApp() {
            return true;
        }

        @JavascriptInterface
        public boolean saveText(String name, String mime, String content) {
            try {
                byte[] bytes = content.getBytes(StandardCharsets.UTF_8);
                if (Build.VERSION.SDK_INT >= 29) {
                    ContentValues cv = new ContentValues();
                    cv.put(MediaStore.MediaColumns.DISPLAY_NAME, name);
                    cv.put(MediaStore.MediaColumns.MIME_TYPE, mime);
                    cv.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS);
                    Uri uri = getContentResolver().insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cv);
                    if (uri == null) throw new IllegalStateException("sem destino");
                    OutputStream os = getContentResolver().openOutputStream(uri);
                    if (os == null) throw new IllegalStateException("sem destino");
                    try {
                        os.write(bytes);
                    } finally {
                        os.close();
                    }
                    toast("Salvo em Downloads: " + name);
                } else {
                    File dir = getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
                    File f = new File(dir, name);
                    FileOutputStream os = new FileOutputStream(f);
                    try {
                        os.write(bytes);
                    } finally {
                        os.close();
                    }
                    toast("Salvo em: " + f.getAbsolutePath());
                }
                return true;
            } catch (Exception e) {
                toast("Não foi possível salvar o arquivo");
                return false;
            }
        }

        @JavascriptInterface
        public void print() {
            runOnUiThread(() -> {
                PrintManager pm = (PrintManager) getSystemService(Context.PRINT_SERVICE);
                PrintDocumentAdapter adapter = web.createPrintDocumentAdapter("Horas Extras");
                pm.print("Horas Extras", adapter, new PrintAttributes.Builder().build());
            });
        }
    }
}
