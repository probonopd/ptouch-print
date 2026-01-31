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
    NSTextField *tapeWidthField;
    NSButton *invertButton;
    NSButton *rotateButton;
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
- (void) showAbout: (id)sender;
- (void) updatePreview: (id)sender;
- (void) schedulePreviewUpdate;
- (void) renderPreviewNow;
- (void) setupMenus;
@end

@implementation PtouchAppDelegate


- (void) applicationDidFinishLaunching: (NSNotification *)aNotification
{
    [self setupMenus];
    unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 500, 650)
                                          styleMask: styleMask
                                            backing: NSBackingStoreBuffered
                                              defer: NO];
    [window setTitle: @"P-touch Utility"];

    NSView *contentView = [window contentView];



    // Text View
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect(24, 535, 452, 100)];
    [scroll setHasVerticalScroller: YES];
    textView = [[NSTextView alloc] initWithFrame: NSMakeRect(0, 0, 452, 100)];
    [textView setDelegate: self];
    [scroll setDocumentView: textView];
    [contentView addSubview: scroll];

    // Font
    NSTextField *label2 = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 497, 50, 22)];
    [label2 setStringValue: @"Font:"];
    [label2 setBezeled: NO];
    [label2 setDrawsBackground: NO];
    [label2 setEditable: NO];
    [contentView addSubview: label2];

    fontField = [[NSTextField alloc] initWithFrame: NSMakeRect(82, 497, 150, 22)];
    [fontField setStringValue: @"Sans"];
    [fontField setDelegate: self];
    [contentView addSubview: fontField];

    NSTextField *label3 = [[NSTextField alloc] initWithFrame: NSMakeRect(248, 497, 100, 22)];
    [label3 setStringValue: @"Size (0=auto):"];
    [label3 setBezeled: NO];
    [label3 setDrawsBackground: NO];
    [label3 setEditable: NO];
    [contentView addSubview: label3];

    fontSizeField = [[NSTextField alloc] initWithFrame: NSMakeRect(356, 497, 70, 22)];
    [fontSizeField setStringValue: @"0"];
    [fontSizeField setDelegate: self];
    [contentView addSubview: fontSizeField];

    // Align
    NSTextField *label4 = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 456, 50, 22)];
    [label4 setStringValue: @"Align:"];
    [label4 setBezeled: NO];
    [label4 setDrawsBackground: NO];
    [label4 setEditable: NO];
    [contentView addSubview: label4];

    alignPopup = [[NSPopUpButton alloc] initWithFrame: NSMakeRect(82, 456, 120, 25) pullsDown: NO];
    [alignPopup addItemWithTitle: @"Left"];
    [alignPopup addItemWithTitle: @"Center"];
    [alignPopup addItemWithTitle: @"Right"];
    [alignPopup setTarget: self];
    [alignPopup setAction: @selector(schedulePreviewUpdate)];
    [contentView addSubview: alignPopup];

    // Options
    invertButton = [[NSButton alloc] initWithFrame: NSMakeRect(24, 422, 100, 18)];
    [invertButton setButtonType: NSSwitchButton];
    [invertButton setTitle: @"Invert"];
    [invertButton setTarget: self];
    [invertButton setAction: @selector(schedulePreviewUpdate)];
    [contentView addSubview: invertButton];

    rotateButton = [[NSButton alloc] initWithFrame: NSMakeRect(134, 422, 100, 18)];
    [rotateButton setButtonType: NSSwitchButton];
    [rotateButton setTitle: @"Rotate 90"];
    [rotateButton setTarget: self];
    [rotateButton setAction: @selector(schedulePreviewUpdate)];
    [contentView addSubview: rotateButton];

    chainButton = [[NSButton alloc] initWithFrame: NSMakeRect(244, 422, 100, 18)];
    [chainButton setButtonType: NSSwitchButton];
    [chainButton setTitle: @"Chain"];
    [contentView addSubview: chainButton];

    precutButton = [[NSButton alloc] initWithFrame: NSMakeRect(354, 422, 100, 18)];
    [precutButton setButtonType: NSSwitchButton];
    [precutButton setTitle: @"Precut"];
    [contentView addSubview: precutButton];

    // Preview
    NSTextField *labelPreview = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 384, 100, 22)];
    [labelPreview setStringValue: @"Preview:"];
    [labelPreview setBezeled: NO];
    [labelPreview setDrawsBackground: NO];
    [labelPreview setEditable: NO];
    [contentView addSubview: labelPreview];

    previewImageView = [[NSImageView alloc] initWithFrame: NSMakeRect(24, 276, 452, 100)];
    [previewImageView setImageScaling: NSImageScaleProportionallyDown];
    [previewImageView setEditable: NO];
    [previewImageView setAnimates: NO];
    [contentView addSubview: previewImageView];

    NSTextField *label6 = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 238, 150, 22)];
    [label6 setStringValue: @"Force Width (px):"];
    [label6 setBezeled: NO];
    [label6 setDrawsBackground: NO];
    [label6 setEditable: NO];
    [contentView addSubview: label6];

    tapeWidthField = [[NSTextField alloc] initWithFrame: NSMakeRect(184, 238, 60, 22)];
    [tapeWidthField setStringValue: @"0"];
    [tapeWidthField setDelegate: self];
    [contentView addSubview: tapeWidthField];

    // Buttons (Show Info removed; info shown on startup)


    printBtn = [[NSButton alloc] initWithFrame: NSMakeRect(376, 70, 100, 20)];
    [printBtn setTitle: @"Print"];
    [printBtn setTarget: self];
    [printBtn setAction: @selector(print:)];
    [contentView addSubview: printBtn];
    /* Default disabled until we know tape state */
    [printBtn setEnabled: NO];

    /* Status bar (single-line) */
    statusLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(24, 20, 452, 20)];
    [statusLabel setStringValue: @"Ready."];
    [statusLabel setBezeled: NO];
    [statusLabel setDrawsBackground: YES];
    /* light gray background for status feel */
    @try {
        [statusLabel setBackgroundColor: [NSColor colorWithCalibratedWhite:0.95 alpha:1.0]];
    } @catch (id ex) {
        /* some backends may not support colorSetting; ignore */
    }
    [statusLabel setEditable: NO];
    [statusLabel setSelectable: NO];
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

- (void) setupMenus
{
    NSMenu *mainMenu = [[NSMenu alloc] init];
    
    // Application Menu
    NSMenuItem *appMenuItem = [[NSMenuItem alloc] initWithTitle: @"P-touch Utility" action: NULL keyEquivalent: @""];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle: @"P-touch Utility"];
    [appMenu addItemWithTitle: @"About P-touch Utility" action: @selector(orderFrontStandardAboutPanel:) keyEquivalent: @""];
    [appMenu addItem: [NSMenuItem separatorItem]];
    [appMenu addItemWithTitle: @"Quit" action: @selector(terminate:) keyEquivalent: @"q"];
    [appMenuItem setSubmenu: appMenu];
    [mainMenu addItem: appMenuItem];
    
    // File Menu
    NSMenuItem *fileMenuItem = [[NSMenuItem alloc] initWithTitle: @"File" action: NULL keyEquivalent: @""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle: @"File"];
    NSMenuItem *saveItem = [[NSMenuItem alloc] initWithTitle: @"Save as..." action: @selector(saveMenu:) keyEquivalent: @"s"];
    [saveItem setTarget: self];
    [fileMenu addItem: saveItem];
    [fileMenu addItem: [NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle: @"Close" action: @selector(performClose:) keyEquivalent: @"w"];
    [fileMenuItem setSubmenu: fileMenu];
    [mainMenu addItem: fileMenuItem];
    
    // Edit Menu
    NSMenuItem *editMenuItem = [[NSMenuItem alloc] initWithTitle: @"Edit" action: NULL keyEquivalent: @""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle: @"Edit"];
    [editMenu addItemWithTitle: @"Cut" action: @selector(cut:) keyEquivalent: @"x"];
    [editMenu addItemWithTitle: @"Copy" action: @selector(copy:) keyEquivalent: @"c"];
    [editMenu addItemWithTitle: @"Paste" action: @selector(paste:) keyEquivalent: @"v"];
    [editMenu addItemWithTitle: @"Select All" action: @selector(selectAll:) keyEquivalent: @"a"];
    [editMenuItem setSubmenu: editMenu];
    [mainMenu addItem: editMenuItem];

    [NSApp setMainMenu: mainMenu];
}

- (void) showAbout: (id)sender
{
    [NSApp orderFrontStandardAboutPanel: sender];
}

- (void) saveMenu: (id)sender
{
    /* Ensure app is active so the save dialog appears in front */
    printf("[GUI] Save menu invoked\n");
    [NSApp activateIgnoringOtherApps: YES];
    [statusLabel setStringValue: @"Opening Save As dialog..."];

    /* Offer a Save dialog pre-configured for PNG files with a default name */
    NSSavePanel *panel = [NSSavePanel savePanel];
#if defined(NSAppKitVersionNumber)
    [panel setAllowedFileTypes: @[ @"png" ]];
#endif
    /* Derive a sensible default filename from the first words of the Text area */
    NSString *textString = [[textView string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *defaultName = @"untitled";
    if (textString && [textString length] > 0) {
        NSArray *words = [textString componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSMutableArray *picked = [NSMutableArray array];
        for (NSString *w in words) {
            if ([w length] > 0) {
                [picked addObject:w];
                if ([picked count] >= 3) break; /* use up to first 3 words */
            }
        }
        if ([picked count] > 0) {
            NSString *joined = [picked componentsJoinedByString:@"_"];
            /* Remove characters not valid in filenames */
            NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_."]; 
            NSArray *parts = [joined componentsSeparatedByCharactersInSet:[allowed invertedSet]];
            NSString *san = [parts componentsJoinedByString:@"_"];
            if ([san length] > 0) {
                /* Limit length */
                if ([san length] > 40) san = [san substringToIndex:40];
                defaultName = san;
            }
        }
    }
    [panel setNameFieldStringValue: [defaultName stringByAppendingPathExtension:@"png"]];

    NSInteger res = 0;
    if ([panel respondsToSelector: @selector(runModal)]) {
        res = [panel runModal];
    } else if ([panel respondsToSelector: @selector(runModalForDirectory:file:)]) {
        /* Older GNUstep API fallback */
        res = (NSInteger)[panel performSelector: @selector(runModalForDirectory:file:) withObject: nil withObject: [defaultName stringByAppendingPathExtension:@"png"]];
    } else {
        /* Fallback: bring to front and wait briefly — best-effort */
        [panel orderFront: self];
    }

    if (res == NSOKButton || res == NSModalResponseOK) {
        NSString *path = [[panel URL] path];
        const char *filename = [path UTF8String];
        [statusLabel setStringValue: [NSString stringWithFormat: @"Saving to %@...", path]];
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
            if (write_png(out, filename) == 0) {
                [statusLabel setStringValue: [NSString stringWithFormat: @"Saved to %@", path]];
            } else {
                [statusLabel setStringValue: @"Error saving PNG"];
            }
            image_destroy(out);
        } else {
            [statusLabel setStringValue: @"Nothing to render."];
        }
    } else {
        [statusLabel setStringValue: @"Save cancelled."];
    }
}

- (void) setupRenderArgs
{
    render_args.font_file = (char *)[[fontField stringValue] UTF8String];
    render_args.font_size = [fontSizeField intValue];
    render_args.debug = false;
    render_args.rotate = [rotateButton state] == NSOnState;
    
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
            if (job->n > 0 && job->lines && job->lines[0]) {
                free(job->lines[0]);
            }
            if (job->lines) free(job->lines);
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
        NSSavePanel *panel = [NSSavePanel savePanel];
        [panel setNameFieldStringValue: @"output.png"];
        NSInteger res = [panel runModal];
        if (res == NSOKButton || res == NSModalResponseOK) {
            NSString *path = [[panel URL] path];
            const char *filename = [path UTF8String];
            if (write_png(out, filename) == 0) {
                [statusLabel setStringValue: [NSString stringWithFormat: @"Saved to %@", path]];
            } else {
                [statusLabel setStringValue: @"Error saving PNG"];
            }
        } else {
            [statusLabel setStringValue: @"Save cancelled."];
        }
        image_destroy(out);
    } else {
        [statusLabel setStringValue: @""];
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
