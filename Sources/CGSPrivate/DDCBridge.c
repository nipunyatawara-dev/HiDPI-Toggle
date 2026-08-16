#include "include/CGSPrivate.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <unistd.h>

typedef CFTypeRef IOAVServiceRef;

// Private IOKit exports used by the Apple-silicon display controller.
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator,
                                                   io_service_t service);
extern IOReturn IOAVServiceCopyEDID(IOAVServiceRef service, CFDataRef *edid);
extern IOReturn IOAVServiceReadI2C(IOAVServiceRef service,
                                  uint32_t chipAddress,
                                  uint32_t dataAddress,
                                  void *buffer,
                                  uint32_t bufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service,
                                   uint32_t chipAddress,
                                   uint32_t dataAddress,
                                   void *buffer,
                                   uint32_t bufferSize);

static const uint32_t ddcChipAddress = 0x37;
static const uint32_t ddcDataAddress = 0x51;
static const uint8_t brightnessVCPCode = 0x10;
static pthread_mutex_t ddcLock = PTHREAD_MUTEX_INITIALIZER;

static bool locationIsExternal(io_service_t service) {
    CFTypeRef value = IORegistryEntryCreateCFProperty(
        service, CFSTR("Location"), kCFAllocatorDefault, 0
    );
    if (value == NULL) {
        return false;
    }

    bool matches = CFGetTypeID(value) == CFStringGetTypeID()
        && CFStringCompare((CFStringRef)value, CFSTR("External"), 0) == kCFCompareEqualTo;
    CFRelease(value);
    return matches;
}

static bool edidMatchesDisplay(CFDataRef edid,
                               CGDirectDisplayID display,
                               bool *exactSerialMatch) {
    if (edid == NULL || CFDataGetLength(edid) < 16) {
        return false;
    }

    const UInt8 *bytes = CFDataGetBytePtr(edid);
    uint32_t vendor = ((uint32_t)bytes[8] << 8) | bytes[9];
    uint32_t product = (uint32_t)bytes[10] | ((uint32_t)bytes[11] << 8);
    uint32_t serial = (uint32_t)bytes[12]
        | ((uint32_t)bytes[13] << 8)
        | ((uint32_t)bytes[14] << 16)
        | ((uint32_t)bytes[15] << 24);

    if (vendor != CGDisplayVendorNumber(display)
        || product != CGDisplayModelNumber(display)) {
        return false;
    }

    uint32_t displaySerial = CGDisplaySerialNumber(display);
    *exactSerialMatch = serial != 0 && displaySerial != 0 && serial == displaySerial;
    return serial == 0 || displaySerial == 0 || *exactSerialMatch;
}

static uint32_t onlineExternalDisplayCount(void) {
    CGDirectDisplayID displays[16] = {0};
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(16, displays, &count) != kCGErrorSuccess) {
        return 0;
    }

    uint32_t externalCount = 0;
    for (uint32_t index = 0; index < count; index++) {
        if (!CGDisplayIsBuiltin(displays[index])) {
            externalCount++;
        }
    }
    return externalCount;
}

// Returned service follows the Create rule and must be released by the caller.
static IOAVServiceRef copyAVServiceForDisplay(CGDirectDisplayID display) {
    io_iterator_t iterator = IO_OBJECT_NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("DCPAVServiceProxy");
    if (matching == NULL
        || IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) != KERN_SUCCESS) {
        return NULL;
    }

    IOAVServiceRef exactService = NULL;
    IOAVServiceRef candidateService = NULL;
    IOAVServiceRef onlyService = NULL;
    uint32_t externalServiceCount = 0;
    uint32_t candidateCount = 0;

    io_service_t registryService;
    while ((registryService = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        if (!locationIsExternal(registryService)) {
            IOObjectRelease(registryService);
            continue;
        }

        IOAVServiceRef avService = IOAVServiceCreateWithService(
            kCFAllocatorDefault, registryService
        );
        IOObjectRelease(registryService);
        if (avService == NULL) {
            continue;
        }

        externalServiceCount++;
        if (onlyService == NULL) {
            onlyService = avService;
            CFRetain(onlyService);
        }

        CFDataRef edid = NULL;
        bool exactSerialMatch = false;
        if (IOAVServiceCopyEDID(avService, &edid) == KERN_SUCCESS
            && edidMatchesDisplay(edid, display, &exactSerialMatch)) {
            if (exactSerialMatch) {
                exactService = avService;
            } else {
                candidateCount++;
                if (candidateService == NULL) {
                    candidateService = avService;
                    CFRetain(candidateService);
                }
            }
        }
        if (edid != NULL) {
            CFRelease(edid);
        }

        if (exactService != NULL) {
            break;
        }
        CFRelease(avService);
    }

    IOObjectRelease(iterator);

    if (exactService != NULL) {
        if (onlyService != NULL) {
            CFRelease(onlyService);
        }
        if (candidateService != NULL) {
            CFRelease(candidateService);
        }
        return exactService;
    }

    if (candidateCount == 1) {
        if (onlyService != NULL) {
            CFRelease(onlyService);
        }
        return candidateService;
    }

    if (externalServiceCount == 1 && onlineExternalDisplayCount() == 1) {
        if (candidateService != NULL) {
            CFRelease(candidateService);
        }
        return onlyService;
    }

    if (candidateService != NULL) {
        CFRelease(candidateService);
    }
    if (onlyService != NULL) {
        CFRelease(onlyService);
    }
    return NULL;
}

static uint8_t checksum(uint8_t seed, const uint8_t *bytes, size_t count) {
    uint8_t result = seed;
    for (size_t index = 0; index < count; index++) {
        result ^= bytes[index];
    }
    return result;
}

static bool readBrightness(IOAVServiceRef service,
                           uint16_t *currentValue,
                           uint16_t *maximumValue) {
    for (int attempt = 0; attempt < 4; attempt++) {
        uint8_t request[] = {0x82, 0x01, brightnessVCPCode, 0x00};
        request[3] = checksum(0x6E, request, 3);

        bool wrote = false;
        for (int cycle = 0; cycle < 2; cycle++) {
            usleep(10000);
            wrote = IOAVServiceWriteI2C(
                service, ddcChipAddress, ddcDataAddress,
                request, (uint32_t)sizeof(request)
            ) == KERN_SUCCESS || wrote;
        }
        if (!wrote) {
            usleep(20000);
            continue;
        }

        usleep(50000);
        uint8_t reply[11] = {0};
        IOReturn result = IOAVServiceReadI2C(
            service, ddcChipAddress, ddcDataAddress,
            reply, (uint32_t)sizeof(reply)
        );
        bool validReply = result == KERN_SUCCESS
            && checksum(0x50, reply, sizeof(reply) - 1) == reply[sizeof(reply) - 1]
            && reply[2] == 0x02
            && reply[3] == 0x00
            && reply[4] == brightnessVCPCode;
        if (validReply) {
            uint16_t maximum = ((uint16_t)reply[6] << 8) | reply[7];
            uint16_t current = ((uint16_t)reply[8] << 8) | reply[9];
            if (maximum > 0) {
                *maximumValue = maximum;
                *currentValue = current > maximum ? maximum : current;
                return true;
            }
        }
        usleep(20000);
    }
    return false;
}

int32_t HDTDDCProbeBrightness(CGDirectDisplayID display,
                              uint16_t *currentValue,
                              uint16_t *maximumValue) {
    if (currentValue == NULL || maximumValue == NULL) {
        return 0;
    }

    pthread_mutex_lock(&ddcLock);
    IOAVServiceRef service = copyAVServiceForDisplay(display);
    if (service == NULL) {
        pthread_mutex_unlock(&ddcLock);
        return 0;
    }

    bool readable = readBrightness(service, currentValue, maximumValue);
    CFRelease(service);
    pthread_mutex_unlock(&ddcLock);
    return readable ? 2 : 1;
}

bool HDTDDCWriteBrightness(CGDirectDisplayID display, uint16_t value) {
    pthread_mutex_lock(&ddcLock);
    IOAVServiceRef service = copyAVServiceForDisplay(display);
    if (service == NULL) {
        pthread_mutex_unlock(&ddcLock);
        return false;
    }

    uint8_t request[] = {
        0x84, 0x03, brightnessVCPCode,
        (uint8_t)(value >> 8), (uint8_t)(value & 0xFF), 0x00
    };
    request[5] = checksum(0x6E ^ 0x51, request, 5);

    bool wrote = false;
    for (int cycle = 0; cycle < 2; cycle++) {
        usleep(10000);
        wrote = IOAVServiceWriteI2C(
            service, ddcChipAddress, ddcDataAddress,
            request, (uint32_t)sizeof(request)
        ) == KERN_SUCCESS || wrote;
    }

    CFRelease(service);
    pthread_mutex_unlock(&ddcLock);
    return wrote;
}
