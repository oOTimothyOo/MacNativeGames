// Ultimate 2C Wireless Bluetooth (2dc8:301b), using HID usages rather than
// platform-dependent axis indices. Mapping cross-checked with SDL's macOS DB.
#pragma once
#include <stdint.h>
#include "dm_input.h"

typedef struct { uint32_t buttons; uint64_t hat; int32_t lx, ly, rx, ry; int lt, rt; } hid_8bitdo;

static int32_t hid_8bitdo_axis(long value, long lo, long hi) {
    if (hi <= lo) return 0;
    double range = (double)hi - (double)lo;
    double v = ((double)value - (double)lo) / range * 2.0 - 1.0;
    if (v > 1) v = 1; if (v < -1) v = -1;
    if (v > -0.06 && v < 0.06) return 0;
    return (int32_t)(v * DM_STICK_MAX);
}
static void hid_8bitdo_value(hid_8bitdo *s, unsigned page, unsigned usage, long value, long lo, long hi) {
    if (page == 9 && usage >= 1 && usage <= 16) {
        uint32_t bit = 1u << (usage - 1);
        s->buttons = value ? s->buttons | bit : s->buttons & ~bit;
    } else if (page == 1 && usage == 0x39) {
        static const uint64_t hats[] = {DM_BTN_UP, DM_BTN_UP | DM_BTN_RIGHT, DM_BTN_RIGHT,
            DM_BTN_RIGHT | DM_BTN_DOWN, DM_BTN_DOWN, DM_BTN_DOWN | DM_BTN_LEFT,
            DM_BTN_LEFT, DM_BTN_LEFT | DM_BTN_UP};
        s->hat = value >= 0 && value < 8 ? hats[value] : 0; // 8 is the descriptor's null state.
    } else if (page == 1) {
        int32_t v = hid_8bitdo_axis(value, lo, hi);
        switch (usage) {
            case 0x30: s->lx = v; break; case 0x31: s->ly = -v; break;
            case 0x32: s->rx = v; break; case 0x35: s->ry = -v; break;
        }
    } else if (page == 2 && hi > lo) {
        int pressed = (double)value > ((double)lo + (double)hi) * 0.5;
        if (usage == 0xc5) s->lt = pressed;
        if (usage == 0xc4) s->rt = pressed;
    }
}
static uint64_t hid_8bitdo_buttons(const hid_8bitdo *s, int labels, int swap_ab) {
    // HID button usages are one-based; 3/6 are the extra L4/R4 buttons.
    static const uint64_t map[16] = {DM_BTN_A, DM_BTN_B, 0, DM_BTN_X, DM_BTN_Y, 0,
        DM_BTN_L, DM_BTN_R, DM_BTN_ZL, DM_BTN_ZR, DM_BTN_MINUS, DM_BTN_PLUS, 0, DM_BTN_LS, DM_BTN_RS, 0};
    uint64_t m = s->hat;
    for (unsigned i = 0; i < 16; i++) if (s->buttons & (1u << i)) m |= map[i];
    if (s->lt) m |= DM_BTN_ZL; if (s->rt) m |= DM_BTN_ZR;
    if (labels) { // Same settings convention as the GameController backend.
        uint64_t face = m & 15u;
        m = (m & ~15ull) | ((face & 5u) << 1) | ((face & 10u) >> 1);
    }
    if (swap_ab) { uint64_t ab = m & 3u; m = (m & ~3ull) | ((ab & 1u) << 1) | ((ab & 2u) >> 1); }
    return m;
}
