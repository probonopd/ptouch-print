/*
	ptouch-print - Print labels with images or text on a Brother P-Touch

	Copyright (C) 2015-2025 Dominic Radermacher <dominic@familie-radermacher.ch>

	This program is free software; you can redistribute it and/or modify it
	under the terms of the GNU General Public License version 3 as
	published by the Free Software Foundation

	This program is distributed in the hope that it will be useful, but
	WITHOUT ANY WARRANTY; without even the implied warranty of
	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
	See the GNU General Public License for more details.

	You should have received a copy of the GNU General Public License
	along with this program; if not, write to the Free Software Foundation,
	Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307 USA
*/

#include <argp.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include <libintl.h>
#include <locale.h>

#include "version.h"
#include "ptouch.h"
#include "ptouch-render.h"

#define _(s) gettext(s)

#define P_NAME "ptouch-print"

struct arguments {
	align_type_t align;
	bool chain;
	bool precut;
	int copies;
	bool debug;
	bool info;
	bool invert;
	char *font_file;
	int font_size;
	int forced_tape_width;
	char *save_png;
	int verbose;
	int timeout;
	int line_spacing_percent; /* percent to scale ascender for inter-line spacing */
};

static error_t parse_opt(int key, char *arg, struct argp_state *state);

const char *argp_program_version = P_NAME " " VERSION;
const char *argp_program_bug_address = "Dominic Radermacher <dominic@familie-radermacher.ch>";
static char doc[] = "ptouch-print is a command line tool to print labels on Brother P-Touch printers on Linux.";

static struct argp_option options[] = {
	{ 0, 0, 0, 0, "options:", 1},
	{ "debug", 1, 0, 0, "Enable debug output", 1},
	{ "verbose", 'v', 0, 0, "Enable verbose output (same as --debug)", 1},
	{ "invert", 30, 0, 0, "Invert output (print white on black background)", 1},
	{ "font", 2, "<file>", 0, "Use font <file> or <name>", 1},
	{ "fontsize", 3, "<size>", 0, "Manually set font size", 1},
	{ "writepng", 4, "<file>", 0, "Instead of printing, write output to png <file>", 1},
	{ "force-tape-width", 5, "<px>", 0, "Set tape width in pixels, use together with --writepng without a printer connected", 1},
	{ "copies", 6, "<number>", 0, "Sets the number of identical prints", 1},
	{ "timeout", 7, "<seconds>", 0, "Set timeout waiting for finishing previous job. Default:1, 0 means infinity", 1},
	{ 0, 0, 0, 0, "print commands:", 2},
	{ "image", 'i', "<file>", 0, "Print the given image which must be a 2 color (black/white) png", 2},
	{ "text", 't', "<text>", 0, "Print line of <text>. If the text contains spaces, use quotation marks around it. \\n will be replaced by a newline", 2},
	{ "cutmark", 'c', 0, 0, "Print a mark where the tape should be cut", 2},
	{ "pad", 'p', "<n>", 0, "Add n pixels padding (blank tape)", 2},
	{ "chain", 10, 0, 0, "Skip final feed of label and any automatic cut", 2},
	{ "precut", 11, 0, 0, "Add a cut before the label (useful in chain mode for cuts with minimal waste)", 2},
	{ "newline", 'n', "<text>", 0, "Add text in a new line (up to 8 lines). \\n will be replaced by a newline", 2},
	{ "align", 'a', "<l|c|r>", 0, "Align text (when printing multiple lines)", 2},
	{ 0, 0, 0, 0, "other commands:", 3},
	{ "info", 20, 0, 0, "Show info about detected tape", 3},
	{ "list-supported", 21, 0, 0, "Show printers supported by this version", 3},
	{ "line-spacing", 31, "<percent>", 0, "Set line spacing percent (100 = asc, <100 reduces vertical spacing)", 3},
	{ 0 }
};

static struct argp argp = { options, parse_opt, NULL, doc, NULL, NULL, NULL };

struct arguments arguments = {
	.align = ALIGN_LEFT,
	.chain = false,
	.copies = 1,
	.debug = false,
	.info = false,
	.invert = false,
	.font_file = "Sans",
	.font_size = 0,
	.forced_tape_width = 0,
	.save_png = NULL,
	.verbose = 0,
	.timeout = 1,
	.line_spacing_percent = 85
};

static error_t parse_opt(int key, char *arg, struct argp_state *state)
{
	struct arguments *arguments = (struct arguments *)state->input;

	switch (key) {
		case 1: arguments->debug = true; break;
		case 2: arguments->font_file = arg; break;
		case 3: arguments->font_size = strtol(arg, NULL, 10); break;
		case 30: arguments->invert = true; break;
		case 4: arguments->save_png = arg; break;
		case 5: arguments->forced_tape_width = strtol(arg, NULL, 10); break;
		case 6: arguments->copies = strtol(arg, NULL, 10); break;
		case 7: arguments->timeout = strtol(arg, NULL, 10); break;
	case 'v': arguments->verbose++; break;
	case 31: arguments->line_spacing_percent = strtol(arg, NULL, 10); break;
		case 'i': add_job(JOB_IMAGE, 1, arg); break;
		case 't': add_text(state, arg, true); break;
		case 'c': add_job(JOB_CUTMARK, 0, NULL); break;
		case 'p': add_job(JOB_PAD, atoi(arg), NULL); break;
		case 10: arguments->chain = true; break;
		case 11: arguments->precut = true; break;
		case 'a':
			if ((strcmp(arg, "c") == 0) || (strcmp(arg, "center") == 0)) arguments->align = ALIGN_CENTER;
			else if ((strcmp(arg, "r") == 0) || (strcmp(arg, "right") == 0)) arguments->align = ALIGN_RIGHT;
			else if ((strcmp(arg, "l") == 0) || (strcmp(arg, "left") == 0)) arguments->align = ALIGN_LEFT;
			else arguments->align = ALIGN_LEFT;
			break;
		case 'n': add_text(state, arg, false); break;
		case 20: arguments->info = true; break;
		case 21: ptouch_list_supported(); exit(0);
		case ARGP_KEY_ARG: argp_failure(state, 1, E2BIG, _("No arguments supported")); break;
		case ARGP_KEY_END:
			if (arguments->forced_tape_width && !arguments->save_png) argp_failure(state, 1, ENOTSUP, _("Option --writepng missing"));
			if (arguments->forced_tape_width && arguments->info) argp_failure(state, 1, ENOTSUP, _("Options --force_tape_width and --info can't be used together"));
			break;
		default: return ARGP_ERR_UNKNOWN;
	}
	render_args.debug = arguments->debug || (arguments->verbose > 0);
	render_args.align = arguments->align;
	render_args.font_file = arguments->font_file;
	render_args.font_size = arguments->font_size;
	/* propagate line spacing percent CLI option */
	render_args.line_spacing_percent = arguments->line_spacing_percent;
	return 0;
}

int main(int argc, char *argv[])
{
	int print_width = 0;
	image_t *im = NULL, *out = NULL;
	ptouch_dev ptdev = NULL;

	setlocale(LC_ALL, "");
	bindtextdomain(P_NAME, "/usr/share/locale/");
	textdomain(P_NAME);

	/* Ensure AppKit/GNUstep backends are initialized for rendering */
	ensure_ns_application();

	argp_parse(&argp, argc, argv, 0, 0, &arguments);

	if (arguments.save_png && !arguments.info) {
		print_width = arguments.forced_tape_width ? arguments.forced_tape_width : 76;
	} else {
		if ((ptouch_open(&ptdev)) < 0) return 5;
		ptouch_init(ptdev);
		if (ptouch_getstatus(ptdev, arguments.timeout) != 0) return 1;
		print_width = ptouch_get_tape_width(ptdev);
		int max_print_width = ptouch_get_max_width(ptdev);
		if (print_width > max_print_width) print_width = max_print_width;
	}

	if (arguments.info) {
		printf(_("maximum printing width for this printer is %ldpx\n"), ptouch_get_max_width(ptdev));
		printf(_("maximum printing width for this tape is %ldpx\n"), ptouch_get_tape_width(ptdev));
		printf("media width = %d mm\n", ptdev->status->media_width);
		exit(0);
	}

	for (job_t *job = jobs; job != NULL; job = job->next) {
		switch (job->type) {
			case JOB_IMAGE:
				if ((im = image_load(job->lines[0])) == NULL) return 1;
				out = img_append(out, im);
				image_destroy(im); im = NULL;
				break;
			case JOB_TEXT:
				if ((im = render_text(arguments.font_file, job->lines, job->n, print_width)) == NULL) return 1;
				out = img_append(out, im);
				image_destroy(im); im = NULL;
				break;
			case JOB_CUTMARK:
				im = img_cutmark(print_width);
				out = img_append(out, im);
				image_destroy(im); im = NULL;
				break;
			case JOB_PAD:
				im = img_padding(print_width, job->n);
				out = img_append(out, im);
				image_destroy(im); im = NULL;
				break;
			default: break;
		}
	}

	if (out) {
		if (arguments.invert) invert_image(out);
		if (arguments.save_png) write_png(out, arguments.save_png);
		else {
			for (int i = 0; i < arguments.copies; ++i) {
				print_img(ptdev, out, arguments.chain, arguments.precut);
				ptouch_finalize(ptdev, (arguments.chain || (i < arguments.copies-1)));
			}
		}
		image_destroy(out);
	}
	if (!arguments.forced_tape_width) ptouch_close(ptdev);
	libusb_exit(NULL);
	return 0;
}
