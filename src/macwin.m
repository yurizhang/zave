// Minimal native macOS window hosting a WKWebView.
// Uses only system frameworks (Cocoa + WebKit) — no third-party deps.
// Exposes one C entry point, openWebview(url, title, childPid), called from Zig.
// The HTTP server runs in a separate child process; we kill it on quit.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <signal.h>

static int g_child_pid = 0;

@interface WFDelegate : NSObject <NSApplicationDelegate, WKUIDelegate>
@end

@implementation WFDelegate
// Quit the process when the window is closed.
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
// Tear down the server child process before exiting.
- (void)applicationWillTerminate:(NSNotification *)note {
    if (g_child_pid > 0) kill(g_child_pid, SIGTERM);
}

// WKWebView ignores JS dialogs unless these WKUIDelegate methods are provided.
// Without them, window.prompt()/confirm()/alert() silently do nothing — which
// breaks New folder / Rename / Delete in the app.
- (void)webView:(WKWebView *)webView
        runJavaScriptAlertPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"window-finder";
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"OK"];
    [a runModal];
    completionHandler();
}

- (void)webView:(WKWebView *)webView
        runJavaScriptConfirmPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(BOOL))completionHandler {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"window-finder";
    a.informativeText = message ?: @"";
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    completionHandler([a runModal] == NSAlertFirstButtonReturn);
}

- (void)webView:(WKWebView *)webView
        runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt
        defaultText:(NSString *)defaultText
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(NSString *))completionHandler {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = prompt ?: @"";
    [a addButtonWithTitle:@"OK"];
    [a addButtonWithTitle:@"Cancel"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 280, 24)];
    input.stringValue = defaultText ?: @"";
    a.accessoryView = input;
    [a.window setInitialFirstResponder:input];
    if ([a runModal] == NSAlertFirstButtonReturn) {
        completionHandler(input.stringValue);
    } else {
        completionHandler(nil);
    }
}

// target="_blank" links: open in the user's default browser (WKWebView would
// otherwise ignore them).
- (WKWebView *)webView:(WKWebView *)webView
        createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration
        forNavigationAction:(WKNavigationAction *)navigationAction
        windowFeatures:(WKWindowFeatures *)windowFeatures {
    NSURL *url = navigationAction.request.URL;
    if (url) [[NSWorkspace sharedWorkspace] openURL:url];
    return nil;
}
@end

void openWebview(const char *url, const char *title, int childPid) {
    g_child_pid = childPid;
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        WFDelegate *delegate = [[WFDelegate alloc] init];
        [NSApp setDelegate:delegate];

        NSRect frame = NSMakeRect(0, 0, 1200, 760);
        NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                           NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                       styleMask:style
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
        [window setTitle:[NSString stringWithUTF8String:title]];
        [window setMinSize:NSMakeSize(720, 480)];
        [window center];

        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
        WKWebView *webview = [[WKWebView alloc] initWithFrame:frame configuration:config];
        [webview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [webview setUIDelegate:delegate]; // enable JS alert/confirm/prompt dialogs
        [window setContentView:webview];

        NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
        [webview loadRequest:[NSURLRequest requestWithURL:nsurl]];

        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run]; // blocks until the app terminates
    }
}
