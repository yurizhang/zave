// Minimal native macOS window hosting a WKWebView.
// Uses only system frameworks (Cocoa + WebKit) — no third-party deps.
// Exposes one C entry point, openWebview(url, title, childPid), called from Zig.
// The HTTP server runs in a separate child process; we kill it on quit.

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <signal.h>

static int g_child_pid = 0;

@interface WFDelegate : NSObject <NSApplicationDelegate>
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
        [window setContentView:webview];

        NSURL *nsurl = [NSURL URLWithString:[NSString stringWithUTF8String:url]];
        [webview loadRequest:[NSURLRequest requestWithURL:nsurl]];

        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        [NSApp run]; // blocks until the app terminates
    }
}
