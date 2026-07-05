// Private CoreGraphics (CGS/SkyLight) declarations for display mode control.
// The WindowServer keeps HiDPI variants of each resolution in its internal
// mode list; these are hidden from the public CGDisplayCopyAllDisplayModes
// API but reachable through CGSGetDisplayModeDescriptionOfLength and
// switchable with CGSConfigureDisplayMode. BetterDisplay uses the same calls.

#ifndef CGS_PRIVATE_H
#define CGS_PRIVATE_H

#include <CoreGraphics/CoreGraphics.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint32_t modeNumber;
    uint32_t flags;
    uint32_t width;   // logical (points)
    uint32_t height;  // logical (points)
    uint32_t depth;
    uint32_t reserved1[42];
    uint16_t reserved2;
    uint16_t freq;    // refresh rate in Hz
    uint32_t reserved3[4];
    float density;    // 1.0 = LoDPI, 2.0 = HiDPI (Retina)
} CGSDisplayModeDescription;

void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *count);
void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int idx,
                                          CGSDisplayModeDescription *mode, int length);
void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int *modeNum);
CGError CGSConfigureDisplayMode(CGDisplayConfigRef config,
                                CGDirectDisplayID display, int modeNum);

#ifdef __cplusplus
}
#endif

#endif
