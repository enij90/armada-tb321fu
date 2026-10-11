// SPDX-License-Identifier: GPL-3.0-or-later
/*
 * tb321fu-als-bridge: Lenovo TB321FU ambient light sensor (Qualcomm SSC,
 * read with libssc) into the kernel's tb321fu-als IIO device.
 *
 * Steam and iio-sensor-proxy read light from IIO sysfs; the SSC sensor has no
 * kernel driver, so each reading in lux goes to in_illuminance_input of the
 * IIO device under the tb321fu-als platform device (named "als", one of the
 * names Steam accepts). Readings that change by less than 1% (and 0.5 lux)
 * are skipped.
 */
#include <glob.h>
#include <math.h>
#include <signal.h>
#include <stdio.h>
#include <glib.h>
#include <glib-unix.h>
#include <libssc.h>

static char als_path[256];
static float last_lux = -1;

static gboolean find_iio_device(void)
{
	glob_t g;
	gboolean found = FALSE;

	if (glob("/sys/devices/platform/tb321fu-als/iio:device*", 0, NULL, &g))
		return FALSE;
	if (g.gl_pathc) {
		snprintf(als_path, sizeof(als_path), "%s/in_illuminance_input", g.gl_pathv[0]);
		found = TRUE;
	}
	globfree(&g);
	return found;
}

static void on_light(G_GNUC_UNUSED SSCSensorLight *sensor, gfloat lux,
		     G_GNUC_UNUSED gpointer user_data)
{
	FILE *f;

	if (!isfinite(lux) || lux < 0)
		return;
	if (last_lux >= 0 && fabsf(lux - last_lux) < fmaxf(0.5f, last_lux * 0.01f))
		return;

	f = fopen(als_path, "w");
	if (!f) {
		g_warning("%s: %m", als_path);
		return;
	}
	fprintf(f, "%.3f\n", lux);
	if (fclose(f) == 0)
		last_lux = lux;
}

static gboolean on_signal(gpointer loop)
{
	g_main_loop_quit(loop);
	return G_SOURCE_REMOVE;
}

int main(void)
{
	g_autoptr(GError) err = NULL;
	g_autoptr(GMainLoop) loop = g_main_loop_new(NULL, FALSE);

	if (!find_iio_device()) {
		g_printerr("tb321fu-als IIO device not found\n");
		return 1;
	}

	g_autoptr(SSCSensorLight) light = ssc_sensor_light_new_sync(NULL, &err);
	if (!light) {
		g_printerr("light sensor: %s\n", err ? err->message : "unknown error");
		return 1;
	}
	g_signal_connect(light, "measurement", G_CALLBACK(on_light), NULL);
	if (!ssc_sensor_light_open_sync(light, NULL, &err)) {
		g_printerr("open light sensor: %s\n", err ? err->message : "unknown error");
		return 1;
	}
	g_print("tb321fu-als-bridge: SSC light -> %s\n", als_path);

	g_unix_signal_add(SIGINT, on_signal, loop);
	g_unix_signal_add(SIGTERM, on_signal, loop);
	g_main_loop_run(loop);

	ssc_sensor_light_close_sync(light, NULL, NULL);
	return 0;
}
