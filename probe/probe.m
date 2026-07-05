// Read-only probe: dumps the WindowServer's private mode list for every
// online display, including hidden HiDPI variants. Same struct layout that
// displayplacer uses (212-byte mode description).

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
} CGSDisplayModeDescription; // 212 bytes (0xD4)

extern void CGSGetNumberOfDisplayModes(CGDirectDisplayID display, int *count);
extern void CGSGetDisplayModeDescriptionOfLength(CGDirectDisplayID display, int idx, CGSDisplayModeDescription *mode, int length);
extern void CGSGetCurrentDisplayMode(CGDirectDisplayID display, int *modeNum);

int main(void) {
    printf("sizeof mode struct: %lu\n", sizeof(CGSDisplayModeDescription));

    CGDirectDisplayID ids[16];
    uint32_t count = 0;
    CGGetOnlineDisplayList(16, ids, &count);

    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID d = ids[i];
        int modeCount = 0, current = -1;
        CGSGetNumberOfDisplayModes(d, &modeCount);
        CGSGetCurrentDisplayMode(d, &current);
        printf("\nDisplay %u (builtin=%d) current mode=%d, %d modes:\n",
               d, CGDisplayIsBuiltin(d), current, modeCount);
        for (int m = 0; m < modeCount; m++) {
            CGSDisplayModeDescription mode;
            memset(&mode, 0, sizeof(mode));
            CGSGetDisplayModeDescriptionOfLength(d, m, &mode, sizeof(mode));
            printf("  [%3d] num=%3u  %5ux%-5u  %3uHz  density=%.1f  flags=0x%08x%s\n",
                   m, mode.modeNumber, mode.width, mode.height, mode.freq,
                   mode.density, mode.flags,
                   (m == current) ? "   <== CURRENT" : "");
        }
    }
    return 0;
}
