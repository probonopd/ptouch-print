#import <AppKit/AppKit.h>
#include "ptouch.h"
#include "ptouch-render.h"

@interface PtouchAppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, NSTextFieldDelegate>
{
    NSWindow *window;
    NSTextView *textView;
    NSTextField *fontField;
    NSTextField *fontSizeField;
    NSPopUpButton *alignPopup;
    NSTextField *pngField;
    NSTextField *tapeWidthField;
    NSButton *invertButton;
    NSButton *chainButton;
    NSButton *precutButton;
    NSTextField *statusLabel;
    NSImageView *previewImageView;
    NSTimer *previewTimer;

    /* New persistent printer state and UI elements */
    NSButton *printBtn;     /* Make print button an instance field so we can enable/disable it */
    NSTimer *statusTimer;   /* Periodically poll printer status */
    ptouch_dev ptdev;       /* Persistent device handle when available */
    int prev_media_width_mm; /* track previous media width to detect changes */
    int prev_door_open;      /* track previous door state */
}
- (void) print: (id)sender;
- (void) savePng: (id)sender;
- (void) showInfo: (id)sender;
- (void) updatePreview: (id)sender;
- (void) schedulePreviewUpdate;
- (void) renderPreviewNow;
@end

@implementation PtouchAppDelegate


- (void) applicationDidFinishLaunching: (NSNotification *)aNotification
{
    unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 650)
                                          styleMask: styleMask
                                            backing: NSBackingStoreBuffered
                                              defer: NO];
    [window setTitle: @"P-Touch"];

    NSView *contentView = [window contentView];

    // Label
    NSTextField *label1 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 610, 360, 20)];
    [label1 setStringValue: @"Text:"];
    [label1 setBezeled: NO];
    [label1 setDrawsBackground: NO];
    [label1 setEditable: NO];
    [contentView addSubview: label1];

    // Text View
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(20, 500, 360, 100)];
    [scroll setHasVerticalScroller: YES];
    textView = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 360, 100)];
    [textView setDelegate: self];
    [scroll setDocumentView: textView];
    [contentView addSubview: scroll];

    // Font
    NSTextField *label2 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 470, 50, 20)];
    [label2 setStringValue: @"Font:"];
    [label2 setBezeled: NO];
    [label2 setDrawsBackground: NO];
    [label2 setEditable: NO];
    [contentView addSubview: label2];

    fontField = [[NSTextField alloc] initWithFrame: NSMakeRect(70, 470, 150, 25)];
    [fontField setStringValue: @"Sans"];
    [fontField setDelegate: self];
    [contentView addSubview: fontField];

    NSTextField *label3 = [[NSTextField alloc] initWithFrame: NSMakeRect(230, 470, 70, 20)];
    [label3 setStringValue: @"Size (0=auto):"];
    [label3 setBezeled: NO];
    [label3 setDrawsBackground: NO];
    [label3 setEditable: NO];
    [contentView addSubview: label3];

    fontSizeField = [[NSTextField alloc] initWithFrame: NSMakeRect(310, 470, 70, 25)];
    [fontSizeField setStringValue: @"0"];
    [fontSizeField setDelegate: self];
    [contentView addSubview: fontSizeField];

    // Align
    NSTextField *label4 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 440, 50, 20)];
    [label4 setStringValue: @"Align:"];
    [label4 setBezeled: NO];
    [label4 setDrawsBackground: NO];
    [label4 setEditable: NO];
    [contentView addSubview: label4];

    alignPopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(70, 440, 100, 25) pullsDown: NO];
    [alignPopup addItemWithTitle: @"Left"];
    [alignPopup addItemWithTitle: @"Center"];
    [alignPopup addItemWithTitle: @"Right"];
    [alignPopup setTarget: self];
    [alignPopup setAction: @selector(schedulePreviewUpdate)];
    [contentView addSubview: alignPopup];

    // Options
    invertButton = [[NSButton alloc] initWithFrame: NSMakeRect(20, 410, 100, 25)];
    [invertButton setButtonType: NSSwitchButton];
    [invertButton setTitle: @"Invert"];
    [invertButton setTarget: self];
    [invertButton setAction: @selector(schedulePreviewUpdate)];
    [contentView addSubview: invertButton];

    chainButton = [[NSButton alloc] initWithFrame: NSMakeRect(130, 410, 100, 25)];
    [chainButton setButtonType: NSSwitchButton];
    [chainButton setTitle: @"Chain"];
    [contentView addSubview: chainButton];

    precutButton = [[NSButton alloc] initWithFrame: NSMakeRect(240, 410, 100, 25)];
    [precutButton setButtonType: NSSwitchButton];
    [precutButton setTitle: @"Precut"];
    [contentView addSubview: precutButton];

    // Preview
    NSTextField *labelPreview = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 380, 100, 20)];
    [labelPreview setStringValue: @"Preview:"];
    [labelPreview setBezeled: NO];
    [labelPreview setDrawsBackground: NO];
    [labelPreview setEditable: NO];
    [contentView addSubview: labelPreview];

    previewImageView = [[NSImageView alloc] initWithFrame: NSMakeRect(20, 270, 360, 100)];
    [previewImageView setImageScaling: NSImageScaleProportionallyDown];
    [previewImageView setEditable: NO];
    [previewImageView setAnimates: NO];
    [contentView addSubview: previewImageView];

    // PNG
    NSTextField *label5 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 230, 100, 20)];
    [label5 setStringValue: @"Output PNG:"];
    [label5 setBezeled: NO];
    [label5 setDrawsBackground: NO];
    [label5 setEditable: NO];
    [contentView addSubview: label5];

    pngField = [[NSTextField alloc] initWithFrame: NSMakeRect(120, 230, 150, 25)];
    [pngField setStringValue: @"output.png"];
    [contentView addSubview: pngField];

    NSTextField *label6 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 200, 150, 20)];
    [label6 setStringValue: @"Force Width (px, 0=auto):"];
    [label6 setBezeled: NO];
    [label6 setDrawsBackground: NO];
    [label6 setEditable: NO];
    [contentView addSubview: label6];

    tapeWidthField = [[NSTextField alloc] initWithFrame: NSMakeRect(180, 200, 50, 25)];
    [tapeWidthField setStringValue: @"0"];
    [tapeWidthField setDelegate: self];
    [contentView addSubview: tapeWidthField];

    // Buttons (Show Info removed; info shown on startup)
    NSButton *pngBtn = [[NSButton alloc] initWithFrame: NSMakeRect(130, 150, 120, 30)];
    [pngBtn setTitle: @"Save to PNG"];
    [pngBtn setTarget: self];
    [pngBtn setAction: @selector(savePng:)];
    [contentView addSubview: pngBtn];

    printBtn = [[NSButton alloc] initWithFrame: NSMakeRect(260, 150, 100, 30)];
    [printBtn setTitle: @"Print"];
    [printBtn setTarget: self];
    [printBtn setAction: @selector(print:)];
    [contentView addSubview: printBtn];
    /* Default disabled until we know tape state */
    [printBtn setEnabled: NO];

    statusLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 20, 360, 100)];
    [statusLabel setStringValue: @"Ready."];
    [statusLabel setBezeled: YES];
    [statusLabel setDrawsBackground: YES];
    [statusLabel setEditable: NO];
    [contentView addSubview: statusLabel];

    [window makeKeyAndOrderFront: self];

    [self showInfo: nil];

    [self schedulePreviewUpdate];

    /* Try to open printer persistently and start polling its status */
    ptdev = NULL;
    prev_media_width_mm = -1;
    prev_door_open = -1;
    if (ptouch_open(&ptdev) == 0) {
        ptouch_init(ptdev);
        if (ptouch_getstatus(ptdev, 1) == 0) {
            /* Set initial UI state based on detected media */
            if (ptdev->status->media_width > 0) {
                [statusLabel setStringValue: [NSString stringWithFormat: @"Tape: %d mm", ptdev->status->media_width]];
            } else {
                [statusLabel setStringValue: @"No tape detected" ];
            }
            [printBtn setEnabled: (ptdev->status->media_width > 0 && !ptdev->door_open)];
            prev_media_width_mm = ptdev->status->media_width;
            prev_door_open = ptdev->door_open;
        }
        statusTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.5
                                                        target: self
                                                      selector: @selector(pollPrinterStatus:)
                                                      userInfo: nil
                                                       repeats: YES] retain];
    } else {
        [statusLabel setStringValue: @"Printer not connected" ];
    }
}

- (void) setupRenderArgs
{
    render_args.font_file = (char *)[[fontField stringValue] UTF8String];
    render_args.font_size = [fontSizeField intValue];
    render_args.debug = false;
    
    NSString *align = [alignPopup titleOfSelectedItem];
    if ([align isEqualToString: @"Center"]) render_args.align = ALIGN_CENTER;
    else if ([align isEqualToString: @"Right"]) render_args.align = ALIGN_RIGHT;
    else render_args.align = ALIGN_LEFT;
}

- (void) cleanupJobs
{
    for (job_t *job = jobs; job != NULL; ) {
        job_t *next = job->next;
        if (job->type == JOB_TEXT) {
            if (job->n > 0 && job->lines[0]) {
                free(job->lines[0]);
            }
        }
        free(job);
        job = next;
    }
    jobs = last_added_job = NULL;
}

- (void) pollPrinterStatus: (id)sender
{
    /* Attempt to (re)open printer handle if we don't have one */
    if (!ptdev) {
        if (ptouch_open(&ptdev) == 0) {
            ptouch_init(ptdev);
            ptouch_getstatus(ptdev, 1);
        } else {
            [statusLabel setStringValue: @"Printer not connected"]; 
            [printBtn setEnabled: NO];
            return;
        }
    }

    if (ptouch_getstatus(ptdev, 1) != 0) {
        [statusLabel setStringValue: @"Could not read printer status"]; 
        [printBtn setEnabled: NO];
        return;
    }

    int mm = ptdev->status->media_width;
    int door = ptdev->door_open;

    if (mm != prev_media_width_mm) {
        if (mm > 0) {
            [statusLabel setStringValue: [NSString stringWithFormat: @"Tape: %d mm", mm]];
            printf("[GUI] Tape changed: %d mm\n", mm);
        } else {
            [statusLabel setStringValue: @"No tape detected"]; 
            printf("[GUI] Tape removed / door open\n");
        }
        prev_media_width_mm = mm;
    }

    if (door != prev_door_open) {
        if (door) {
            /* Door opened */
            [statusLabel setStringValue: @"Door open: printing disabled"]; 
            printf("[GUI] Door opened\n");
        } else {
            /* Door closed: re-query to get fresh tape info */
            [statusLabel setStringValue: @"Door closed: re-checking tape..."]; 
            printf("[GUI] Door closed\n");
            if (ptouch_getstatus(ptdev, 1) == 0) {
                int newmm = ptdev->status->media_width;
                if (newmm > 0) [statusLabel setStringValue: [NSString stringWithFormat: @"Tape: %d mm", newmm]];
                prev_media_width_mm = newmm;
                printf("[GUI] Re-queried tape width: %d mm\n", newmm);
            }
        }
        prev_door_open = door;
    }

    /* Disable print when tape width is 0 or door is open */
    BOOL canPrint = (mm > 0 && !door);
    [printBtn setEnabled: canPrint];
    if (!canPrint) printf("[GUI] Print disabled (tape=%d door=%d)\n", mm, door);

}

- (void) dealloc
{
    if (previewTimer) {
        [previewTimer invalidate];
        [previewTimer release];
    }
    if (statusTimer) {
        [statusTimer invalidate];
        [statusTimer release];
    }
    if (ptdev) {
        ptouch_close(ptdev);
        ptdev = NULL;
    }
    [super dealloc];
}

- (void) print: (id)sender
{
    [self setupRenderArgs];
    [self cleanupJobs];
    
    char *text = (char *)[[textView string] UTF8String];
    if (strlen(text) > 0) {
        char *text_copy = strdup(text);
        add_text(NULL, text_copy, true);
    }
    
    /* Prefer persistent ptdev if available, otherwise open a temporary connection */
    ptouch_dev active_dev = ptdev;
    BOOL opened_locally = NO;
    if (!active_dev) {
        if (ptouch_open(&active_dev) < 0) {
            NSString *msg = @"Could not open printer";
            [statusLabel setStringValue: [NSString stringWithFormat: @"Error: %@", msg]];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText: @"Printer Error"];
            [alert setInformativeText: msg];
            [alert addButtonWithTitle: @"OK"];
            [alert runModal];
            [alert release];
            return;
        }
        ptouch_init(active_dev);
        opened_locally = YES;
    }
    if (ptouch_getstatus(active_dev, 1) != 0) {
        NSString *msg = @"Could not get status from printer";
        [statusLabel setStringValue: [NSString stringWithFormat: @"Error: %@", msg]];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText: @"Printer Error"];
        [alert setInformativeText: msg];
        [alert addButtonWithTitle: @"OK"];
        [alert runModal];
        [alert release];
        if (opened_locally) ptouch_close(active_dev);
        return;
    }

    /* Prevent printing when tape width unknown (0) */
    if (active_dev->status->media_width == 0) {
        NSString *msg = @"No tape detected or door open. Close the door before printing.";
        [statusLabel setStringValue: [NSString stringWithFormat: @"Error: %@", msg]];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText: @"Printer Error"];
        [alert setInformativeText: msg];
        [alert addButtonWithTitle: @"OK"];
        [alert runModal];
        [alert release];
        if (opened_locally) ptouch_close(active_dev);
        return;
    }
    
    int print_width = ptouch_get_tape_width(active_dev);
    int max_print_width = ptouch_get_max_width(active_dev);
    if (print_width > max_print_width) print_width = max_print_width;

    image_t *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            image_t *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                out = img_append(out, im);
                image_destroy(im);
            }
        }
    }
    
    if (out) {
        if ([invertButton state] == NSOnState) invert_image(out);
        bool chain = ([chainButton state] == NSOnState);
        bool precut = ([precutButton state] == NSOnState);
        print_img(active_dev, out, chain, precut);
        ptouch_finalize(active_dev, chain);
        image_destroy(out);
        [statusLabel setStringValue: @"Printed successfully."];
    } else {
        [statusLabel setStringValue: @"Nothing to print."];
    }
    
    if (opened_locally) ptouch_close(active_dev);
}

- (void) savePng: (id)sender
{
    [self setupRenderArgs];
    [self cleanupJobs];
    
    char *text = (char *)[[textView string] UTF8String];
    if (strlen(text) > 0) {
        char *text_copy = strdup(text);
        add_text(NULL, text_copy, true);
    }
    
    int print_width = [tapeWidthField intValue];
    if (print_width <= 0) print_width = 76;
    
    image_t *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            image_t *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                out = img_append(out, im);
                image_destroy(im);
            }
        }
    }
    
    if (out) {
        if ([invertButton state] == NSOnState) invert_image(out);
        const char *filename = [[pngField stringValue] UTF8String];
        if (write_png(out, filename) == 0) {
            [statusLabel setStringValue: [NSString stringWithFormat: @"Saved to %s", filename]];
        } else {
            [statusLabel setStringValue: @"Error saving PNG"];
        }
        image_destroy(out);
    } else {
        [statusLabel setStringValue: @"Nothing to render."];
    }
}

- (void) showInfo: (id)sender
{
    ptouch_dev active_dev = ptdev;
    BOOL opened_locally = NO;
    if (!active_dev) {
        if (ptouch_open(&active_dev) < 0) {
            NSString *msg = @"Could not open printer";
            [statusLabel setStringValue: [NSString stringWithFormat: @"Error: %@", msg]];
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText: @"Printer Error"];
            [alert setInformativeText: msg];
            [alert addButtonWithTitle: @"OK"];
            [alert runModal];
            [alert release];
            return;
        }
        ptouch_init(active_dev);
        opened_locally = YES;
    }
    if (ptouch_getstatus(active_dev, 1) != 0) {
        NSString *msg = @"Could not get status from printer";
        [statusLabel setStringValue: [NSString stringWithFormat: @"Error: %@", msg]];
        NSAlert *alert = [[NSAlert alloc] init];
        [alert setMessageText: @"Printer Error"];
        [alert setInformativeText: msg];
        [alert addButtonWithTitle: @"OK"];
        [alert runModal];
        [alert release];
        if (opened_locally) ptouch_close(active_dev);
        return;
    }
    
    NSString *info = [NSString stringWithFormat: @"Max printing width: %ldpx\nMax tape width: %ldpx\nMedia width: %d mm",
                      ptouch_get_max_width(active_dev),
                      ptouch_get_tape_width(active_dev),
                      active_dev->status->media_width];
    [statusLabel setStringValue: info];
    if (opened_locally) ptouch_close(active_dev);
}

- (void) updatePreview: (id)sender
{
    [self setupRenderArgs];
    [self cleanupJobs];
    
    char *text = (char *)[[textView string] UTF8String];
    if (text && strlen(text) > 0) {
        char *text_copy = strdup(text);
        add_text(NULL, text_copy, true);
    }
    
    int print_width = [tapeWidthField intValue];
    if (print_width <= 0) print_width = 76;
    
    image_t *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            image_t *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                if (render_args.debug) printf("[debug] updatePreview: rendered im %dx%d\n", im->width, im->height);
                image_t *new_out = img_append(out, im);
                if (!new_out) {
                    printf("[error] updatePreview: img_append returned NULL\n");
                } else {
                    if (render_args.debug) printf("[debug] updatePreview: img_append -> out %dx%d\n", new_out->width, new_out->height);
                }
                out = new_out;
                image_destroy(im);
            } else {
                printf("[error] updatePreview: render_text returned NULL\n");
            }
        }
    }
    
    if (out) {
        if ([invertButton state] == NSOnState) invert_image(out);
        if (render_args.debug) printf("[debug] updatePreview: image created: %dx%d\n", out->width, out->height);
        
        int size;
        void *data = image_png_ptr(out, &size);
        if (!data) {
            printf("[error] updatePreview: image_png_ptr returned NULL\n");
        } else {
            if (render_args.debug) printf("[debug] updatePreview: image_png_ptr returned %d bytes\n", size);
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSData *nsData = [NSData dataWithBytes: data length: size];
            NSImage *nsImage = [[NSImage alloc] initWithData: nsData];
            if (nsImage) {
                [previewImageView setImage: nsImage];
                [nsImage release];
                if (render_args.debug) printf("[debug] updatePreview: preview image set successfully\n");
            } else {
                printf("[error] updatePreview: NSImage initWithData returned nil\n");
            }
            image_free(data);
            [pool drain];
        }
        image_destroy(out);
    } else {
        if (render_args.debug) printf("[debug] updatePreview: no image to render\n");
        [previewImageView setImage: nil];
    }
}

- (void) schedulePreviewUpdate
{
    if (previewTimer) {
        [previewTimer invalidate];
        [previewTimer release];
        previewTimer = nil;
    }
    previewTimer = [[NSTimer scheduledTimerWithTimeInterval: 0.5
                                                     target: self
                                                   selector: @selector(renderPreviewNow)
                                                   userInfo: nil
                                                    repeats: NO] retain];
}

- (void) renderPreviewNow
{
    if (previewTimer) {
        [previewTimer release];
        previewTimer = nil;
    }
    [self updatePreview: nil];
}

- (void) textDidChange: (NSNotification *)notification
{
    [self schedulePreviewUpdate];
}

- (void) controlTextDidChange: (NSNotification *)notification
{
    [self schedulePreviewUpdate];
}

@end

int main(int argc, const char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    PtouchAppDelegate *delegate = [[PtouchAppDelegate alloc] init];
    
    [app setDelegate: delegate];
    [app run];
    
    [pool release];
    return 0;
}
