package com.flutter_webview_plugin;


import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.graphics.Point;
import android.view.Display;
import android.webkit.WebStorage;
import android.widget.FrameLayout;
import android.webkit.CookieManager;
import android.webkit.ValueCallback;
import android.os.Build;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.PluginRegistry;

/**
 * FlutterWebviewPlugin
 */
public class FlutterWebviewPlugin implements MethodCallHandler, PluginRegistry.ActivityResultListener {
    private Activity activity;
    private WebviewManager webViewManager;
    private Context context;
    static MethodChannel channel;
    private static final String CHANNEL_NAME = "flutter_webview_plugin";
    private static final String JS_CHANNEL_NAMES_FIELD = "javascriptChannelNames";

    public static void registerWith(PluginRegistry.Registrar registrar) {
        if (registrar.activity() != null) {
            channel = new MethodChannel(registrar.messenger(), CHANNEL_NAME);
            final FlutterWebviewPlugin instance = new FlutterWebviewPlugin(registrar.activity(), registrar.activeContext());
            registrar.addActivityResultListener(instance);
            channel.setMethodCallHandler(instance);
        }
    }

    FlutterWebviewPlugin(Activity activity, Context context) {
        this.activity = activity;
        this.context = context;
    }

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        switch (call.method) {
            case "launch":
                openUrl(call, result);
                break;
            case "close":
                close(call, result);
                break;
            case "eval":
                eval(call, result);
                break;
            case "resize":
                resize(call, result);
                break;
            case "reload":
                reload(call, result);
                break;
            case "back":
                back(call, result);
                break;
            case "forward":
                forward(call, result);
                break;
            case "hide":
                hide(call, result);
                break;
            case "show":
                show(call, result);
                break;
            case "reloadUrl":
                reloadUrl(call, result);
                break;
            case "stopLoading":
                stopLoading(call, result);
                break;
            case "cleanCookies":
                cleanCookies(call, result);
                break;
            case "canGoBack":
                canGoBack(result);
                break;
            case "canGoForward":
                canGoForward(result);
                break;
            case "cleanCache":
                cleanCache(result);
                break;
            default:
                result.notImplemented();
                break;
        }
    }

    private void cleanCache(MethodChannel.Result result) {
        webViewManager.cleanCache();
        WebStorage.getInstance().deleteAllData();
        result.success(null);
    }

    void openUrl(MethodCall call, MethodChannel.Result result) {
        boolean hidden = call.argument("hidden");
        String url = call.argument("url");
        String userAgent = call.argument("userAgent");
        boolean withJavascript = call.argument("withJavascript");
        boolean clearCache = call.argument("clearCache");
        boolean clearCookies = call.argument("clearCookies");
        boolean mediaPlaybackRequiresUserGesture = call.argument("mediaPlaybackRequiresUserGesture");
        boolean withZoom = call.argument("withZoom");
        boolean displayZoomControls = call.argument("displayZoomControls");
        boolean withLocalStorage = call.argument("withLocalStorage");
        boolean withOverviewMode = call.argument("withOverviewMode");
        boolean supportMultipleWindows = call.argument("supportMultipleWindows");
        boolean appCacheEnabled = call.argument("appCacheEnabled");
        Map<String, String> headers = call.argument("headers");
        boolean scrollBar = call.argument("scrollBar");
        boolean allowFileURLs = call.argument("allowFileURLs");
        boolean useWideViewPort = call.argument("useWideViewPort");
        String invalidUrlRegex = call.argument("invalidUrlRegex");
        boolean geolocationEnabled = call.argument("geolocationEnabled");
        boolean debuggingEnabled = call.argument("debuggingEnabled");
        boolean ignoreSSLErrors = call.argument("ignoreSSLErrors");

        if (webViewManager == null || webViewManager.closed == true) {
            Map<String, Object> arguments = (Map<String, Object>) call.arguments;
            List<String> channelNames = new ArrayList();
            if (arguments.containsKey(JS_CHANNEL_NAMES_FIELD)) {
                @SuppressWarnings("unchecked")
                channelNames = (List<String>) arguments.get(JS_CHANNEL_NAMES_FIELD);
            }
            webViewManager = new WebviewManager(activity, context, channelNames);
        }

        FrameLayout.LayoutParams params = buildLayoutParams(call);

        activity.addContentView(webViewManager.webView, params);

        webViewManager.openUrl(withJavascript,
                clearCache,
                hidden,
                clearCookies,
                mediaPlaybackRequiresUserGesture,
                userAgent,
                url,
                headers,
                withZoom,
                displayZoomControls,
                withLocalStorage,
                withOverviewMode,
                scrollBar,
                supportMultipleWindows,
                appCacheEnabled,
                allowFileURLs,
                useWideViewPort,
                invalidUrlRegex,
                geolocationEnabled,
                debuggingEnabled,
                ignoreSSLErrors
        );
        result.success(null);
    }

    private FrameLayout.LayoutParams buildLayoutParams(MethodCall call) {
        Map<String, Number> rc = call.argument("rect");
        FrameLayout.LayoutParams params;
        if (rc != null) {
            params = new FrameLayout.LayoutParams(
                    dp2px(activity, rc.get("width").intValue()), dp2px(activity, rc.get("height").intValue()));
            params.setMargins(dp2px(activity, rc.get("left").intValue()), dp2px(activity, rc.get("top").intValue()),
                    0, 0);
        } else {
            Display display = activity.getWindowManager().getDefaultDisplay();
            Point size = new Point();
            display.getSize(size);
            int width = size.x;
            int height = size.y;
            params = new FrameLayout.LayoutParams(width, height);
        }

        return params;
    }

    private void stopLoading(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.stopLoading(call, result);
        }
        result.success(null);
    }

    void close(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.close(call, result);
            webViewManager = null;
        }
    }

    /**
     * Checks if can navigate back
     *
     * @param result
     */
    private void canGoBack(MethodChannel.Result result) {
        if (webViewManager != null) {
            result.success(webViewManager.canGoBack());
        } else {
            result.error("Webview is null", null, null);
        }
    }

    /**
     * Navigates back on the Webview.
     */
    private void back(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.back(call, result);
        }
        result.success(null);
    }

    /**
     * Checks if can navigate forward
     * @param result
     */
    private void canGoForward(MethodChannel.Result result) {
        if (webViewManager != null) {
            result.success(webViewManager.canGoForward());
        } else {
            result.error("Webview is null", null, null);
        }
    }

    /**
     * Navigates forward on the Webview.
     */
    private void forward(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.forward(call, result);
        }
        result.success(null);
    }

    /**
     * Reloads the Webview.
     */
    private void reload(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.reload(call, result);
        }
        result.success(null);
    }

    private void reloadUrl(MethodCall call, MethodChannel.Result result) {
        if (webViewManager != null) {
            String url = call.argument("url");
            Map<String, String> headers = call.argument("headers");
            if (headers != null) {
                webViewManager.reloadUrl(url, headers);
            } else {
                webViewManager.reloadUrl(url);
            }

        }
        result.success(null);
    }

    private void eval(MethodCall call, final MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.eval(call, result);
        }
    }

    private void resize(MethodCall call, final MethodChannel.Result result) {
        if (webViewManager != null) {
            FrameLayout.LayoutParams params = buildLayoutParams(call);
            webViewManager.resize(params);
        }
        result.success(null);
    }

    private void hide(MethodCall call, final MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.hide(call, result);
        }
        result.success(null);
    }

    private void show(MethodCall call, final MethodChannel.Result result) {
        if (webViewManager != null) {
            webViewManager.show(call, result);
        }
        result.success(null);
    }

    private void cleanCookies(MethodCall call, final MethodChannel.Result result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            CookieManager.getInstance().removeAllCookies(new ValueCallback<Boolean>() {
                @Override
                public void onReceiveValue(Boolean aBoolean) {

                }
            });
        } else {
            CookieManager.getInstance().removeAllCookie();
        }
        result.success(null);
    }

    private int dp2px(Context context, float dp) {
        final float scale = context.getResources().getDisplayMetrics().density;
        return (int) (dp * scale + 0.5f);
    }

    @Override
    public boolean onActivityResult(int i, int i1, Intent intent) {
        if (webViewManager != null && webViewManager.resultHandler != null) {
            return webViewManager.resultHandler.handleResult(i, i1, intent);
        }
        return false;
    }
}
