#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "ptouch-render.h"

int main(int argc, char **argv)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    (void)[NSApplication sharedApplication];
    /* Ensure the application finishes launching so drawing backends are initialized */
    [NSApp finishLaunching];

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

                /* Also render a two-line sample to inspect vertical spacing */
                char *two_lines[2] = { "First line", "Second line" };
                render_args.font_file = render_args.font_file ? render_args.font_file : "Sans";
                render_args.font_size = render_args.font_size ? render_args.font_size : 24;
                image_t *im2 = render_text(render_args.font_file, two_lines, 2, 76);
                if (im2) {
                    const char *two_out = "/tmp/ptouch-render-test-2lines.png";
                    if (write_png(im2, two_out) == 0) printf("[test] wrote two-line image %s\n", two_out);
                    image_destroy(im2);
                } else {
                    printf("[test] two-line render failed\n");
                }

                image_destroy(im);
                [pool drain];
                return 0;
            }
            image_destroy(im);
        }
    }
    printf("[test] failed: no font/size produced black and white pixels\n");

    /* Additional quick check: try a two-line render to inspect vertical spacing */
    printf("[test] Trying two-line sample for spacing check\n");
    render_args.font_file = "Sans";
    render_args.font_size = 24;
    char *two_lines[2] = { "First line", "Second line" };
    image_t *im2 = render_text(render_args.font_file, two_lines, 2, 76);
    if (im2) {
        size_t white = 0, black = 0;
        for (int y = 0; y < im2->height; ++y) {
            for (int x = 0; x < im2->width; ++x) {
                if (im2->data[y * im2->width + x]) black++; else white++;
            }
        }
        printf("[test] two-line got image %dx%d white=%zu black=%zu\n", im2->width, im2->height, white, black);
        const char *two_out = "/tmp/ptouch-render-test-2lines.png";
        if (write_png(im2, two_out) == 0) printf("[test] wrote two-line image %s\n", two_out);
        image_destroy(im2);
    } else {
        printf("[test] two-line render failed\n");
    }

    [pool drain];
    return 1;
}
