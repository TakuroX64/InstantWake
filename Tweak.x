#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>
#import <notify.h>

@interface CSCoverSheetViewController : UIViewController
@end

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventOptionBits;

static BOOL isCoverSheetVisible = NO;

static void injectHIDButton(uint32_t page, uint32_t usage) {
    typedef IOHIDEventSystemClientRef (*CreateWithTypeFn)(CFAllocatorRef, uint32_t, CFDictionaryRef);
    typedef IOHIDEventRef (*KeyEventFn)(CFAllocatorRef, uint64_t, uint32_t, uint32_t, bool, IOHIDEventOptionBits);
    typedef void (*DispatchFn)(IOHIDEventSystemClientRef, IOHIDEventRef);
    
    static CreateWithTypeFn _createWithType = NULL;
    static KeyEventFn _keyEvent = NULL;
    static DispatchFn _dispatch = NULL;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        void *handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
        if (handle) {
            _createWithType = (CreateWithTypeFn)dlsym(handle, "IOHIDEventSystemClientCreateWithType");
            _keyEvent = (KeyEventFn)dlsym(handle, "IOHIDEventCreateKeyboardEvent");
            _dispatch = (DispatchFn)dlsym(handle, "IOHIDEventSystemClientDispatchEvent");
        }
    });
    
    if (!_createWithType || !_keyEvent || !_dispatch) return;
    
    IOHIDEventSystemClientRef client = _createWithType(kCFAllocatorDefault, 2, NULL);
    if (!client) return;
    
    IOHIDEventRef down = _keyEvent(kCFAllocatorDefault, mach_absolute_time(), page, usage, true, 0);
    if (down) { _dispatch(client, down); CFRelease(down); }
    
    // REDUCED: Was 50000 (50ms), now 2000 (2ms) for an instant click
    usleep(2000);
    
    IOHIDEventRef up = _keyEvent(kCFAllocatorDefault, mach_absolute_time(), page, usage, false, 0);
    if (up) { _dispatch(client, up); CFRelease(up); }
    
    CFRelease(client);
}

static void wakeUnlock(void) {
    injectHIDButton(0x0C, 0x40); 
}

%hook CSCoverSheetViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    isCoverSheetVisible = YES;
    self.view.window.layer.speed = 1.0; 
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    // Targets the master SpringBoard window physics, boosting transition speed by 10x
    self.view.window.layer.speed = 10.0; 
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    isCoverSheetVisible = NO;
    // Instantly returns the OS to normal speed once unlocked
    self.view.window.layer.speed = 1.0;
}

%end

%ctor {
    static int token;
    notify_register_dispatch("com.apple.springboard.hasBlankedScreen", &token, dispatch_get_main_queue(), ^(int t) {
        uint64_t state = 0;
        notify_get_state(t, &state);
        
        if (state == 0 && isCoverSheetVisible) {
            // REDUCED: Was 0.15s, now 0.02s for near-zero latency
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.02 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                wakeUnlock();
            });
        }
    });
}
