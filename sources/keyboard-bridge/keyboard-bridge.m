#import "keyboard-bridge.h"
#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDLib.h>
#import <IOKit/hidsystem/IOHIDParameter.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <IOKit/hidsystem/IOHIDServiceClient.h>

static const uint32_t genericDesktopUsagePage = 1;
static const uint32_t keyboardUsage = 6;
static CFStringRef const mappingProperty = CFSTR("UserKeyMapping");

CFArrayRef CKCopyKeyboards(void) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!client) return NULL;
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) { CFRelease(client); return NULL; }
    NSMutableArray *keyboards = [NSMutableArray array];
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        if (!IOHIDServiceClientConformsTo(service, genericDesktopUsagePage, keyboardUsage)) continue;
        id mapping = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, mappingProperty));
        id product = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        [keyboards addObject:@{
            @"id": (__bridge id)IOHIDServiceClientGetRegistryID(service),
            @"product": product ?: @"Keyboard",
            @"mapping": mapping ?: @[]
        }];
    }
    CFRelease(services);
    CFRelease(client);
    return CFBridgingRetain(keyboards);
}

bool CKSetMapping(uint64_t registryId, CFArrayRef mapping) {
    IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault);
    if (!client) return false;
    CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
    if (!services) { CFRelease(client); return false; }
    bool result = false;
    for (CFIndex index = 0; index < CFArrayGetCount(services); index++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, index);
        NSNumber *serviceId = (__bridge NSNumber *)IOHIDServiceClientGetRegistryID(service);
        if (serviceId.unsignedLongLongValue != registryId) continue;
        result = IOHIDServiceClientSetProperty(service, mappingProperty, mapping);
        break;
    }
    CFRelease(services);
    CFRelease(client);
    return result;
}

int32_t CKSetCapsLock(bool enabled) {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"));
    if (!service) return kIOReturnNoDevice;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), kIOHIDParamConnectType, &connection);
    IOObjectRelease(service);
    if (result != KERN_SUCCESS) return result;
    result = IOHIDSetModifierLockState(connection, kIOHIDCapsLockState, enabled);
    IOServiceClose(connection);
    return result;
}
