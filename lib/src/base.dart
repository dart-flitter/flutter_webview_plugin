import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webview_plugin/src/javascript_channel.dart';

import 'javascript_message.dart';

const _kChannel = 'flutter_webview_plugin';

// TODO: more general state for iOS/android
enum WebViewState { shouldStart, startLoad, finishLoad, abortLoad }

// TODO: use an id by webview to be able to manage multiple webview

/// Singleton class that communicate with a Webview Instance
class FlutterWebviewPlugin {
  factory FlutterWebviewPlugin() {
    if(_instance == null) {
      const MethodChannel methodChannel = const MethodChannel(_kChannel);
      _instance = FlutterWebviewPlugin.private(methodChannel);
    }
    return _instance;
  }

  @visibleForTesting
  FlutterWebviewPlugin.private(this._channel) {
    _channel.setMethodCallHandler(_handleMessages);
  }

  static FlutterWebviewPlugin _instance;

  final MethodChannel _channel;

  final _onBack = StreamController<Null>.broadcast();
  final _onDestroy = StreamController<Null>.broadcast();
  final _onUrlChanged = StreamController<String>.broadcast();
  final _onStateChanged = StreamController<WebViewStateChanged>.broadcast();
  final _onScrollXChanged = StreamController<double>.broadcast();
  final _onScrollYChanged = StreamController<double>.broadcast();
  final _onProgressChanged = new StreamController<double>.broadcast();
  final _onHttpError = StreamController<WebViewHttpError>.broadcast();
  final _onPostMessage = StreamController<JavascriptMessage>.broadcast();

  final Map<String, JavascriptChannel> _javascriptChannels =
      // ignoring warning as min SDK version doesn't support collection literals yet
      // ignore: prefer_collection_literals
      Map<String, JavascriptChannel>();

  Future<dynamic> _handleMessages(MethodCall call) async {
    switch (call.method) {
      case 'onBack':
        _onBack.add(null);
        break;
      case 'onDestroy':
        _onDestroy.add(null);
        break;
      case 'onUrlChanged':
        _onUrlChanged.add(call.arguments['url']);
        break;
      case 'onScrollXChanged':
        _onScrollXChanged.add(call.arguments['xDirection']);
        break;
      case 'onScrollYChanged':
        _onScrollYChanged.add(call.arguments['yDirection']);
        break;
      case 'onJsAlert':
        if (onJSAlert != null) {
          await onJSAlert(WebViewJSAlert(
              url: call.arguments['url'], message: call.arguments['message']));
        }
        return null;
      case 'onJsConfirm':
        if (onJSConfirm != null) {
          final result = await onJSConfirm(WebViewJSConfirm(
              url: call.arguments['url'], message: call.arguments['message']));
          return result;
        }
        return false;
      case 'onJsPrompt':
        if (onJSPrompt != null) {
          final result = await onJSPrompt(WebViewJSPrompt(
              url: call.arguments['url'],
              message: call.arguments['message'],
              defaultText: call.arguments['defaultText']));
          return result;
        }
        return '';
      case 'onProgressChanged':
        _onProgressChanged.add(call.arguments['progress']);
        break;
      case 'onState':
        _onStateChanged.add(
          WebViewStateChanged.fromMap(
            Map<String, dynamic>.from(call.arguments),
          ),
        );
        break;
      case 'onHttpError':
        _onHttpError.add(
            WebViewHttpError(call.arguments['code'], call.arguments['url']));
        break;
      case 'javascriptChannelMessage':
        _handleJavascriptChannelMessage(
            call.arguments['channel'], call.arguments['message']);
        break;
    }
  }

  Future<Null> Function(WebViewJSAlert alert) onJSAlert;

  Future<bool> Function(WebViewJSConfirm confirm) onJSConfirm;

  Future<String> Function(WebViewJSPrompt prompt) onJSPrompt;

  /// Listening the OnDestroy LifeCycle Event for Android
  Stream<Null> get onDestroy => _onDestroy.stream;

  /// Listening the back key press Event for Android
  Stream<Null> get onBack => _onBack.stream;

  /// Listening url changed
  Stream<String> get onUrlChanged => _onUrlChanged.stream;

  /// Listening the onState Event for iOS WebView and Android
  /// content is Map for type: {shouldStart(iOS)|startLoad|finishLoad}
  /// more detail than other events
  Stream<WebViewStateChanged> get onStateChanged => _onStateChanged.stream;

  /// Listening web view loading progress estimation, value between 0.0 and 1.0
  Stream<double> get onProgressChanged => _onProgressChanged.stream;

  /// Listening web view y position scroll change
  Stream<double> get onScrollYChanged => _onScrollYChanged.stream;

  /// Listening web view x position scroll change
  Stream<double> get onScrollXChanged => _onScrollXChanged.stream;

  Stream<WebViewHttpError> get onHttpError => _onHttpError.stream;

  /// Start the Webview with [url]
  /// - [headers] specify additional HTTP headers
  /// - [withJavascript] enable Javascript or not for the Webview
  /// - [clearCache] clear the cache of the Webview
  /// - [clearCookies] clear all cookies of the Webview
  /// - [hidden] not show
  /// - [rect]: show in rect, fullscreen if null
  /// - [enableAppScheme]: false will enable all schemes, true only for httt/https/about
  ///     android: Not implemented yet
  /// - [userAgent]: set the User-Agent of WebView
  /// - [withZoom]: enable zoom on webview
  /// - [withLocalStorage] enable localStorage API on Webview
  ///     Currently Android only.
  ///     It is always enabled in UIWebView of iOS and  can not be disabled.
  /// - [withLocalUrl]: allow url as a local path
  ///     Allow local files on iOs > 9.0
  /// - [localUrlScope]: allowed folder for local paths
  ///     iOS only.
  ///     If null and withLocalUrl is true, then it will use the url as the scope,
  ///     allowing only itself to be read.
  /// - [scrollBar]: enable or disable scrollbar
  /// - [supportMultipleWindows] enable multiple windows support in Android
  /// - [invalidUrlRegex] is the regular expression of URLs that web view shouldn't load.
  /// For example, when webview is redirected to a specific URL, you want to intercept
  /// this process by stopping loading this URL and replacing webview by another screen.
  ///   Android only settings:
  /// - [displayZoomControls]: display zoom controls on webview
  /// - [withOverviewMode]: enable overview mode for Android webview ( setLoadWithOverviewMode )
  /// - [useWideViewPort]: use wide viewport for Android webview ( setUseWideViewPort )
  /// - [ignoreSSLErrors]: use to bypass Android/iOS SSL checks e.g. for self-signed certificates
  Future<Null> launch(
    String url, {
    Map<String, String> headers,
    Set<JavascriptChannel> javascriptChannels,
    bool withJavascript,
    bool clearCache,
    bool clearCookies,
    bool mediaPlaybackRequiresUserGesture,
    bool hidden,
    bool enableAppScheme,
    Rect rect,
    String userAgent,
    bool withZoom,
    bool displayZoomControls,
    bool withLocalStorage,
    bool withLocalUrl,
    String localUrlScope,
    bool withOverviewMode,
    bool scrollBar,
    bool supportMultipleWindows,
    bool appCacheEnabled,
    bool allowFileURLs,
    bool useWideViewPort,
    String invalidUrlRegex,
    bool geolocationEnabled,
    bool debuggingEnabled,
    bool ignoreSSLErrors,
  }) async {
    final args = <String, dynamic>{
      'url': url,
      'withJavascript': withJavascript ?? true,
      'clearCache': clearCache ?? false,
      'hidden': hidden ?? false,
      'clearCookies': clearCookies ?? false,
      'mediaPlaybackRequiresUserGesture': mediaPlaybackRequiresUserGesture ?? true,
      'enableAppScheme': enableAppScheme ?? true,
      'userAgent': userAgent,
      'withZoom': withZoom ?? false,
      'displayZoomControls': displayZoomControls ?? false,
      'withLocalStorage': withLocalStorage ?? true,
      'withLocalUrl': withLocalUrl ?? false,
      'localUrlScope': localUrlScope,
      'scrollBar': scrollBar ?? true,
      'supportMultipleWindows': supportMultipleWindows ?? false,
      'appCacheEnabled': appCacheEnabled ?? false,
      'allowFileURLs': allowFileURLs ?? false,
      'useWideViewPort': useWideViewPort ?? false,
      'invalidUrlRegex': invalidUrlRegex,
      'geolocationEnabled': geolocationEnabled ?? false,
      'withOverviewMode': withOverviewMode ?? false,
      'debuggingEnabled': debuggingEnabled ?? false,
      'ignoreSSLErrors': ignoreSSLErrors ?? false,
    };

    if (headers != null) {
      args['headers'] = headers;
    }

    _assertJavascriptChannelNamesAreUnique(javascriptChannels);

    if (javascriptChannels != null) {
      javascriptChannels.forEach((channel) {
        _javascriptChannels[channel.name] = channel;
      });
    } else {
      if (_javascriptChannels.isNotEmpty) {
        _javascriptChannels.clear();
      }
    }

    args['javascriptChannelNames'] =
        _extractJavascriptChannelNames(javascriptChannels).toList();

    if (rect != null) {
      args['rect'] = {
        'left': rect.left,
        'top': rect.top,
        'width': rect.width,
        'height': rect.height,
      };
    }
    await _channel.invokeMethod('launch', args);
  }

  /// Execute Javascript inside webview
  Future<String> evalJavascript(String code) async {
    final res = await _channel.invokeMethod('eval', {'code': code});
    return res;
  }

  /// Close the Webview
  /// Will trigger the [onDestroy] event
  Future<Null> close() async {
    _javascriptChannels.clear();
    await _channel.invokeMethod('close');
  }

  /// Reloads the WebView.
  Future<Null> reload() async => await _channel.invokeMethod('reload');

  /// Navigates back on the Webview.
  Future<Null> goBack() async => await _channel.invokeMethod('back');

  /// Checks if webview can navigate back
  Future<bool> canGoBack() async => await _channel.invokeMethod('canGoBack');

  /// Checks if webview can navigate back
  Future<bool> canGoForward() async => await _channel.invokeMethod('canGoForward');

  /// Navigates forward on the Webview.
  Future<Null> goForward() async => await _channel.invokeMethod('forward');

  // Hides the webview
  Future<Null> hide() async => await _channel.invokeMethod('hide');

  // Shows the webview
  Future<Null> show() async => await _channel.invokeMethod('show');

  // Clears browser cache
  Future<Null> clearCache() async => await _channel.invokeMethod('cleanCache');

  // Reload webview with a url
  Future<Null> reloadUrl(String url, {Map<String, String> headers}) async {
    final args = <String, dynamic>{'url': url};
    if (headers != null) {
      args['headers'] = headers;
    }
    await _channel.invokeMethod('reloadUrl', args);
  }

  // Clean cookies on WebView
  Future<Null> cleanCookies() async {
    // one liner to clear javascript cookies
    await evalJavascript('document.cookie.split(";").forEach(function(c) { document.cookie = c.replace(/^ +/, "").replace(/=.*/, "=;expires=" + new Date().toUTCString() + ";path=/"); });');
    return await _channel.invokeMethod('cleanCookies');
  }

  // Stops current loading process
  Future<Null> stopLoading() async =>
      await _channel.invokeMethod('stopLoading');

  /// Close all Streams
  void dispose() {
    _onDestroy.close();
    _onUrlChanged.close();
    _onStateChanged.close();
    _onProgressChanged.close();
    _onScrollXChanged.close();
    _onScrollYChanged.close();
    _onHttpError.close();
    _onPostMessage.close();
    _instance = null;
  }

  Future<Map<String, String>> getCookies() async {
    final cookiesString = await evalJavascript('document.cookie');
    final cookies = <String, String>{};

    if (cookiesString?.isNotEmpty == true) {
      cookiesString.split(';').forEach((String cookie) {
        final split = cookie.split('=');
        cookies[split[0]] = split[1];
      });
    }

    return cookies;
  }

  /// resize webview
  Future<Null> resize(Rect rect) async {
    final args = {};
    args['rect'] = {
      'left': rect.left,
      'top': rect.top,
      'width': rect.width,
      'height': rect.height,
    };
    await _channel.invokeMethod('resize', args);
  }

  Set<String> _extractJavascriptChannelNames(Set<JavascriptChannel> channels) {
    final Set<String> channelNames = channels == null
        // ignore: prefer_collection_literals
        ? Set<String>()
        : channels.map((JavascriptChannel channel) => channel.name).toSet();
    return channelNames;
  }

  void _handleJavascriptChannelMessage(
      final String channelName, final String message) {
    _javascriptChannels[channelName]
        .onMessageReceived(JavascriptMessage(message));
  }

  void _assertJavascriptChannelNamesAreUnique(
      final Set<JavascriptChannel> channels) {
    if (channels == null || channels.isEmpty) {
      return;
    }

    assert(_extractJavascriptChannelNames(channels).length == channels.length);
  }
}

class WebViewStateChanged {
  WebViewStateChanged(this.type, this.url, this.navigationType);

  factory WebViewStateChanged.fromMap(Map<String, dynamic> map) {
    WebViewState t;
    switch (map['type']) {
      case 'shouldStart':
        t = WebViewState.shouldStart;
        break;
      case 'startLoad':
        t = WebViewState.startLoad;
        break;
      case 'finishLoad':
        t = WebViewState.finishLoad;
        break;
      case 'abortLoad':
        t = WebViewState.abortLoad;
        break;
    }
    return WebViewStateChanged(t, map['url'], map['navigationType']);
  }

  final WebViewState type;
  final String url;
  final int navigationType;
}

class WebViewHttpError {
  WebViewHttpError(this.code, this.url);

  final String url;
  final String code;
}

class WebViewJSAlert {
  WebViewJSAlert({this.url, this.message});

  final String url;
  final String message;
}

class WebViewJSConfirm {
  WebViewJSConfirm({this.url, this.message});

  final String url;
  final String message;
}

class WebViewJSPrompt {
  WebViewJSPrompt({this.url, this.message, this.defaultText});

  final String url;
  final String message;
  final String defaultText;
}
