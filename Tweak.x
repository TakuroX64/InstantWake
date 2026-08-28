#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <unistd.h>

typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef uint32_t IOHIDEventOptionBits;

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
    
    usleep(50000);
    
    IOHIDEventRef up = _keyEvent(kCFAllocatorDefault, mach_absolute_time(), page, usage, false, 0);
    if (up) { _dispatch(client, up); CFRelease(up); }
    
    CFRelease(client);
}

static void wakeUnlock(void) {
    injectHIDButton(0x0C, 0x40); // Synthesize Home Button
}

%hook CSCoverSheetViewController

// This method tells us exactly when the OLED panel changes power states
- (void)setInScreenOffMode:(BOOL)off {
    %orig;
    
    // If 'off' is NO (false), the screen is waking up from sleep.
    if (!off) {
        // Add a tiny 0.15-second delay to let the screen fully power on before injecting the unlock
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            wakeUnlock();
        });
    }
}

%end
