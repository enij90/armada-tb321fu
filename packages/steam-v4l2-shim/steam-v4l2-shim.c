// SPDX-License-Identifier: MIT
//
// Steam Remote Play hardware decoding on V4L2 stateful decoders (Qualcomm iris).
//
// Steam's ARM streaming_client decodes through V4L2 and hands the frames to SDL
// with texture colorspace 0 (SDL_COLORSPACE_UNKNOWN), which SDL rejects for YUV
// textures ("Unsupported YUV colorspace"): Steam then falls back to software
// decoding. In streaming_client this library replaces that 0 with the colorspace
// the decoder reports on its capture queue.
//
// launch-steam preloads it into the native ARM Steam client. Steam restores
// streaming_client on every update, so the library cannot wrap that binary: it
// stays in LD_PRELOAD for the binaries in steamrtarm64/, which start
// streaming_client, and removes itself from every other process (games,
// compatibility tools).
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <linux/videodev2.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// SDL_DEFINE_COLORSPACE(SDL_COLOR_TYPE_YCBCR, range, primaries, transfer,
// matrix, SDL_CHROMA_LOCATION_CENTER)
#define SDL_YCBCR_COLORSPACE(range, prim, xfer, mat) \
	((2u << 28) | ((range) << 24) | (2u << 20) | ((prim) << 10) | ((xfer) << 5) | (mat))

// Used until the decoder has reported a format: BT.709 full range, what a
// Windows host streaming H.264 or HEVC declares.
#define DEFAULT_COLORSPACE SDL_YCBCR_COLORSPACE(2, 1, 1, 1)

static int (*real_ioctl)(int, unsigned long, ...);
static int active;
static volatile int have_fmt;
static volatile struct {
	unsigned colorspace, ycbcr_enc, quantization, xfer_func;
} fmt;

static void drop_from_ld_preload(const char *self)
{
	const char *cur = getenv("LD_PRELOAD");
	if (!cur || !self)
		return;
	char *copy = strdup(cur), *out = calloc(1, strlen(cur) + 1), *save = NULL;
	if (!copy || !out)
		goto done;
	for (char *tok = strtok_r(copy, ": ", &save); tok; tok = strtok_r(NULL, ": ", &save)) {
		if (strcmp(tok, self) == 0)
			continue;
		if (*out)
			strcat(out, ":");
		strcat(out, tok);
	}
	if (*out)
		setenv("LD_PRELOAD", out, 1);
	else
		unsetenv("LD_PRELOAD");
done:
	free(copy);
	free(out);
}

__attribute__((constructor)) static void init(void)
{
	real_ioctl = dlsym(RTLD_NEXT, "ioctl");

	char exe[PATH_MAX];
	ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
	if (n <= 0)
		return;
	exe[n] = '\0';
	char *base = strrchr(exe, '/');
	if (!base)
		return;
	*base++ = '\0';

	active = strcmp(base, "streaming_client") == 0;

	const char *dir = strrchr(exe, '/');
	if (!dir || strcmp(dir, "/steamrtarm64") != 0) {
		Dl_info info;
		if (dladdr((void *)init, &info))
			drop_from_ld_preload(info.dli_fname);
	}
}

int ioctl(int fd, unsigned long req, ...)
{
	va_list ap;
	va_start(ap, req);
	void *arg = va_arg(ap, void *);
	va_end(ap);

	if (!real_ioctl)
		real_ioctl = dlsym(RTLD_NEXT, "ioctl");
	int ret = real_ioctl(fd, req, arg);

	if (active && ret == 0 && (req == VIDIOC_G_FMT || req == VIDIOC_S_FMT)) {
		int err = errno;
		struct v4l2_format *f = arg;
		if (f->type == V4L2_BUF_TYPE_VIDEO_CAPTURE_MPLANE) {
			fmt.colorspace = f->fmt.pix_mp.colorspace;
			fmt.ycbcr_enc = f->fmt.pix_mp.ycbcr_enc;
			fmt.quantization = f->fmt.pix_mp.quantization;
			fmt.xfer_func = f->fmt.pix_mp.xfer_func;
			have_fmt = 1;
		} else if (f->type == V4L2_BUF_TYPE_VIDEO_CAPTURE) {
			fmt.colorspace = f->fmt.pix.colorspace;
			fmt.ycbcr_enc = f->fmt.pix.ycbcr_enc;
			fmt.quantization = f->fmt.pix.quantization;
			fmt.xfer_func = f->fmt.pix.xfer_func;
			have_fmt = 1;
		}
		errno = err;
	}
	return ret;
}

// V4L2 colorimetry -> SDL_Colorspace (SDL_pixels.h enum values).
static uint32_t decoder_colorspace(void)
{
	if (!have_fmt)
		return DEFAULT_COLORSPACE;

	unsigned cs = fmt.colorspace, enc = fmt.ycbcr_enc;
	unsigned quant = fmt.quantization, xfer = fmt.xfer_func;
	if (cs == V4L2_COLORSPACE_DEFAULT)
		cs = V4L2_COLORSPACE_REC709;
	if (enc == V4L2_YCBCR_ENC_DEFAULT)
		enc = V4L2_MAP_YCBCR_ENC_DEFAULT(cs);
	if (xfer == V4L2_XFER_FUNC_DEFAULT)
		xfer = V4L2_MAP_XFER_FUNC_DEFAULT(cs);
	if (quant == V4L2_QUANTIZATION_DEFAULT)
		quant = V4L2_MAP_QUANTIZATION_DEFAULT(0, cs, enc);

	unsigned range = quant == V4L2_QUANTIZATION_FULL_RANGE ? 2 : 1;

	unsigned prim;
	switch (cs) {
	case V4L2_COLORSPACE_SMPTE170M: prim = 6; break;
	case V4L2_COLORSPACE_470_SYSTEM_M: prim = 4; break;
	case V4L2_COLORSPACE_470_SYSTEM_BG: prim = 5; break;
	case V4L2_COLORSPACE_SMPTE240M: prim = 7; break;
	case V4L2_COLORSPACE_BT2020: prim = 9; break;
	default: prim = 1; break;
	}

	unsigned tf;
	switch (xfer) {
	case V4L2_XFER_FUNC_SRGB: tf = 13; break;
	case V4L2_XFER_FUNC_SMPTE240M: tf = 7; break;
	case V4L2_XFER_FUNC_SMPTE2084: tf = 16; break;
	case V4L2_XFER_FUNC_NONE: tf = 8; break;
	default: tf = 1; break;
	}

	unsigned mat;
	switch (enc) {
	case V4L2_YCBCR_ENC_601:
	case V4L2_YCBCR_ENC_XV601: mat = 6; break;
	case V4L2_YCBCR_ENC_BT2020: mat = 9; break;
	case V4L2_YCBCR_ENC_BT2020_CONST_LUM: mat = 10; break;
	case V4L2_YCBCR_ENC_SMPTE240M: mat = 7; break;
	default: mat = 1; break;
	}

	return SDL_YCBCR_COLORSPACE(range, prim, tf, mat);
}

// SDL3: bool SDL_SetNumberProperty(SDL_PropertiesID props, const char *name, Sint64 value)
_Bool SDL_SetNumberProperty(uint32_t props, const char *name, int64_t value)
{
	static _Bool (*real)(uint32_t, const char *, int64_t);
	static uint32_t reported;
	if (!real)
		real = dlsym(RTLD_NEXT, "SDL_SetNumberProperty");
	if (!real)
		return 0;

	if (active && value == 0 && name && strcmp(name, "SDL.texture.create.colorspace") == 0) {
		value = decoder_colorspace();
		if (value != reported) {
			reported = value;
			fprintf(stderr, "steam-v4l2-shim: texture colorspace 0 -> 0x%08x"
				" (V4L2 cs=%u ycbcr=%u quant=%u xfer=%u%s)\n", reported,
				fmt.colorspace, fmt.ycbcr_enc, fmt.quantization, fmt.xfer_func,
				have_fmt ? "" : ", no format yet");
		}
	}
	return real(props, name, value);
}
