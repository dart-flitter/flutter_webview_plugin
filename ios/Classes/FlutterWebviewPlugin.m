#import "FlutterWebviewPlugin.h"

static NSString *const CHANNEL_NAME = @"flutter_webview_plugin";
static NSString *const EVENT_CHANNEL_NAME = @"flutter_webview_plugin_event";

// UIWebViewDelegate
@interface FlutterWebviewPlugin() <UIWebViewDelegate, FlutterStreamHandler> {
    FlutterEventSink _eventSink;
    BOOL _enableAppScheme;
}
@end

@implementation FlutterWebviewPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    channel = [FlutterMethodChannel
               methodChannelWithName:CHANNEL_NAME
               binaryMessenger:[registrar messenger]];
    
    UIViewController *viewController = (UIViewController *)registrar.messenger;
    FlutterWebviewPlugin* instance = [[FlutterWebviewPlugin alloc] initWithViewController:viewController];
    
    [registrar addMethodCallDelegate:instance channel:channel];
    
    FlutterEventChannel* event =
    [FlutterEventChannel eventChannelWithName:EVENT_CHANNEL_NAME
                              binaryMessenger:[registrar messenger]];
    [event setStreamHandler:instance];
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
            [self initWebView:call];
        else
            [self launch:call];
        result(nil);
    } else if ([@"close" isEqualToString:call.method]) {
        [self closeWebView];
        result(nil);
    } else if ([@"eval" isEqualToString:call.method]) {
        result([self evalJavascript:call]);
    } else {
        result(FlutterMethodNotImplemented);
    }
}

- (void)initWebView:(FlutterMethodCall*)call {
    // NSNumber *withJavascript = call.arguments[@"withJavascript"];
    NSNumber *clearCache = call.arguments[@"clearCache"];
    NSNumber *clearCookies = call.arguments[@"clearCookies"];
    NSNumber *hidden = call.arguments[@"hidden"];
    NSDictionary *rect = call.arguments[@"rect"];
    _enableAppScheme = call.arguments[@"enableAppScheme"];
    NSString *userAgent = call.arguments[@"userAgent"];
    
    //
    if ([clearCache boolValue]) {
        [[NSURLCache sharedURLCache] removeAllCachedResponses];
    }
    
    if ([clearCookies boolValue]) {
        [[NSURLSession sharedSession] resetWithCompletionHandler:^{
        }];
    }
    
    CGRect rc;
    if (rect) {
        rc = CGRectMake([[rect valueForKey:@"left"] doubleValue],
                               [[rect valueForKey:@"top"] doubleValue],
                               [[rect valueForKey:@"width"] doubleValue],
                               [[rect valueForKey:@"height"] doubleValue]);
    } else {
        rc = self.viewController.view.bounds;
    }
    
    if (userAgent) {
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent": userAgent}];
    }
    
    self.webview = [[UIWebView alloc] initWithFrame:rc];
    self.webview.delegate = self;
    
    if (!hidden || ![hidden boolValue])
        [self.viewController.view addSubview:self.webview];
    
    [self launch:call];
}

- (void)launch:(FlutterMethodCall*)call {
    NSString *url = call.arguments[@"url"];
    
    NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    [self.webview loadRequest:request];
}

- (NSString *)evalJavascript:(FlutterMethodCall*)call {
    NSString *code = call.arguments[@"code"];
    
    NSString *result = [self.webview stringByEvaluatingJavaScriptFromString:code];
    return result;
}

- (void)closeWebView {
    [self.webview stopLoading];
    [self.webview removeFromSuperview];
    self.webview.delegate = nil;
    self.webview = nil;
    [self sendEvent:@"destroy"];
}


#pragma mark -- WebView Delegate
- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    NSArray *data = [NSArray arrayWithObjects:@"shouldStart",
                     request.URL.absoluteString, [NSNumber numberWithInt:navigationType],
                     nil];
    [self sendEvent:data];
    
    if (_enableAppScheme)
        return YES;

    // disable some scheme
    return [request.URL.scheme isEqualToString:@"http"] ||
            [request.URL.scheme isEqualToString:@"https"] ||
            [request.URL.scheme isEqualToString:@"about"];
}

-(void)webViewDidStartLoad:(UIWebView *)webView {
    [self sendEvent:@"startLoad"];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView {
    [self sendEvent:@"finishLoad"];
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error {
    id data = [FlutterError errorWithCode:[NSString stringWithFormat:@"%ld", error.code]
                                  message:error.localizedDescription
                                  details:error.localizedFailureReason];
    [self sendEvent:data];
}

#pragma mark -- WkWebView Delegate

#pragma mark -- FlutterStreamHandler impl

- (FlutterError*)onListenWithArguments:(id)arguments eventSink:(FlutterEventSink)eventSink {
    _eventSink = eventSink;
    return nil;
}

- (FlutterError*)onCancelWithArguments:(id)arguments {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _eventSink = nil;
    return nil;
}

- (void)sendEvent:(id)data {
    // data should be @"" or [FlutterError]
    if (!_eventSink)
        return;
    
    _eventSink(data);
}
@end
