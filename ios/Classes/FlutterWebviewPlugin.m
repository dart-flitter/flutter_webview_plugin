#import "FlutterWebviewPlugin.h"
#import "WebviewJavaScriptChannelHandler.h"

static NSString *const CHANNEL_NAME = @"flutter_webview_plugin";

// UIWebViewDelegate
@interface FlutterWebviewPlugin() <WKNavigationDelegate, UIScrollViewDelegate, WKUIDelegate> {
    BOOL _enableAppScheme;
    BOOL _enableZoom;
    NSString* _invalidUrlRegex;
    NSMutableSet* _javaScriptChannelNames;
    NSNumber*  _ignoreSSLErrors;
}
@end

@implementation FlutterWebviewPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    channel = [FlutterMethodChannel
               methodChannelWithName:CHANNEL_NAME
               binaryMessenger:[registrar messenger]];

    UIViewController *viewController = [UIApplication sharedApplication].delegate.window.rootViewController;
    FlutterWebviewPlugin* instance = [[FlutterWebviewPlugin alloc] initWithViewController:viewController];
    
    [registrar addMethodCallDelegate:instance channel:channel];
}

- (instancetype)initWithViewController:(UIViewController *)viewController {
    self = [super init];
    if (self) {
        self.viewController = viewController;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"launch" isEqualToString:call.method]) {
        if (!self.webview)
            [self initWebview:call withResult:result];
        else
            [self navigate:call];
        result(nil);
    } else if ([@"close" isEqualToString:call.method]) {
        [self closeWebView];
        result(nil);
    } else if ([@"eval" isEqualToString:call.method]) {
        [self evalJavascript:call completionHandler:^(NSString * response) {
            result(response);
        }];
    } else if ([@"resize" isEqualToString:call.method]) {
        [self resize:call];
        result(nil);
    } else if ([@"reloadUrl" isEqualToString:call.method]) {
        [self reloadUrl:call];
        result(nil);
    } else if ([@"show" isEqualToString:call.method]) {
        [self show];
        result(nil);
    } else if ([@"hide" isEqualToString:call.method]) {
        [self hide];
        result(nil);
    } else if ([@"stopLoading" isEqualToString:call.method]) {
        [self stopLoading];
        result(nil);
    } else if ([@"cleanCookies" isEqualToString:call.method]) {
        [self cleanCookies:result];
    } else if ([@"back" isEqualToString:call.method]) {
        [self back];
        result(nil);
    } else if ([@"forward" isEqualToString:call.method]) {
        [self forward];
        result(nil);
    } else if ([@"reload" isEqualToString:call.method]) {
        [self reload];
        result(nil);
    } else if ([@"canGoBack" isEqualToString:call.method]) {
        [self onCanGoBack:call result:result];
    } else if ([@"canGoForward" isEqualToString:call.method]) {
        [self onCanGoForward:call result:result];
    } else if ([@"cleanCache" isEqualToString:call.method]) {
        [self cleanCache:result];
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)initWebview:(FlutterMethodCall*)call withResult:(FlutterResult)result {
    NSNumber *clearCache = call.arguments[@"clearCache"];
    NSNumber *clearCookies = call.arguments[@"clearCookies"];
    NSNumber *hidden = call.arguments[@"hidden"];
    NSDictionary *rect = call.arguments[@"rect"];
    _enableAppScheme = call.arguments[@"enableAppScheme"];
    NSString *userAgent = call.arguments[@"userAgent"];
    NSNumber *withZoom = call.arguments[@"withZoom"];
    NSNumber *scrollBar = call.arguments[@"scrollBar"];
    NSNumber *withJavascript = call.arguments[@"withJavascript"];
    _invalidUrlRegex = call.arguments[@"invalidUrlRegex"];
    _ignoreSSLErrors = call.arguments[@"ignoreSSLErrors"];
    _javaScriptChannelNames = [[NSMutableSet alloc] init];
    
    WKUserContentController* userContentController = [[WKUserContentController alloc] init];
    if ([call.arguments[@"javascriptChannelNames"] isKindOfClass:[NSArray class]]) {
        NSArray* javaScriptChannelNames = call.arguments[@"javascriptChannelNames"];
        [_javaScriptChannelNames addObjectsFromArray:javaScriptChannelNames];
        [self registerJavaScriptChannels:_javaScriptChannelNames controller:userContentController];
    }

    if (clearCache != (id)[NSNull null] && [clearCache boolValue]) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
        [self cleanCache:result];

    }

    if (clearCookies != (id)[NSNull null] && [clearCookies boolValue]) {
        NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        for (NSHTTPCookie *cookie in [storage cookies])
        {
            [storage deleteCookie:cookie];
        }

        [self cleanCookies:result];

    }

    if (userAgent != (id)[NSNull null]) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    }

    CGRect rc;
    if (rect != nil) {
        rc = [self parseRect:rect];
    } else {
        rc = self.viewController.view.bounds;
    }

    WKWebViewConfiguration* configuration = [[WKWebViewConfiguration alloc] init];
    configuration.userContentController = userContentController;
    self.webview = [[WKWebView alloc] initWithFrame:rc configuration:configuration];
    self.webview.UIDelegate = self;
    self.webview.navigationDelegate = self;
    self.webview.scrollView.delegate = self;
    self.webview.hidden = [hidden boolValue];
    self.webview.scrollView.showsHorizontalScrollIndicator = [scrollBar boolValue];
    self.webview.scrollView.showsVerticalScrollIndicator = [scrollBar boolValue];
    
    [self.webview addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];

    WKPreferences* preferences = [[self.webview configuration] preferences];
    if ([withJavascript boolValue]) {
        [preferences setJavaScriptEnabled:YES];
    } else {
        [preferences setJavaScriptEnabled:NO];
    }

    _enableZoom = [withZoom boolValue];

    UIViewController* presentedViewController = self.viewController.presentedViewController;
    UIViewController* currentViewController = presentedViewController != nil ? presentedViewController : self.viewController;
    [currentViewController.view addSubview:self.webview];

    [self navigate:call];
}

- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([_ignoreSSLErrors boolValue]){
        SecTrustRef serverTrust = challenge.protectionSpace.serverTrust;
        CFDataRef exceptions = SecTrustCopyExceptions(serverTrust);
        SecTrustSetExceptions(serverTrust, exceptions);
        CFRelease(exceptions);
        completionHandler(NSURLSessionAuthChallengeUseCredential,
                          [NSURLCredential credentialForTrust:serverTrust]);
    }
    else {
        completionHandler(NSURLSessionAuthChallengePerformDefaultHandling,nil);
    }
    
}

- (CGRect)parseRect:(NSDictionary *)rect {
    return CGRectMake([[rect valueForKey:@"left"] doubleValue],
                      [[rect valueForKey:@"top"] doubleValue],
                      [[rect valueForKey:@"width"] doubleValue],
                      [[rect valueForKey:@"height"] doubleValue]);
}

- (void) scrollViewDidScroll:(UIScrollView *)scrollView {
    id xDirection = @{@"xDirection": @(scrollView.contentOffset.x) };
    [channel invokeMethod:@"onScrollXChanged" arguments:xDirection];

    id yDirection = @{@"yDirection": @(scrollView.contentOffset.y) };
    [channel invokeMethod:@"onScrollYChanged" arguments:yDirection];
}

- (void)navigate:(FlutterMethodCall*)call {
    if (self.webview != nil) {
            NSString *url = call.arguments[@"url"];
            NSNumber *withLocalUrl = call.arguments[@"withLocalUrl"];
            if ( [withLocalUrl boolValue]) {
                NSURL *htmlUrl = [NSURL fileURLWithPath:url isDirectory:false];
                NSString *localUrlScope = call.arguments[@"localUrlScope"];
                if (@available(iOS 9.0, *)) {
                    if(localUrlScope == nil) {
                        [self.webview loadFileURL:htmlUrl allowingReadAccessToURL:htmlUrl];
                    }
                    else {
                        NSURL *scopeUrl = [NSURL fileURLWithPath:localUrlScope];
                        [self.webview loadFileURL:htmlUrl allowingReadAccessToURL:scopeUrl];
                    }
                } else {
                    @throw @"not available on version earlier than ios 9.0";
                }
            } else {
                NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
                NSDictionary *headers = call.arguments[@"headers"];

                if (headers != nil) {
                    [request setAllHTTPHeaderFields:headers];
                }

                [self.webview loadRequest:request];
            }
        }
}

- (void)evalJavascript:(FlutterMethodCall*)call
     completionHandler:(void (^_Nullable)(NSString * response))completionHandler {
    if (self.webview != nil) {
        NSString *code = call.arguments[@"code"];
        [self.webview evaluateJavaScript:code
                       completionHandler:^(id _Nullable response, NSError * _Nullable error) {
            completionHandler([NSString stringWithFormat:@"%@", response]);
        }];
    } else {
        completionHandler(nil);
    }
}

- (void)resize:(FlutterMethodCall*)call {
    if (self.webview != nil) {
        NSDictionary *rect = call.arguments[@"rect"];
        CGRect rc = [self parseRect:rect];
        self.webview.frame = rc;
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"] && object == self.webview) {
        [channel invokeMethod:@"onProgressChanged" arguments:@{@"progress": @(self.webview.estimatedProgress)}];
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

- (void)closeWebView {
    if (self.webview != nil) {
        [self.webview stopLoading];
        [self.webview removeFromSuperview];
        self.webview.navigationDelegate = nil;
        [self.webview removeObserver:self forKeyPath:@"estimatedProgress"];
        self.webview = nil;

        // manually trigger onDestroy
        [channel invokeMethod:@"onDestroy" arguments:nil];
    }
}

- (void)reloadUrl:(FlutterMethodCall*)call {
    if (self.webview != nil) {
		NSString *url = call.arguments[@"url"];
		NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        NSDictionary *headers = call.arguments[@"headers"];
        
        if (headers != nil) {
            [request setAllHTTPHeaderFields:headers];
        }
        
        [self.webview loadRequest:request];
    }
}

- (void)cleanCookies:(FlutterResult)result {
    if(self.webview != nil) {
        [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        }];
        if (@available(iOS 9.0, *)) {
          NSSet<NSString *> *websiteDataTypes = [NSSet setWithObject:WKWebsiteDataTypeCookies];
          WKWebsiteDataStore *dataStore = [WKWebsiteDataStore defaultDataStore];

          void (^deleteAndNotify)(NSArray<WKWebsiteDataRecord *> *) =
              ^(NSArray<WKWebsiteDataRecord *> *cookies) {
                [dataStore removeDataOfTypes:websiteDataTypes
                              forDataRecords:cookies
                           completionHandler:^{
                            result(nil);
                           }];
              };

          [dataStore fetchDataRecordsOfTypes:websiteDataTypes completionHandler:deleteAndNotify];
        } else {
          // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
          NSLog(@"Clearing cookies is not supported for Flutter WebViews prior to iOS 9.");
        }
    }
}

- (void)cleanCache:(FlutterResult)result {
    if (self.webview != nil) {
       if (@available(iOS 9.0, *)) {
          NSSet* cacheDataTypes = [WKWebsiteDataStore allWebsiteDataTypes];
          WKWebsiteDataStore* dataStore = [WKWebsiteDataStore defaultDataStore];
          NSDate* dateFrom = [NSDate dateWithTimeIntervalSince1970:0];
          [dataStore removeDataOfTypes:cacheDataTypes
                         modifiedSince:dateFrom
                     completionHandler:^{
              result(nil);
                     }];
        } else {
          // support for iOS8 tracked in https://github.com/flutter/flutter/issues/27624.
          NSLog(@"Clearing cache is not supported for Flutter WebViews prior to iOS 9.");
        }
    }
}

- (void)show {
    if (self.webview != nil) {
        self.webview.hidden = false;
    }
}

- (void)hide {
    if (self.webview != nil) {
        self.webview.hidden = true;
    }
}
- (void)stopLoading {
    if (self.webview != nil) {
        [self.webview stopLoading];
    }
}
- (void)back {
    if (self.webview != nil) {
        [self.webview goBack];
    }
}

- (void)onCanGoBack:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoBack = [self.webview canGoBack];
  result([NSNumber numberWithBool:canGoBack]);
}

- (void)onCanGoForward:(FlutterMethodCall*)call result:(FlutterResult)result {
  BOOL canGoForward = [self.webview canGoForward];
  result([NSNumber numberWithBool:canGoForward]);
}

- (void)forward {
    if (self.webview != nil) {
        [self.webview goForward];
    }
}
- (void)reload {
    if (self.webview != nil) {
        [self.webview reload];
    }
}

- (bool)checkInvalidUrl:(NSURL*)url {
  NSString* urlString = url != nil ? [url absoluteString] : nil;
  if (![_invalidUrlRegex isEqual:[NSNull null]] && urlString != nil) {
    NSError* error = NULL;
    NSRegularExpression* regex =
        [NSRegularExpression regularExpressionWithPattern:_invalidUrlRegex
                                                  options:NSRegularExpressionCaseInsensitive
                                                    error:&error];
    NSTextCheckingResult* match = [regex firstMatchInString:urlString
                                                    options:0
                                                      range:NSMakeRange(0, [urlString length])];
    return match != nil;
  } else {
    return false;
  }
}

#pragma mark -- WkWebView Delegate
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {

    BOOL isInvalid = [self checkInvalidUrl: navigationAction.request.URL];
    
    id data = @{@"url": navigationAction.request.URL.absoluteString,
                @"type": isInvalid ? @"abortLoad" : @"shouldStart",
                @"navigationType": [NSNumber numberWithInteger:navigationAction.navigationType]};
    [channel invokeMethod:@"onState" arguments:data];

    if (navigationAction.navigationType == WKNavigationTypeBackForward) {
        [channel invokeMethod:@"onBackPressed" arguments:nil];
    } else if (!isInvalid) {
        id data = @{@"url": navigationAction.request.URL.absoluteString};
        [channel invokeMethod:@"onUrlChanged" arguments:data];
    }

    if (_enableAppScheme ||
        ([webView.URL.scheme isEqualToString:@"http"] ||
         [webView.URL.scheme isEqualToString:@"https"] ||
         [webView.URL.scheme isEqualToString:@"about"] ||
         [webView.URL.scheme isEqualToString:@"file"])) {
         if (isInvalid) {
            decisionHandler(WKNavigationActionPolicyCancel);
         } else {
            decisionHandler(WKNavigationActionPolicyAllow);
         }
    } else {
        decisionHandler(WKNavigationActionPolicyCancel);
    }
}

- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
    forNavigationAction:(WKNavigationAction *)navigationAction windowFeatures:(WKWindowFeatures *)windowFeatures {

    if (!navigationAction.targetFrame.isMainFrame) {
        [webView loadRequest:navigationAction.request];
    }

    return nil;
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"startLoad", @"url": webView.URL.absoluteString}];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSString* url = webView.URL == nil ? @"?" : webView.URL.absoluteString;
    
    [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", error.code], @"url": url}];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    [channel invokeMethod:@"onState" arguments:@{@"type": @"finishLoad", @"url": webView.URL.absoluteString}];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", error.code], @"error": error.localizedDescription}];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse * response = (NSHTTPURLResponse *)navigationResponse.response;

        if (response.statusCode >= 400) {
            [channel invokeMethod:@"onHttpError" arguments:@{@"code": [NSString stringWithFormat:@"%ld", response.statusCode], @"url": webView.URL.absoluteString}];
        }
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)registerJavaScriptChannels:(NSSet*)channelNames
                        controller:(WKUserContentController*)userContentController {
    for (NSString* channelName in channelNames) {
        FLTCommunityJavaScriptChannel* _channel =
        [[FLTCommunityJavaScriptChannel alloc] initWithMethodChannel: channel
                                      javaScriptChannelName:channelName];
        [userContentController addScriptMessageHandler:_channel name:channelName];
        NSString* wrapperSource = [NSString
                                   stringWithFormat:@"window.%@ = webkit.messageHandlers.%@;", channelName, channelName];
        WKUserScript* wrapperScript =
        [[WKUserScript alloc] initWithSource:wrapperSource
                               injectionTime:WKUserScriptInjectionTimeAtDocumentStart
                            forMainFrameOnly:NO];
        [userContentController addUserScript:wrapperScript];
    }
}

#pragma mark -- UIScrollViewDelegate
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView.pinchGestureRecognizer.isEnabled != _enableZoom) {
        scrollView.pinchGestureRecognizer.enabled = _enableZoom;
    }
}

#pragma mark -- WKUIDelegate
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler
{
    [channel invokeMethod:@"onJsAlert" arguments:@{@"url": webView.URL.absoluteString, @"message": message} result:^(id  _Nullable result) {
        completionHandler();
    }];
}

- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(BOOL result))completionHandler
{
    [channel invokeMethod:@"onJsConfirm" arguments:@{@"url": webView.URL.absoluteString, @"message": message} result:^(id  _Nullable result) {
        NSNumber* b = result;
        completionHandler([b boolValue]);
    }];
}

- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(NSString *result))completionHandler
{
    [channel invokeMethod:@"onJsPrompt" arguments:@{@"url": webView.URL.absoluteString, @"message": prompt, @"defaultText": defaultText} result:^(id  _Nullable result) {
        NSString *str = result;
        completionHandler(str);
    }];
}

@end
