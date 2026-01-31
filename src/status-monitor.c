#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "ptouch.h"

static void print_hex(const uint8_t *buf, size_t n)
{
    for (size_t i = 0; i < n; ++i) printf("%02x ", buf[i]);
}

static void print_diff(const uint8_t *old, const uint8_t *cur, size_t n)
{
    int first = 1;
    for (size_t i = 0; i < n; ++i) {
        if (old[i] != cur[i]) {
            if (first) { printf(" changed bytes: "); first = 0; }
            printf("[%zu]=%02x->%02x ", i, old[i], cur[i]);
        }
    }
    if (!first) printf("\n");
}

int main(int argc, char **argv)
{
    ptouch_dev ptdev = NULL;
    if (ptouch_open(&ptdev) < 0) {
        fprintf(stderr, "status-monitor: failed to open printer\n");
        return 1;
    }
    if (ptouch_init(ptdev) != 0) {
        fprintf(stderr, "status-monitor: init failed (continuing)\n");
    }

    uint8_t prev[32] = {0};
    int first = 1;
    printf("status-monitor: connected to printer. Press Ctrl-C to exit.\n");

    while (1) {
        if (ptouch_getstatus(ptdev, 1) == 0) {
            struct _ptouch_dev *d = ptdev;
            uint8_t *s = (uint8_t *)d->status;
            struct timespec ts;
            clock_gettime(CLOCK_REALTIME, &ts);
            char tbuf[64];
            time_t sec = ts.tv_sec;
            struct tm tm;
            localtime_r(&sec, &tm);
            strftime(tbuf, sizeof(tbuf), "%Y-%m-%d %H:%M:%S", &tm);
            printf("%s.%03ld status: ", tbuf, ts.tv_nsec/1000000);
            print_hex(s, 32);
            printf("\n");

            if (!first) {
                print_diff(prev, s, 32);
            } else {
                first = 0;
            }

            /* Mirror known useful fields */
            if (s[0] == 0x80 && s[1] == 0x20) {
                printf("  -> tape width mm: %d (tape px mapping may change)\n", s[10]);
                printf("  -> door_open=%d door_moving=%d\n", d->door_open, d->door_moving);
            }

            /* Door event detection (set by ptouch_update_derived_status called by ptouch_getstatus) */
            static int prev_door_open = -1;
            if (prev_door_open == -1) prev_door_open = d->door_open;
            if (d->door_open != prev_door_open) {
                if (d->door_open) {
                    printf("  -> Door opened\n");
                } else {
                    printf("  -> Door closed\n");
                    /* Re-query immediately to pick up tape info after close */
                    if (ptouch_getstatus(ptdev, 1) == 0) {
                        printf("  -> re-queried status after door close: tape width = %d mm\n", d->status->media_width);
                    }
                }
                prev_door_open = d->door_open;
            }

            memcpy(prev, s, 32);
        } else {
            fprintf(stderr, "status-monitor: ptouch_getstatus failed\n");
        }
        fflush(stdout);
        usleep(200000); /* 200ms */
    }

    ptouch_close(ptdev);
    return 0;
}
