#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/hid/IOHIDManager.h>
#import <IOKit/hid/IOHIDKeys.h>
#import <dlfcn.h>

// These APIs are the IOHIDEventSystemClient/IOHIDServiceClient route documented
// in Apple's TN2450. Resolve them at runtime so the app fails gracefully if
// a future macOS removes or restricts them.
// Returns number of successfully updated keyboard services, or a negative code:
// -1 unavailable API; -2 no matching keyboard; -3 one or more writes failed;
// -4 invalid JSON; -5 no matching IOHIDDevice; -6 device property rejected.
int BKApplyHIDMappings(const char *json, int internalOnly) {
    if (!json) return -4;
    NSData *bytes = [[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *payload = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:nil];
    NSArray *mappings = payload[@"UserKeyMapping"];
    if (![mappings isKindOfClass:[NSArray class]]) return -4;

    // IOHIDServiceClientSetProperty can return success while only updating
    // service metadata. Apply to the actual keyboard device first, and keep
    // this separate from event-system service writes for diagnostics.
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (manager) {
        IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)@{
            [NSString stringWithUTF8String:kIOHIDDeviceUsagePageKey]: @1,
            [NSString stringWithUTF8String:kIOHIDDeviceUsageKey]: @6
        });
        IOReturn opened = IOHIDManagerOpen(manager, kIOHIDOptionsTypeNone);
        CFSetRef deviceSet = opened == kIOReturnSuccess ? IOHIDManagerCopyDevices(manager) : NULL;
        if (deviceSet) {
            int matched = 0, applied = 0;
            for (id device in (__bridge NSSet *)deviceSet) {
                IOHIDDeviceRef hidDevice = (__bridge IOHIDDeviceRef)device;
                if (internalOnly) {
                    id builtin = (__bridge id)IOHIDDeviceGetProperty(hidDevice, CFSTR("Built-In"));
                    id transport = (__bridge id)IOHIDDeviceGetProperty(hidDevice, CFSTR("Transport"));
                    if (![builtin respondsToSelector:@selector(boolValue)] || ![builtin boolValue] ||
                        ![transport isKindOfClass:[NSString class]] || ![transport isEqualToString:@"FIFO"]) continue;
                }
                matched++;
                if (IOHIDDeviceSetProperty(hidDevice, CFSTR("UserKeyMapping"), (__bridge CFTypeRef)mappings)) applied++;
            }
            CFRelease(deviceSet);
            IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
            CFRelease(manager);
            if (!matched) return -5;
            if (matched != applied) return -6;
            return applied;
        }
        IOHIDManagerClose(manager, kIOHIDOptionsTypeNone);
        CFRelease(manager);
    }

    void *(*createClient)(CFAllocatorRef) = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreateSimpleClient");
    CFArrayRef (*copyServices)(void *) = dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCopyServices");
    Boolean (*conforms)(void *, uint32_t, uint32_t) = dlsym(RTLD_DEFAULT, "IOHIDServiceClientConformsTo");
    CFTypeRef (*copyProperty)(void *, CFStringRef) = dlsym(RTLD_DEFAULT, "IOHIDServiceClientCopyProperty");
    Boolean (*setProperty)(void *, CFStringRef, CFTypeRef) = dlsym(RTLD_DEFAULT, "IOHIDServiceClientSetProperty");
    if (!createClient || !copyServices || !conforms || !copyProperty || !setProperty) return -1;

    void *client = createClient(kCFAllocatorDefault);
    if (!client) return -1;
    CFArrayRef services = copyServices(client);
    if (!services) { CFRelease(client); return -2; }

    int matched = 0;
    int applied = 0;
    for (id service in (__bridge NSArray *)services) {
        void *handle = (__bridge void *)service;
        if (!conforms(handle, 1, 6)) continue;
        if (internalOnly) {
            id builtin = CFBridgingRelease(copyProperty(handle, CFSTR("Built-In")));
            id transport = CFBridgingRelease(copyProperty(handle, CFSTR("Transport")));
            if (![builtin respondsToSelector:@selector(boolValue)] || ![builtin boolValue] ||
                ![transport isKindOfClass:[NSString class]] || ![transport isEqualToString:@"FIFO"]) continue;
        }
        matched++;
        if (setProperty(handle, CFSTR("UserKeyMapping"), (__bridge CFTypeRef)mappings)) applied++;
    }
    CFRelease(services);
    CFRelease(client);
    if (!matched) return -2;
    if (matched != applied) return -3;
    return applied;
}
