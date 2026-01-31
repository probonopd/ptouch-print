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
}
- (void) print: (id)sender;
- (void) savePng: (id)sender;
- (void) showInfo: (id)sender;
- (void) updatePreview: (id)sender;
- (void) schedulePreviewUpdate;
- (void) renderPreviewNow;
@end

@implementation PtouchAppDelegate

- (void) dealloc
{
    if (previewTimer) {
        [previewTimer invalidate];
        [previewTimer release];
    }
    [super dealloc];
}

- (void) applicationDidFinishLaunching: (NSNotification *)aNotification
{
    unsigned int styleMask = NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask;
    window = [[NSWindow alloc] initWithContentRect: NSMakeRect(100, 100, 400, 650)
                                          styleMask: styleMask
                                            backing: NSBackingStoreBuffered
                                              defer: NO];
    [window setTitle: @"P-Touch Print GUI"];

    NSView *contentView = [window contentView];

    // Label
    NSTextField *label1 = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 610, 360, 20)];
    [label1 setStringValue: @"Text (use \\n for newlines):"];
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

    // Buttons
    NSButton *infoBtn = [[NSButton alloc] initWithFrame: NSMakeRect(20, 150, 100, 30)];
    [infoBtn setTitle: @"Show Info"];
    [infoBtn setTarget: self];
    [infoBtn setAction: @selector(showInfo:)];
    [contentView addSubview: infoBtn];

    NSButton *pngBtn = [[NSButton alloc] initWithFrame: NSMakeRect(130, 150, 120, 30)];
    [pngBtn setTitle: @"Save to PNG"];
    [pngBtn setTarget: self];
    [pngBtn setAction: @selector(savePng:)];
    [contentView addSubview: pngBtn];

    NSButton *printBtn = [[NSButton alloc] initWithFrame: NSMakeRect(260, 150, 100, 30)];
    [printBtn setTitle: @"Print"];
    [printBtn setTarget: self];
    [printBtn setAction: @selector(print:)];
    [contentView addSubview: printBtn];

    statusLabel = [[NSTextField alloc] initWithFrame: NSMakeRect(20, 20, 360, 100)];
    [statusLabel setStringValue: @"Ready."];
    [statusLabel setBezeled: YES];
    [statusLabel setDrawsBackground: YES];
    [statusLabel setEditable: NO];
    [contentView addSubview: statusLabel];

    [window makeKeyAndOrderFront: self];

    [self schedulePreviewUpdate];
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

- (void) print: (id)sender
{
    [self setupRenderArgs];
    [self cleanupJobs];
    
    char *text = (char *)[[textView string] UTF8String];
    if (strlen(text) > 0) {
        char *text_copy = strdup(text);
        add_text(NULL, text_copy, true);
    }
    
    ptouch_dev ptdev = NULL;
    if (ptouch_open(&ptdev) < 0) {
        [statusLabel setStringValue: @"Error: Could not open printer"];
        return;
    }
    ptouch_init(ptdev);
    if (ptouch_getstatus(ptdev, 1) != 0) {
        [statusLabel setStringValue: @"Error: Could not get status"];
        ptouch_close(ptdev);
        return;
    }
    
    int print_width = ptouch_get_tape_width(ptdev);
    int max_print_width = ptouch_get_max_width(ptdev);
    if (print_width > max_print_width) print_width = max_print_width;

    gdImage *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            gdImage *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                out = img_append(out, im);
                gdImageDestroy(im);
            }
        }
    }
    
    if (out) {
        if ([invertButton state] == NSOnState) invert_image(out);
        bool chain = ([chainButton state] == NSOnState);
        bool precut = ([precutButton state] == NSOnState);
        print_img(ptdev, out, chain, precut);
        ptouch_finalize(ptdev, chain);
        gdImageDestroy(out);
        [statusLabel setStringValue: @"Printed successfully."];
    } else {
        [statusLabel setStringValue: @"Nothing to print."];
    }
    
    ptouch_close(ptdev);
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
    
    gdImage *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            gdImage *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                out = img_append(out, im);
                gdImageDestroy(im);
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
        gdImageDestroy(out);
    } else {
        [statusLabel setStringValue: @"Nothing to render."];
    }
}

- (void) showInfo: (id)sender
{
    ptouch_dev ptdev = NULL;
    if (ptouch_open(&ptdev) < 0) {
        [statusLabel setStringValue: @"Error: Could not open printer"];
        return;
    }
    ptouch_init(ptdev);
    if (ptouch_getstatus(ptdev, 1) != 0) {
        [statusLabel setStringValue: @"Error: Could not get status"];
        ptouch_close(ptdev);
        return;
    }
    
    NSString *info = [NSString stringWithFormat: @"Max printing width: %ldpx\nMax tape width: %ldpx\nMedia width: %d mm",
                      ptouch_get_max_width(ptdev),
                      ptouch_get_tape_width(ptdev),
                      ptdev->status->media_width];
    [statusLabel setStringValue: info];
    ptouch_close(ptdev);
}

- (void) updatePreview: (id)sender
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
    
    gdImage *out = NULL;
    for (job_t *job = jobs; job != NULL; job = job->next) {
        if (job->type == JOB_TEXT) {
            gdImage *im = render_text(render_args.font_file, job->lines, job->n, print_width);
            if (im) {
                out = img_append(out, im);
                gdImageDestroy(im);
            }
        }
    }
    
    if (out) {
        if ([invertButton state] == NSOnState) invert_image(out);
        
        int size;
        void *data = gdImagePngPtr(out, &size);
        if (data) {
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSData *nsData = [NSData dataWithBytes: data length: size];
            NSImage *nsImage = [[NSImage alloc] initWithData: nsData];
            if (nsImage) {
                [previewImageView setImage: nsImage];
                [nsImage release];
            }
            gdFree(data);
            [pool drain];
        }
        gdImageDestroy(out);
    } else {
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
