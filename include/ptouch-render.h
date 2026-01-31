#ifndef PTOUCH_RENDER_H
#define PTOUCH_RENDER_H

#include <gd.h>
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
};

extern struct render_arguments render_args;

gdImage *image_load(const char *file);
int write_png(gdImage *im, const char *file);
void rasterline_setpixel(uint8_t* rasterline, size_t size, int pixel);
int get_baselineoffset(char *text, char *font, int fsz);
int find_fontsize(int want_px, char *font, char *text);
int needed_width(char *text, char *font, int fsz);
int offset_x(char *text, char *font, int fsz);
gdImage *render_text(char *font, char *line[], int lines, int print_width);
gdImage *img_append(gdImage *in_1, gdImage *in_2);
gdImage *img_cutmark(int print_width);
gdImage *img_padding(int print_width, int length);
void invert_image(gdImage *im);
int print_img(ptouch_dev ptdev, gdImage *im, int chain, int precut);

/* Job management */
extern job_t *jobs;
extern job_t *last_added_job;

void add_job(job_type_t type, int n, char *line);
void add_text(struct argp_state *state, char *arg, bool new_job);

#endif
