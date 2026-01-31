#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#include "ptouch-render.h"

static image_t *image_new(int width, int height)
{
    if (width <= 0 || height <= 0) return NULL;
    image_t *im = (image_t *)malloc(sizeof(image_t));
    if (!im) return NULL;
    im->width = width;
    im->height = height;
    im->data = (unsigned char *)malloc((size_t)width * height);
    if (!im->data) { free(im); return NULL; }
    memset(im->data, 0, (size_t)width * height); /* default white (0) */
    return im;
}

void image_destroy(image_t *im)
{
    if (!im) return;
    if (im->data) free(im->data);
    free(im);
}

void image_free(void *ptr)
{
    if (ptr) free(ptr);
}

/* Convert an image_t to PNG data (caller must free) */
void *image_png_ptr(image_t *im, int *size)
{
    if (!im) return NULL;
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                              initWithBitmapDataPlanes:NULL
                              pixelsWide:im->width
                              pixelsHigh:im->height
                              bitsPerSample:8
                              samplesPerPixel:1
                              hasAlpha:NO
                              isPlanar:NO
                              colorSpaceName:NSCalibratedWhiteColorSpace
                              bytesPerRow:im->width
                              bitsPerPixel:8];
    if (!rep) return NULL;

    unsigned char *bitmap = (unsigned char *)[rep bitmapData];
    for (int y = 0; y < im->height; ++y) {
        for (int x = 0; x < im->width; ++x) {
            unsigned char v = im->data[y * im->width + x] ? 0 : 255; /* 0=black,255=white */
            bitmap[y * im->width + x] = v;
        }
    }

    NSData *png = [rep representationUsingType:NSPNGFileType properties:@{}];
    [rep release];
    if (!png) return NULL;
    *size = (int)[png length];
    void *buf = malloc(*size);
    if (!buf) return NULL;
    memcpy(buf, [png bytes], *size);
    return buf;
}

/* Load PNG (or other supported) image and threshold to 0/1 monochrome */
image_t *image_load(const char *file)
{
    if (!file) return NULL;
    NSString *path = [NSString stringWithUTF8String:file];
    NSImage *img = nil;
    if ([path isEqualToString:@"-"]) {
        /* stdin not supported here */
        return NULL;
    } else {
        img = [[NSImage alloc] initWithContentsOfFile:path];
    }
    if (!img) return NULL;
    NSSize ns = [img size];
    int width = (int)ns.width;
    int height = (int)ns.height;
    if (width <= 0 || height <= 0) { [img release]; return NULL; }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
    [img release];
    if (!rep) return NULL;

    int w = (int)[rep pixelsWide];
    int h = (int)[rep pixelsHigh];
    image_t *im = image_new(w, h);
    if (!im) { [rep release]; return NULL; }

    unsigned char *bitmap = (unsigned char *)[rep bitmapData];
    int bpr = (int)[rep bytesPerRow];
    int samples = (int)[rep samplesPerPixel];

    for (int y = 0; y < h; ++y) {
        unsigned char *row = bitmap + y * bpr;
        for (int x = 0; x < w; ++x) {
            int idx = x * samples;
            unsigned char r,g,b;
            if (samples >= 3) {
                r = row[idx]; g = row[idx+1]; b = row[idx+2];
            } else {
                r = g = b = row[idx];
            }
            int lum = r + g + b;
            im->data[y * w + x] = (lum < (255*3/2)) ? 1 : 0; /* 1 = black */
        }
    }
    [rep release];
    return im;
}

int write_png(image_t *im, const char *file)
{
    if (!im || !file) return -1;
    int size = 0;
    void *data = image_png_ptr(im, &size);
    if (!data) return -1;
    FILE *f = fopen(file, "wb");
    if (!f) { image_free(data); return -1; }
    fwrite(data, 1, size, f);
    fclose(f);
    image_free(data);
    return 0;
}

/* Measurement helpers using NSString / NSFont */
static NSFont *nsfont_for(const char *fontname, int fsz)
{
    NSString *fname = fontname ? [NSString stringWithUTF8String:fontname] : nil;
    NSFont *font = nil;
    if (fname) font = [NSFont fontWithName:fname size:fsz];
    if (!font) font = [NSFont systemFontOfSize:fsz];
    return font;
}

int get_baselineoffset(char *text, char *font, int fsz)
{
    @autoreleasepool {
        NSFont *f = nsfont_for(font, fsz);
        /* Use font ascender as baseline reference (rounded up) */
        CGFloat asc = [f ascender];
        int baseline = (int)ceil(asc);
        if (render_args.debug) {
            printf("debug: baseline metrics asc=%.2f baseline=%d\n", asc, baseline);
        }
        return baseline;
    }
} 

int find_fontsize(int want_px, char *font, char *text)
{
    @autoreleasepool {
        if (!text) return -1;
        for (int i = 4; ; ++i) {
            NSFont *f = nsfont_for(font, i);
            /* Prefer font metrics (ascender + |descender| + leading) for consistent line height */
            CGFloat asc = [f ascender];
            CGFloat desc = [f descender];
            CGFloat leading = [f leading];
            int h = (int)ceil(asc - desc + leading);
            if (render_args.debug) printf("[debug] find_fontsize: want_px=%d, try_size=%d, measured_height=%d (asc=%.2f desc=%.2f lead=%.2f)\n", want_px, i, h, asc, desc, leading);
            if (h <= 0) return -1;
            if (h <= want_px) {
                /* keep trying larger sizes until it grows beyond want_px */
            } else {
                int res = i-1 > 0 ? i-1 : -1;
                if (render_args.debug) printf("[debug] find_fontsize: result=%d\n", res);
                return res;
            }
        }
        return -1;
    }
}

int find_fontsize_width(int want_px, char *font, char *text)
{
    @autoreleasepool {
        if (!text) return -1;
        for (int i = 4; ; ++i) {
            int w = needed_width(text, font, i);
            if (w <= 0) return -1;
            if (w <= want_px) {
                /* keep trying */
            } else {
                return i-1 > 0 ? i-1 : -1;
            }
        }
    }
}

int needed_width(char *text, char *font, int fsz)
{
    @autoreleasepool {
        if (!text) return -1;
        NSString *s = [NSString stringWithUTF8String:text];
        NSFont *f = nsfont_for(font, fsz);
        NSDictionary *attr = @{ NSFontAttributeName: f };
        NSSize sz = [s sizeWithAttributes:attr];
        if (render_args.debug) printf("[debug] needed_width: text='%s' font='%s' size=%d -> width=%.2f\n", text, font ? font : "(null)", fsz, sz.width);
        return (int)ceil(sz.width);
    }
}

int offset_x(char *text, char *font, int fsz)
{
    @autoreleasepool {
        /* In our approach the origin x is always 0, so offset is 0 */
        return 0;
    }
}

image_t *rotate_image_90ccw(image_t *im)
{
    if (!im) return NULL;
    image_t *new_im = image_new(im->height, im->width);
    if (!new_im) return NULL;
    for (int y = 0; y < im->height; ++y) {
        for (int x = 0; x < im->width; ++x) {
            new_im->data[((im->width - 1 - x) * new_im->width) + y] = im->data[y * im->width + x];
        }
    }
    image_destroy(im);
    return new_im;
}

/* Render text into a monochrome image_t using GNUstep/AppKit */
image_t *render_text(char *font, char *line[], int lines, int print_width)
{
    @autoreleasepool {
        if (render_args.debug) {
            printf("render_text(): %i lines, font = '%s', align = '%c'\n", lines, font, render_args.align);
        }

        int fsz = 0;
        if (render_args.debug) printf("[debug] render_text: lines=%d font=%s font_size_arg=%d\n", lines, font ? font : "(null)", render_args.font_size);
        if (render_args.font_size > 0) {
            fsz = render_args.font_size;
        } else {
            for (int i = 0; i < lines; ++i) {
                int tmp;
                if (render_args.rotate) {
                    tmp = find_fontsize_width(print_width, font, line[i]);
                } else {
                    tmp = find_fontsize(print_width/lines, font, line[i]);
                }
                if (tmp < 0) {
                    if (render_args.debug) printf("render_text(): find_fontsize failed for line %d\n", i);
                    return NULL;
                }
                if ((fsz == 0) || (tmp < fsz)) fsz = tmp;
            }
        }
        if (fsz <= 0) {
            if (render_args.debug) printf("render_text(): invalid font size %d\n", fsz);
            return NULL;
        }

        int x = 0;
        for (int i = 0; i < lines; ++i) {
            int tmp = needed_width(line[i], font, fsz);
            if (tmp < 0) {
                if (render_args.debug) printf("render_text(): needed_width failed for line %d\n", i);
                return NULL;
            }
            if (tmp > x) x = tmp;
        }
        if (x <= 0) {
            if (render_args.debug) printf("render_text(): invalid text width %d\n", x);
            return NULL;
        }

        NSFont *nsf = nsfont_for(font, fsz);
        int max_height = 0;
        CGFloat asc = [nsf ascender];
        /* Use ascender scaled by user-configurable percent to adjust spacing */
        double spacing_factor = (render_args.line_spacing_percent > 0) ? (render_args.line_spacing_percent / 100.0) : 1.0;
        int computed_lineheight = (int)ceil(asc * spacing_factor);
        max_height = computed_lineheight;
        int total_needed = max_height * lines;

        image_t *im;
        if (render_args.rotate) {
            im = image_new(x, total_needed);
        } else {
            im = image_new(x, print_width);
        }

        if (!im) {
            if (render_args.debug) printf("render_text(): failed to create image\n");
            return NULL;
        }
        if (render_args.debug) printf("[debug] render_text: created image %dx%d\n", im->width, im->height);

        /* Draw into an NSImage via lockFocus for GNUstep/AppKit drawing */
        NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(im->width, im->height)];
        [img lockFocus];
        /* clear to white */
        [[NSColor whiteColor] setFill];
        NSRectFill(NSMakeRect(0, 0, im->width, im->height));

        NSDictionary *attr = @{ NSFontAttributeName: nsf,
                                NSForegroundColorAttributeName: [NSColor blackColor] };

        if (!render_args.rotate && total_needed > print_width) {
            printf("[error] render_text: text doesn't fit vertically\n");
            [img unlockFocus];
            image_destroy(im);
            return NULL;
        }

        int top_margin = render_args.rotate ? 0 : (print_width - total_needed) / 2; /* center the block */
        for (int i = 0; i < lines; ++i) {
            NSString *s = [NSString stringWithUTF8String:line[i]];
            int off_x = offset_x(line[i], font, fsz);
            int align_ofs = 0;
            if (render_args.align == ALIGN_CENTER) {
                align_ofs = (x - needed_width(line[i], font, fsz)) / 2;
            } else if (render_args.align == ALIGN_RIGHT) {
                align_ofs = x - needed_width(line[i], font, fsz);
            }
            /* Compute baseline from top of image: top_margin + i*lineheight + asc (baseline relative to top) */
            int baseline_from_top = top_margin + (i * max_height) + (int)ceil(asc);
            int draw_x = off_x + align_ofs;
            int draw_y = im->height - baseline_from_top; /* convert top-based coordinate to AppKit bottom-based */
            if (render_args.debug) printf("[debug] render_text: line=%d top_margin=%d baseline_from_top=%d drawAt=(%d,%d) asc=%.2f\n", i, top_margin, baseline_from_top, draw_x, draw_y, asc);
            [s drawAtPoint:NSMakePoint(draw_x, draw_y) withAttributes:attr];
        }

        [img unlockFocus];

        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]];
        [img release];
        if (!rep) { printf("[error] render_text: failed to get bitmap rep from image\n"); image_destroy(im); return NULL; }
        if (render_args.debug) printf("[debug] render_text: NSBitmapImageRep created, bytesPerRow=%d\n", (int)[rep bytesPerRow]);

        /* Debug: check whether any pixels in the rep changed from white */
        int bpr = [rep bytesPerRow];
        unsigned char *repdata = (unsigned char *)[rep bitmapData];
        int rep_dark = 0;
        for (int y = 0; y < im->height; ++y) {
            unsigned char *row = repdata + y * bpr;
            for (int x2 = 0; x2 < im->width; ++x2) {
                int idx = x2 * 4;
                unsigned char r = row[idx];
                unsigned char g = row[idx+1];
                unsigned char b = row[idx+2];
                int lum = r + g + b;
                if (lum < (255*3)) rep_dark++;
            }
        }
        if (render_args.debug) printf("[debug] render_text: rep_dark_pixels=%d\n", rep_dark);

        int img_dark = 0;
        if (rep_dark > 0) {
            /* Copy bitmap into image_t (threshold using RGB luminance) */
            for (int y = 0; y < im->height; ++y) {
                unsigned char *row = repdata + y * bpr;
                for (int x2 = 0; x2 < im->width; ++x2) {
                    int idx = x2 * 4;
                    unsigned char r = row[idx];
                    unsigned char g = row[idx+1];
                    unsigned char b = row[idx+2];
                    int lum = r + g + b; /* 0..765 */
                    im->data[y * im->width + x2] = (lum < render_args.gray_threshold) ? 1 : 0; /* black if darker than threshold */
                    if (im->data[y * im->width + x2]) img_dark++;
                }
            }
            if (render_args.debug) printf("[debug] render_text: img_dark_pixels=%d\n", img_dark);
            [rep release];
            if (render_args.rotate) {
                return rotate_image_90ccw(im);
            }
            return im;
        }

        /* No fallback renderer: if rep is blank, we cannot render the text here */
        if (render_args.debug) printf("[error] render_text: rep blank and no fallback available - cannot render\n");
        [rep release];
        image_destroy(im);
        return NULL;
    }
}

image_t *img_append(image_t *in_1, image_t *in_2)
{
    if (!in_1 && !in_2) return NULL;
    int width = 0, length = 0, i_1_x = 0;
    if (in_1 != NULL) {
        width = in_1->height;
        length = in_1->width;
        i_1_x = in_1->width;
    }
    if (in_2 != NULL) {
        length += in_2->width;
        if (in_2->height > width) width = in_2->height;
    }
    if ((width == 0) || (length == 0)) return NULL;
    image_t *out = image_new(length, width);
    if (!out) return NULL;

    /* Fill white by default (already cleared) and copy pixels */
    if (in_1) {
        for (int y = 0; y < in_1->height; ++y) {
            for (int x = 0; x < in_1->width; ++x) {
                out->data[y * out->width + x] = in_1->data[y * in_1->width + x];
            }
        }
    }
    if (in_2) {
        for (int y = 0; y < in_2->height; ++y) {
            for (int x = 0; x < in_2->width; ++x) {
                out->data[y * out->width + (i_1_x + x)] = in_2->data[y * in_2->width + x];
            }
        }
    }
    return out;
}

image_t *img_cutmark(int print_width)
{
    image_t *out = image_new(9, print_width);
    if (!out) return NULL;
    /* draw dashed vertical line at x=5 */
    for (int y = 0; y < out->height; ++y) {
        int segment = (y / 3) % 2;
        if (segment) out->data[y * out->width + 5] = 1;
    }
    return out;
}

image_t *img_padding(int print_width, int length)
{
    if ((length < 1) || (length > 256)) length=1;
    return image_new(length, print_width);
}

void invert_image(image_t *im)
{
    if (!im) return;
    for (int y = 0; y < im->height; ++y) {
        for (int x = 0; x < im->width; ++x) {
            im->data[y * im->width + x] = im->data[y * im->width + x] ? 0 : 1;
        }
    }
}

/* Ensure an NSApplication exists and is fully initialized. This is required
   for font and drawing APIs on some GNUstep backends. */
void ensure_ns_application(void)
{
    @autoreleasepool {
        (void)[NSApplication sharedApplication];
        /* finishLaunching is safe to call multiple times */
        [NSApp finishLaunching];
    }
}
