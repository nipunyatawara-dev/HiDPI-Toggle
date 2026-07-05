// Test: switch the external display between the density-1.0 and density-2.0
// variants of its current resolution using CGSConfigureDisplayMode.
// Usage: toggle_test on|off

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct {
    uint32_t modeNumber;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint32_t dc2[42];
    uint16_t dc3;
    uint16_t freq;
    uint32_t dc4[4];
    float density;
} CGSDisplayModeDescription;

extern void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *count);
extern void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int idx, CGSDisplayModeDescription *mode, int length);
extern void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int *modeNum);
extern CGError CGSConfigureDisplayMode(CGDisplayConfigRef config, CGDirectDisplayID display, int modeNum);

int main(int argc, char *argv[]) {
    BOOL wantHiDPI = (argc > 1 && strcmp(argv[1], "on") == 0);

    CGDirectDisplayID ids[16];
    uint32_t count = 0;
    CGGetOnlineDisplayList(16, ids, &count);

    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID d = ids[i];
        if (CGDisplayIsBuiltin(d)) continue;

        int modeCount = 0, currentIdx = -1;
        CGSGetNumberOfDisplayModes(d, &modeCount);
        CGSGetCurrentDisplayMode(d, &currentIdx);

        CGSDisplayModeDescription current;
        memset(&current, 0, sizeof(current));
        CGSGetDisplayModeDescriptionOfLength(d, currentIdx, &current, sizeof(current));
        printf("display %u current: %ux%u @%uHz density=%.1f\n",
               d, current.width, current.height, current.freq, current.density);

        float targetDensity = wantHiDPI ? 2.0f : 1.0f;
        if (current.density == targetDensity) {
            printf("already at target density\n");
            continue;
        }

        int target = -1;
        for (int m = 0; m < modeCount; m++) {
            CGSDisplayModeDescription mode;
            memset(&mode, 0, sizeof(mode));
            CGSGetDisplayModeDescriptionOfLength(d, m, &mode, sizeof(mode));
            // Skip safe-mode/stub entries (flag 0x40000000).
            if (mode.flags & 0x40000000) continue;
            if (mode.width == current.width && mode.height == current.height &&
                mode.freq == current.freq && mode.density == targetDensity) {
                target = m;
                break;
            }
        }
        if (target < 0) {
            printf("no matching density=%.1f mode found\n", targetDensity);
            continue;
        }

        CGDisplayConfigRef config = NULL;
        if (CGBeginDisplayConfiguration(&config) != kCGErrorSuccess) {
            printf("CGBeginDisplayConfiguration failed\n");
            return 1;
        }
        CGError err = CGSConfigureDisplayMode(config, d, target);
        if (err != kCGErrorSuccess) {
            printf("CGSConfigureDisplayMode failed: %d\n", err);
            CGCancelDisplayConfiguration(config);
            return 1;
        }
        CGCompleteDisplayConfiguration(config, kCGConfigureForSession);
        printf("switched display %u to mode %d (density %.1f)\n", d, target, targetDensity);
    }
    return 0;
}
