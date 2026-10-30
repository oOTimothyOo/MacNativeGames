// Model-specific, read-only HID fallback for pads absent from GameController.
#pragma once
#include "hid_8bitdo.h"
typedef struct {
    void (*connected)(const void *key, const char *name);
    void (*removed)(const void *key);
    void (*input)(const void *key, const hid_8bitdo *state);
} front_hid_callbacks;
void front_hid_start(front_hid_callbacks callbacks);
void front_hid_refresh(void);
int front_hid_count(void);
