#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <libintl.h>
#include <errno.h>
#include "ptouch-render.h"

#define _(s) gettext(s)

struct render_arguments render_args = {
	.align = ALIGN_LEFT,
	.font_file = "Sans",
	.font_size = 0,
	.debug = false
};

job_t *jobs = NULL;
job_t *last_added_job = NULL;

void rasterline_setpixel(uint8_t* rasterline, size_t size, int pixel)
{
	if ((pixel < 0) || (pixel >= (int)(size*8))) {
		return;
	}
	rasterline[(size-1)-(pixel/8)] |= (uint8_t)(1<<(pixel%8));
}

int print_img(ptouch_dev ptdev, image_t *im, int chain, int precut)
{
	uint8_t rasterline[(ptdev->devinfo->max_px)/8];

	if (!im) {
		printf(_("nothing to print\n"));
		return -1;
	}
	int tape_width = ptouch_get_tape_width(ptdev);
	size_t max_pixels = ptouch_get_max_width(ptdev);
	/* Determine whether black pixel is represented by 1 or 0; assume data uses 1=black */
	int d = 1;
	if (im->height > tape_width) {
		printf(_("image is too large (%ipx x %ipx)\n"), im->width, im->height);
		printf(_("maximum printing width for this tape is %ipx\n"), tape_width);
		return -1;
	}
	if (render_args.debug) {
		printf(_("image size (%ipx x %ipx)\n"), im->width, im->height);
	}
	int offset = ((int)max_pixels / 2) - (im->height/2);
	if ((ptdev->devinfo->flags & FLAG_RASTER_PACKBITS) == FLAG_RASTER_PACKBITS) {
		if (render_args.debug) {
			printf("enable PackBits mode\n");
		}
		ptouch_enable_packbits(ptdev);
	}
	if (ptouch_rasterstart(ptdev) != 0) {
		printf(_("ptouch_rasterstart() failed\n"));
		return -1;
	}
	if ((ptdev->devinfo->flags & FLAG_USE_INFO_CMD) == FLAG_USE_INFO_CMD) {
		ptouch_info_cmd(ptdev, im->width);
		if (render_args.debug) {
			printf(_("send print information command\n"));
		}
	}
	if ((ptdev->devinfo->flags & FLAG_D460BT_MAGIC) == FLAG_D460BT_MAGIC) {
		ptouch_send_d460bt_magic(ptdev);
		if (render_args.debug) {
			printf(_("send PT-D460BT magic commands\n"));
		}
	}
	if ((ptdev->devinfo->flags & FLAG_HAS_PRECUT) == FLAG_HAS_PRECUT) {
		if (precut) {
			ptouch_send_precut_cmd(ptdev, 1);
			if (render_args.debug) {
				printf(_("send precut command\n"));
			}
		}
	}
	if ((ptdev->devinfo->flags & FLAG_D460BT_MAGIC) == FLAG_D460BT_MAGIC) {
		if (chain) {
			ptouch_send_d460bt_chain(ptdev);
			if (render_args.debug) {
				printf(_("send PT-D460BT chain commands\n"));
			}
		}
	}
	/* Iterate over X from 0..width-1, and Y from bottom to top as before */
	for (int x = 0; x < im->width; ++x) {
		memset(rasterline, 0, sizeof(rasterline));
		for (int i = 0; i < im->height; ++i) {
			int y = im->height - 1 - i;
			unsigned char pix = im->data[y * im->width + x];
			if (pix == d) {
				rasterline_setpixel(rasterline, sizeof(rasterline), offset + i);
			}
		}
		if (ptouch_sendraster(ptdev, rasterline, (ptdev->devinfo->max_px / 8)) != 0) {
			printf(_("ptouch_sendraster() failed\n"));
			return -1;
		}
	}
	return 0;
}

/* The remaining functions (image/text rendering, IO, image ops) are implemented
 * in the GNUstep-based rendering implementation (Objective-C) in
 * src/ptouch-render-gnustep.m
 */

void add_job(job_type_t type, int n, char *line)
{
	job_t *new_job = (job_t*)malloc(sizeof(job_t));
	if (!new_job) return;
	new_job->type = type;
	if (type == JOB_TEXT && n > MAX_LINES) n = MAX_LINES;
	new_job->n = n;
	new_job->lines[0] = line;
	for (int i=1; i<MAX_LINES; ++i) new_job->lines[i] = NULL;
	new_job->next = NULL;
	if (!last_added_job) {
		jobs = last_added_job = new_job;
	} else {
		last_added_job->next = new_job;
		last_added_job = new_job;
	}
}

void add_text(struct argp_state *state, char *arg, bool new_job)
{
	char *p = arg;
	bool first_part = true;
	do {
		char *next1 = strstr(p, "\\n");
		char *next2 = strchr(p, '\n');
		char *next = NULL, *p_next = NULL;
		int skip = 0;
		if (next1 && next2) {
			if (next1 < next2) { next = next1; skip = 2; }
			else { next = next2; skip = 1; }
		} else if (next1) { next = next1; skip = 2; }
		else if (next2) { next = next2; skip = 1; }
		if (next) { *next = '\0'; p_next = next + skip; }
		else { p_next = NULL; }
		if (new_job && first_part) {
			add_job(JOB_TEXT, 1, p);
		} else {
			if (!last_added_job || last_added_job->type != JOB_TEXT) {
				add_job(JOB_TEXT, 1, p);
			} else {
				if (last_added_job->n >= MAX_LINES) {
					if (state) argp_failure(state, 1, EINVAL, _("Only up to %d lines are supported"), MAX_LINES);
					return;
				}
				last_added_job->lines[last_added_job->n++] = p;
			}
		}
		p = p_next;
		first_part = false;
	} while (p);
}
