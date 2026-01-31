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
        NSString *s = text ? [NSString stringWithUTF8String:text] : @"";
        NSString *o = @"o";
        NSFont *f = nsfont_for(font, fsz);
        NSDictionary *attr = @{ NSFontAttributeName: f };
        NSSize sz_o = [o sizeWithAttributes:attr];
        NSSize sz_t = [s sizeWithAttributes:attr];
        /* We emulate baseline offset by comparing heights */
        int o_off = (int)ceil(sz_o.height);
        int t_off = (int)ceil(sz_t.height);
        if (render_args.debug) {
            printf("debug: o baseline offset - %d\n", o_off);
            printf("debug: text baseline offset - %d\n", t_off);
        }
        return t_off - o_off;
    }
}

int find_fontsize(int want_px, char *font, char *text)
{
    @autoreleasepool {
        if (!text) return -1;
        for (int i = 4; ; ++i) {
            NSFont *f = nsfont_for(font, i);
            CGFloat lh = [f defaultLineHeightForFont];
            if (lh <= 0) return -1;
            if ((int)ceil(lh) <= want_px) {
                /* keep trying larger sizes until it grows beyond want_px */
            } else {
                return i-1 > 0 ? i-1 : -1;
            }
        }
        return -1;
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

/* Render text into a monochrome image_t using GNUstep/AppKit */
image_t *render_text(char *font, char *line[], int lines, int print_width)
{
    @autoreleasepool {
        if (render_args.debug) {
            printf("render_text(): %i lines, font = '%s', align = '%c'\n", lines, font, render_args.align);
        }

        int fsz = 0;
        if (render_args.font_size > 0) {
            fsz = render_args.font_size;
        } else {
            for (int i = 0; i < lines; ++i) {
                int tmp = find_fontsize(print_width/lines, font, line[i]);
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

        image_t *im = image_new(x, print_width);
        if (!im) {
            if (render_args.debug) printf("render_text(): failed to create image\n");
            return NULL;
        }

        /* Prepare bitmap context to draw text */
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
        if (!rep) { image_destroy(im); return NULL; }

        /* Clear to white */
        unsigned char *bitmap = (unsigned char *)[rep bitmapData];
        memset(bitmap, 255, im->width * im->height);

        NSGraphicsContext *gctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:gctx];

        NSFont *nsf = nsfont_for(font, fsz);
        NSDictionary *attr = @{ NSFontAttributeName: nsf,
                                NSForegroundColorAttributeName: [NSColor blackColor] };

        int max_height = 0;
        for (int i = 0; i < lines; ++i) {
            NSString *s = [NSString stringWithUTF8String:line[i]];
            NSSize sz = [s sizeWithAttributes:attr];
            int lineheight = (int)ceil(sz.height);
            if (lineheight > max_height) max_height = lineheight;
        }

        if ((max_height * lines) > print_width) {
            [NSGraphicsContext restoreGraphicsState];
            [rep release];
            image_destroy(im);
            return NULL;
        }

        int unused_px = print_width - (max_height * lines);
        for (int i = 0; i < lines; ++i) {
            NSString *s = [NSString stringWithUTF8String:line[i]];
            int ofs = get_baselineoffset(line[i], font, fsz);
            int pos = ((i)*(print_width/(lines))) + (max_height) - ofs;
            pos += (unused_px/lines) / 2;
            int off_x = offset_x(line[i], font, fsz);
            int align_ofs = 0;
            if (render_args.align == ALIGN_CENTER) {
                align_ofs = (x - needed_width(line[i], font, fsz)) / 2;
            } else if (render_args.align == ALIGN_RIGHT) {
                align_ofs = x - needed_width(line[i], font, fsz);
            }

            /* Drawing point: AppKit coordinate origin is bottom-left, so compute y accordingly */
            int draw_x = off_x + align_ofs;
            int draw_y = im->height - pos; /* approximate mapping */
            [s drawAtPoint:NSMakePoint(draw_x, draw_y) withAttributes:attr];
        }

        [NSGraphicsContext restoreGraphicsState];

        /* Copy bitmap into image_t (threshold) */
        int bpr = [rep bytesPerRow];
        unsigned char *repdata = (unsigned char *)[rep bitmapData];
        for (int y = 0; y < im->height; ++y) {
            for (int x2 = 0; x2 < im->width; ++x2) {
                unsigned char v = repdata[y * bpr + x2];
                im->data[y * im->width + x2] = (v < 128) ? 1 : 0;
            }
        }

        [rep release];
        return im;
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
