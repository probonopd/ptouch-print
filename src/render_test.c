#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "ptouch-render.h"

#import <AppKit/AppKit.h>

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)[NSApplication sharedApplication];

    const char *fonts[] = {"Sans", "DejaVu Sans", "Helvetica", "Arial", NULL};
    int sizes[] = {0, 12, 24, 36, 48};
    char *text = "RenderTest";
    char *lines[2] = { text, NULL };

    for (int fi = 0; fonts[fi] != NULL; ++fi) {
        render_args.font_file = (char *)fonts[fi];
        for (size_t si = 0; si < sizeof(sizes)/sizeof(sizes[0]); ++si) {
            render_args.font_size = sizes[si];
            printf("[test] Trying font='%s' size=%d\n", render_args.font_file, render_args.font_size);
            image_t *im = render_text(render_args.font_file, lines, 1, 76);
            if (!im) {
                printf("[test] render_text returned NULL\n");
                continue;
            }
            size_t white = 0, black = 0;
            for (int y = 0; y < im->height; ++y) {
                for (int x = 0; x < im->width; ++x) {
                    if (im->data[y * im->width + x]) black++; else white++;
                }
            }
            printf("[test] got image %dx%d white=%zu black=%zu\n", im->width, im->height, white, black);
            if (black > 0 && white > 0) {
                const char *out = "/tmp/ptouch-render-test.png";
                if (write_png(im, out) == 0) {
                    printf("[test] success: wrote %s\n", out);
                } else {
                    printf("[test] success but failed to write PNG\n");
                }
                image_destroy(im);
                [pool drain];
                return 0;
            }
            image_destroy(im);
        }
    }
    printf("[test] failed: no font/size produced black and white pixels\n");
    [pool drain];
    return 1;
}
