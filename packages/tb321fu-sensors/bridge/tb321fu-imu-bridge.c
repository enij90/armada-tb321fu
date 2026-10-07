// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * tb321fu-imu-bridge: Lenovo TB321FU accelerometer + gyroscope (Qualcomm SSC,
 * read with libssc) as an evdev motion device for InputPlumber.
 *
 * The uinput device "TB321FU IMU" reports the accelerometer on ABS_X/Y/Z and
 * the gyroscope on ABS_RX/RY/RZ, the layout of InputPlumber's imu_generic
 * capability map. InputPlumber multiplies these values by 0.01 and its Steam
 * Deck target expects accel in m/s^2 * 1632.65 and gyro in rad/s * 916.73
 * (src/input/source/iio/accel_gyro_3d.rs), so we write 100x those units.
 *
 * Axes are rotated from the sensor frame into the landscape game frame (see
 * accel_m/gyro_m); --accel-matrix / --gyro-matrix (row-major "a,b,c;d,e,f;g,h,i")
 * override them.
 */
#include <errno.h>
#include <fcntl.h>
#include <linux/uinput.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include <glib.h>
#include <glib-unix.h>
#include <libssc.h>

#define DEVICE_NAME "TB321FU IMU"
#define ACCEL_LSB_PER_MS2 (1632.6530612244898 * 100.0)
#define GYRO_LSB_PER_RADS (916.7324722093172 * 100.0)
#define AXIS_MAX 3276700 /* 100x the Deck's i16 range */

static int uinput_fd = -1;
/* Sensor frame -> Steam Deck frame (X right, Y up, Z toward the player) with
 * the tablet held in landscape, measured on the TB321FU (2026-10-06): pitch is
 * the sensor's Y axis, yaw its -X, roll its Z. A proper rotation, so the
 * accelerometer uses the same matrix. */
static double accel_m[9] = {0, 1, 0, -1, 0, 0, 0, 0, 1};
static double gyro_m[9] = {0, 1, 0, -1, 0, 0, 0, 0, 1};
static gboolean verbose;

static gboolean parse_matrix(const char *s, double m[9])
{
	double v[9];
	if (sscanf(s, "%lf,%lf,%lf;%lf,%lf,%lf;%lf,%lf,%lf",
		   &v[0], &v[1], &v[2], &v[3], &v[4], &v[5], &v[6], &v[7], &v[8]) != 9)
		return FALSE;
	memcpy(m, v, sizeof(v));
	return TRUE;
}

static int emit(int type, int code, int value)
{
	struct input_event ev = {.type = type, .code = code, .value = value};
	return write(uinput_fd, &ev, sizeof(ev)) == sizeof(ev) ? 0 : -1;
}

static int clamp_axis(double v)
{
	if (v > AXIS_MAX)
		return AXIS_MAX;
	if (v < -AXIS_MAX)
		return -AXIS_MAX;
	return (int)lround(v);
}

static void report(const double m[9], float x, float y, float z, double scale, int code0)
{
	double in[3] = {x, y, z};
	for (int i = 0; i < 3; i++) {
		double v = m[3 * i] * in[0] + m[3 * i + 1] * in[1] + m[3 * i + 2] * in[2];
		emit(EV_ABS, code0 + i, clamp_axis(v * scale));
	}
	emit(EV_SYN, SYN_REPORT, 0);
}

static void on_accel(SSCSensorAccelerometer *s, gfloat x, gfloat y, gfloat z, gpointer data)
{
	if (verbose)
		g_print("accel %f %f %f\n", x, y, z);
	report(accel_m, x, y, z, ACCEL_LSB_PER_MS2, ABS_X);
}

static void on_gyro(SSCSensorGyroscope *s, gfloat x, gfloat y, gfloat z, gpointer data)
{
	if (verbose)
		g_print("gyro %f %f %f\n", x, y, z);
	report(gyro_m, x, y, z, GYRO_LSB_PER_RADS, ABS_RX);
}

static int setup_uinput(void)
{
	struct uinput_setup setup = {0};
	int fd = open("/dev/uinput", O_WRONLY | O_NONBLOCK | O_CLOEXEC);
	if (fd < 0)
		return -1;
	/* A motion sensor, not a joystick: keeps joydev, udev's joystick
	 * classification and Steam away from it. */
	if (ioctl(fd, UI_SET_PROPBIT, INPUT_PROP_ACCELEROMETER) < 0)
		goto fail;
	if (ioctl(fd, UI_SET_EVBIT, EV_ABS) < 0)
		goto fail;
	for (int code = ABS_X; code <= ABS_RZ; code++) {
		struct uinput_abs_setup abs = {
			.code = code,
			.absinfo = {.minimum = -AXIS_MAX, .maximum = AXIS_MAX},
		};
		if (ioctl(fd, UI_SET_ABSBIT, code) < 0 || ioctl(fd, UI_ABS_SETUP, &abs) < 0)
			goto fail;
	}
	setup.id.bustype = BUS_VIRTUAL;
	setup.id.vendor = 0x17ef; /* Lenovo */
	setup.id.product = 0x321f;
	g_strlcpy(setup.name, DEVICE_NAME, sizeof(setup.name));
	if (ioctl(fd, UI_DEV_SETUP, &setup) < 0 || ioctl(fd, UI_DEV_CREATE) < 0)
		goto fail;
	return fd;
fail:
	close(fd);
	return -1;
}

static gboolean on_signal(gpointer loop)
{
	g_main_loop_quit(loop);
	return G_SOURCE_REMOVE;
}

int main(int argc, char **argv)
{
	g_autofree char *accel_s = NULL, *gyro_s = NULL;
	g_autoptr(GError) err = NULL;
	GOptionEntry entries[] = {
		{"accel-matrix", 0, 0, G_OPTION_ARG_STRING, &accel_s, "Accelerometer rotation", "a,b,c;d,e,f;g,h,i"},
		{"gyro-matrix", 0, 0, G_OPTION_ARG_STRING, &gyro_s, "Gyroscope rotation", "a,b,c;d,e,f;g,h,i"},
		{"verbose", 'v', 0, G_OPTION_ARG_NONE, &verbose, "Print every sample", NULL},
		{NULL}};
	g_autoptr(GOptionContext) ctx = g_option_context_new("- TB321FU IMU to evdev bridge");
	g_option_context_add_main_entries(ctx, entries, NULL);
	if (!g_option_context_parse(ctx, &argc, &argv, &err)) {
		g_printerr("%s\n", err->message);
		return 2;
	}
	if ((accel_s && !parse_matrix(accel_s, accel_m)) || (gyro_s && !parse_matrix(gyro_s, gyro_m))) {
		g_printerr("matrices are 9 numbers: a,b,c;d,e,f;g,h,i\n");
		return 2;
	}

	/* Open the sensors first: at boot the SSC may not be up yet, and systemd
	 * restarts us; no half-initialized uinput device meanwhile. */
	g_autoptr(SSCSensorAccelerometer) accel = ssc_sensor_accelerometer_new_sync(NULL, &err);
	if (!accel) {
		g_printerr("accelerometer: %s\n", err->message);
		return 1;
	}
	g_autoptr(SSCSensorGyroscope) gyro = ssc_sensor_gyroscope_new_sync(NULL, &err);
	if (!gyro) {
		g_printerr("gyroscope: %s\n", err->message);
		return 1;
	}

	uinput_fd = setup_uinput();
	if (uinput_fd < 0) {
		g_printerr("uinput: %s\n", g_strerror(errno));
		return 1;
	}

	g_signal_connect(accel, "measurement", G_CALLBACK(on_accel), NULL);
	g_signal_connect(gyro, "measurement", G_CALLBACK(on_gyro), NULL);
	if (!ssc_sensor_accelerometer_open_sync(accel, NULL, &err) ||
	    !ssc_sensor_gyroscope_open_sync(gyro, NULL, &err)) {
		g_printerr("opening sensors: %s\n", err->message);
		return 1;
	}
	g_print("streaming accelerometer + gyroscope to \"%s\"\n", DEVICE_NAME);

	g_autoptr(GMainLoop) loop = g_main_loop_new(NULL, FALSE);
	g_unix_signal_add(SIGTERM, on_signal, loop);
	g_unix_signal_add(SIGINT, on_signal, loop);
	g_main_loop_run(loop);

	ssc_sensor_gyroscope_close_sync(gyro, NULL, NULL);
	ssc_sensor_accelerometer_close_sync(accel, NULL, NULL);
	ioctl(uinput_fd, UI_DEV_DESTROY);
	close(uinput_fd);
	return 0;
}
