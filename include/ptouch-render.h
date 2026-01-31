#ifndef PTOUCH_RENDER_H
#define PTOUCH_RENDER_H

#include <stdbool.h>
#include <argp.h>
#include "ptouch.h"

#define MAX_LINES 8

typedef enum { ALIGN_LEFT = 'l', ALIGN_CENTER = 'c', ALIGN_RIGHT = 'r' } align_type_t;
typedef enum { JOB_CUTMARK, JOB_IMAGE, JOB_PAD, JOB_TEXT, JOB_UNDEFINED } job_type_t;

typedef struct job {
	job_type_t type;
	int n;
	char *lines[MAX_LINES];
	struct job *next;
} job_t;

struct render_arguments {
	align_type_t align;
	char *font_file;
	int font_size;
	bool debug;
	int gray_threshold; /* threshold (sum of R+G+B) to consider pixel 'black' */
	int line_spacing_percent; /* percent multiplier (100 = asc), <100 reduces space */
};

extern struct render_arguments render_args;

/* Opaque image type representing a monochrome raster image */
typedef struct image_t {
	int width;  /* width in px (x dimension) */
	int height; /* height in px (y dimension) */
	unsigned char *data; /* row-major, 0 = white, 1 = black */
} image_t;

/* Image creation / destruction / IO (implemented using native GNUstep rendering) */
image_t *image_load(const char *file);
int write_png(image_t *im, const char *file);
void *image_png_ptr(image_t *im, int *size); /* returns malloc'd PNG data, free with image_free */
void image_free(void *ptr);
void image_destroy(image_t *im);

/* Ensure the shared NSApplication exists and is finished launching before
   calling AppKit/GNUstep APIs from CLI tools. */
void ensure_ns_application(void);

/* Raster / measurement / rendering */
void rasterline_setpixel(uint8_t* rasterline, size_t size, int pixel);
int get_baselineoffset(char *text, char *font, int fsz);
int find_fontsize(int want_px, char *font, char *text);
int needed_width(char *text, char *font, int fsz);
int offset_x(char *text, char *font, int fsz);
image_t *render_text(char *font, char *line[], int lines, int print_width);
image_t *img_append(image_t *in_1, image_t *in_2);
image_t *img_cutmark(int print_width);
image_t *img_padding(int print_width, int length);
void invert_image(image_t *im);
int print_img(ptouch_dev ptdev, image_t *im, int chain, int precut);

/* Job management */
extern job_t *jobs;
extern job_t *last_added_job;

void add_job(job_type_t type, int n, char *line);
void add_text(struct argp_state *state, char *arg, bool new_job);

#endif
