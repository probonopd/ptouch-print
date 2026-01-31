#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <gd.h>
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

int print_img(ptouch_dev ptdev, gdImage *im, int chain, int precut)
{
	uint8_t rasterline[(ptdev->devinfo->max_px)/8];

	if (!im) {
		printf(_("nothing to print\n"));
		return -1;
	}
	int tape_width = ptouch_get_tape_width(ptdev);
	size_t max_pixels = ptouch_get_max_width(ptdev);
	int d = (gdImageRed(im,1) + gdImageGreen(im,1) + gdImageBlue(im,1) < gdImageRed(im,0) + gdImageGreen(im,0) + gdImageBlue(im,0))?1:0;
	if (gdImageSY(im) > tape_width) {
		printf(_("image is too large (%ipx x %ipx)\n"), gdImageSX(im), gdImageSY(im));
		printf(_("maximum printing width for this tape is %ipx\n"), tape_width);
		return -1;
	}
	if (render_args.debug) {
		printf(_("image size (%ipx x %ipx)\n"), gdImageSX(im), gdImageSY(im));
	}
	int offset = ((int)max_pixels / 2) - (gdImageSY(im)/2);
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
		ptouch_info_cmd(ptdev, gdImageSX(im));
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
	for (int k = 0; k < gdImageSX(im); ++k) {
		memset(rasterline, 0, sizeof(rasterline));
		for (int i = 0; i < gdImageSY(im); ++i) {
			if (gdImageGetPixel(im, k, gdImageSY(im) - 1 - i) == d) {
				rasterline_setpixel(rasterline, sizeof(rasterline), offset+i);
			}
		}
		if (ptouch_sendraster(ptdev, rasterline, (ptdev->devinfo->max_px / 8)) != 0) {
			printf(_("ptouch_sendraster() failed\n"));
			return -1;
		}
	}
	return 0;
}

gdImage *image_load(const char *file)
{
	const uint8_t png[8] = {0x89,'P','N','G',0x0d,0x0a,0x1a,0x0a};
	char d[10];
	FILE *f;
	gdImage *img = NULL;

	if (!strcmp(file, "-")) {
		f = stdin;
	} else {
		f = fopen(file, "rb");
	}
	if (f == NULL) {
		return NULL;
	}
	if (fseek(f, 0L, SEEK_SET)) {
		img = gdImageCreateFromPng(f);
	} else {
		if (fread(d, sizeof(d), 1, f) != 1) {
			fclose(f);
			return NULL;
		}
		rewind(f);
		if (memcmp(d, png, 8) == 0) {
			img = gdImageCreateFromPng(f);
		}
	}
	if (f != stdin) {
		fclose(f);
	}
	return img;
}

int write_png(gdImage *im, const char *file)
{
	FILE *f;
	if ((f = fopen(file, "wb")) == NULL) {
		printf(_("writing image '%s' failed\n"), file);
		return -1;
	}
	gdImagePng(im, f);
	fclose(f);
	return 0;
}

int get_baselineoffset(char *text, char *font, int fsz)
{
	int brect[8];
	gdImageStringFT(NULL, &brect[0], -1, font, fsz, 0.0, 0, 0, "o");
	int o_offset = brect[1];
	gdImageStringFT(NULL, &brect[0], -1, font, fsz, 0.0, 0, 0, text);
	int text_offset = brect[1];
	if (render_args.debug) {
		printf(_("debug: o baseline offset - %d\n"), o_offset);
		printf(_("debug: text baseline offset - %d\n"), text_offset);
	}
	return text_offset-o_offset;
}

int find_fontsize(int want_px, char *font, char *text)
{
	int save = 0;
	int brect[8];

	for (int i=4; ; ++i) {
		if (gdImageStringFT(NULL, &brect[0], -1, font, i, 0.0, 0, 0, text) != NULL) {
			break;
		}
		if (brect[1]-brect[5] <= want_px) {
			save = i;
		} else {
			break;
		}
	}
	if (save == 0) {
		return -1;
	}
	return save;
}

int needed_width(char *text, char *font, int fsz)
{
	int brect[8];
	if (gdImageStringFT(NULL, &brect[0], -1, font, fsz, 0.0, 0, 0, text) != NULL) {
		return -1;
	}
	return brect[2]-brect[0];
}

int offset_x(char *text, char *font, int fsz)
{
	int brect[8];
	if (gdImageStringFT(NULL, &brect[0], -1, font, fsz, 0.0, 0, 0, text) != NULL) {
		return -1;
	}
	return -brect[0];
}

gdImage *render_text(char *font, char *line[], int lines, int print_width)
{
	int brect[8];
	int i, black, x = 0, tmp = 0, fsz = 0;
	char *p;
	gdImage *im = NULL;

	if (render_args.debug) {
		printf(_("render_text(): %i lines, font = '%s', align = '%c'\n"), lines, font, render_args.align);
	}
	if (gdFTUseFontConfig(1) != GD_TRUE) {
		printf(_("warning: font config not available\n"));
	}
	if (render_args.font_size > 0) {
		fsz = render_args.font_size;
	} else {
		for (i = 0; i < lines; ++i) {
			if ((tmp = find_fontsize(print_width/lines, font, line[i])) < 0) {
				if (render_args.debug) printf(_("render_text(): find_fontsize failed for line %d\n"), i);
				return NULL;
			}
			if ((fsz == 0) || (tmp < fsz)) {
				fsz=tmp;
			}
		}
	}
	if (fsz <= 0) {
		if (render_args.debug) printf(_("render_text(): invalid font size %d\n"), fsz);
		return NULL;
	}
	for (i = 0; i < lines; ++i) {
		tmp = needed_width(line[i], font, fsz);
		if (tmp < 0) {
			if (render_args.debug) printf(_("render_text(): needed_width failed for line %d\n"), i);
			return NULL;
		}
		if (tmp > x) {
			x = tmp;
		}
	}
	if (x <= 0) {
		if (render_args.debug) printf(_("render_text(): invalid text width %d\n"), x);
		return NULL;
	}
	im = gdImageCreatePalette(x, print_width);
	if (!im) {
		if (render_args.debug) printf(_("render_text(): failed to create image\n"));
		return NULL;
	}
	gdImageColorAllocate(im, 255, 255, 255);
	black = gdImageColorAllocate(im, 0, 0, 0);
	int max_height=0;
	for (i = 0; i < lines; ++i) {
		if ((p = gdImageStringFT(NULL, &brect[0], -black, font, fsz, 0.0, 0, 0, line[i])) != NULL) {
			printf(_("error in gdImageStringFT: %s\n"), p);
		}
		int lineheight = brect[1]-brect[5];
		if (lineheight > max_height) {
			max_height = lineheight;
		}
	}
	if ((max_height * lines) > print_width) {
		return NULL;
	}
	int unused_px = print_width - (max_height * lines);
	for (i = 0; i < lines; ++i) {
		int ofs = get_baselineoffset(line[i], font, fsz);
		int pos = ((i)*(print_width/(lines)))+(max_height)-ofs;
		pos += (unused_px/lines) / 2;
		int off_x = offset_x(line[i], font, fsz);
		int align_ofs = 0;
		if (render_args.align == ALIGN_CENTER) {
			align_ofs = (x - needed_width(line[i], font, fsz)) / 2;
		} else if (render_args.align == ALIGN_RIGHT) {
			align_ofs = x - needed_width(line[i], font, fsz);
		}
		gdImageStringFT(im, &brect[0], -black, font, fsz, 0.0, off_x + align_ofs, pos, line[i]);
	}
	return im;
}

gdImage *img_append(gdImage *in_1, gdImage *in_2)
{
	gdImage *out = NULL;
	int width = 0, length = 0, i_1_x = 0;
	if (in_1 != NULL) {
		width = gdImageSY(in_1);
		length = gdImageSX(in_1);
		i_1_x = gdImageSX(in_1);
	}
	if (in_2 != NULL) {
		length += gdImageSX(in_2);
		if (gdImageSY(in_2) > width) width = gdImageSY(in_2);
	}
	if ((width == 0) || (length == 0)) return NULL;
	out = gdImageCreatePalette(length, width);
	gdImageColorAllocate(out, 255, 255, 255);
	gdImageColorAllocate(out, 0, 0, 0);
	if (in_1 != NULL) gdImageCopy(out, in_1, 0, 0, 0, 0, gdImageSX(in_1), gdImageSY(in_1));
	if (in_2 != NULL) gdImageCopy(out, in_2, i_1_x, 0, 0, 0, gdImageSX(in_2), gdImageSY(in_2));
	return out;
}

gdImage *img_cutmark(int print_width)
{
	gdImage *out = gdImageCreatePalette(9, print_width);
	gdImageColorAllocate(out, 255, 255, 255);
	int black = gdImageColorAllocate(out, 0, 0, 0);
	int style_dashed[6] = {gdTransparent, gdTransparent, gdTransparent, black, black, black};
	gdImageSetStyle(out, style_dashed, 6);
	gdImageLine(out, 5, 0, 5, print_width - 1, gdStyled);
	return out;
}

gdImage *img_padding(int print_width, int length)
{
	if ((length < 1) || (length > 256)) length=1;
	gdImage *out = gdImageCreatePalette(length, print_width);
	gdImageColorAllocate(out, 255, 255, 255);
	return out;
}

void invert_image(gdImage *im)
{
	if (!im) return;
	int sx = gdImageSX(im), sy = gdImageSY(im);
	int white = gdImageColorClosest(im, 255, 255, 255);
	int black = gdImageColorClosest(im, 0, 0, 0);
	for (int x = 0; x < sx; ++x) {
		for (int y = 0; y < sy; ++y) {
			int c = gdImageGetPixel(im, x, y);
			int lum = gdImageRed(im, c) + gdImageGreen(im, c) + gdImageBlue(im, c);
			gdImageSetPixel(im, x, y, (lum > ((255*3)/2)) ? black : white);
		}
	}
}

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
