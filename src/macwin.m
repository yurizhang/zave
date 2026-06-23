// Minimal native macOS window(s) hosting a WKWebView.
// Uses only system frameworks (Cocoa + WebKit) — no third-party deps.
// Exposes one C entry point, openWebview(url, title, childPid), called from Zig.
// Supports multiple windows (Cmd+N). The HTTP server runs in a separate child
// process; we kill it on quit.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <signal.h>

static int g_child_pid = 0;
static NSString *g_url = nil;
static NSString *g_title = nil;

@interface WFDelegate : NSObject <NSApplicationDelegate, WKUIDelegate>
- (void)newWindow:(id)sender;
@end

static WFDelegate *g_delegate = nil;

// Create and show one window pointing at the local server.
static void makeWindow(void) {
    NSRect frame = NSMakeRect(0, 0, 1200, 760);
    NSUInteger style = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                       NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:style
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:g_title];
    [window setMinSize:NSMakeSize(720, 480)];
    [window center];
    [window cascadeTopLeftFromPoint:NSMakePoint(24, 24)]; // offset extra windows

    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    WKWebView *webview = [[WKWebView alloc] initWithFrame:frame configuration:config];
    [webview setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [webview setUIDelegate:g_delegate];
    [window setContentView:webview];

    NSURL *nsurl = [NSURL URLWithString:g_url];
    [webview loadRequest:[NSURLRequest requestWithURL:nsurl]];

    [window makeKeyAndOrderFront:nil];
}

// Minimal menu bar so Cmd+N (new window), Cmd+W (close), Cmd+Q (quit) work.
// Deliberately no Edit menu: Cmd+X/C/V are the app's file cut/copy/paste
// shortcuts (handled in JS) — an Edit menu would steal them.
static void setupMenu(void) {
    NSMenu *menubar = [[NSMenu alloc] init];
    [NSApp setMainMenu:menubar];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    [menubar addItem:appItem];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Zave" action:@selector(showAbout:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Zave" action:@selector(terminate:) keyEquivalent:@"q"];
    [appItem setSubmenu:appMenu];

    NSMenuItem *fileItem = [[NSMenuItem alloc] init];
    [menubar addItem:fileItem];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New Window" action:@selector(newWindow:) keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileItem setSubmenu:fileMenu];

    NSMenuItem *windowItem = [[NSMenuItem alloc] init];
    [menubar addItem:windowItem];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize" action:@selector(performMiniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom" action:@selector(performZoom:) keyEquivalent:@""];
    [windowItem setSubmenu:windowMenu];
    [NSApp setWindowsMenu:windowMenu];
}

@implementation WFDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    return YES;
}
- (void)applicationWillTerminate:(NSNotification *)note {
    if (g_child_pid > 0) kill(g_child_pid, SIGTERM);
}
- (void)newWindow:(id)sender {
    makeWindow();
}
// Reuse the web UI's About modal (Settings ⚙ → About) from the native menu.
- (void)showAbout:(id)sender {
    NSWindow *win = [NSApp keyWindow] ?: [[NSApp windows] firstObject];
    id view = [win contentView];
    if ([view isKindOfClass:[WKWebView class]]) {
        [(WKWebView *)view evaluateJavaScript:@"window.showAbout&&showAbout()" completionHandler:nil];
    }
}

// WKWebView ignores JS dialogs unless these WKUIDelegate methods exist.
- (void)webView:(WKWebView *)webView
        runJavaScriptAlertPanelWithMessage:(NSString *)message
        initiatedByFrame:(WKFrameInfo *)frame
        completionHandler:(void (^)(void))completionHandler {
    NSAlert *a = [[NSAlert alloc] init];
    a.messageText = @"Zave";
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
    a.messageText = @"Zave";
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

// target="_blank" links open in the user's default browser.
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
        g_url = [NSString stringWithUTF8String:url];
        g_title = [NSString stringWithUTF8String:title];

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

        g_delegate = [[WFDelegate alloc] init];
        [NSApp setDelegate:g_delegate];

        setupMenu();
        makeWindow();

        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run]; // blocks until the app terminates
    }
}
