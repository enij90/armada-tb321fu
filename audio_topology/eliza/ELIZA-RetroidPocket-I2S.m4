# Copyright, Teguh Sobirin, 2026
# SPDX-License-Identifier: BSD-3-Clause
#
# Eliza (rpduo) topology:
#   MultiMedia1 playback -> Primary MI2S RX    (AW88166 speaker)
#   MultiMedia2 playback -> Quaternary MI2S RX (ES8326 headphone, SD0)
#   MultiMedia3 capture  <- Quaternary MI2S TX (ES8326 mic / jack, SD1)
#   MultiMedia4 capture  <- VA_CODEC_DMA_TX_0  (on-board DMIC via LPASS VA macro)
#
include(`audioreach/audioreach.m4')
include(`audioreach/stream-subgraph.m4')
include(`audioreach/device-subgraph.m4')
include(`util/route.m4')
include(`util/mixer.m4')
include(`audioreach/tokens.m4')
#
# Stream SubGraphs
#
dnl Playback MultiMedia1 (speaker)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA1,
	`S32_LE', 48000, 48000, 2, 2,
	0x00004001, 0x00004001, 0x00006001, `110000')
dnl Playback MultiMedia2 (headphone)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-vol-playback.m4, FRONTEND_DAI_MULTIMEDIA2,
	`S16_LE', 48000, 48000, 2, 2,
	0x00004002, 0x00004002, 0x00006010, `110000')
dnl Capture MultiMedia3 (ES8326 mic / jack)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA3,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004003, 0x00004003, 0x00006020, `110000')
dnl Capture MultiMedia4 (on-board DMIC via VA macro)
STREAM_SG_PCM_ADD(audioreach/subgraph-stream-capture.m4, FRONTEND_DAI_MULTIMEDIA4,
	`S16_LE', 48000, 48000, 1, 2,
	0x00004011, 0x00004011, 0x00006100, `110000')
#
# Device SubGraphs
#
dnl Primary MI2S RX (AW88166 speaker) - main TLMM i2s0, SD0
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `Primary', PRIMARY_MI2S_RX,
	`S32_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_LPAIF, I2S_INTF_TYPE_PRIMARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
	0x00004004, 0x00004004, 0x00006030, `PRIMARY_MI2S_RX')
dnl Quaternary MI2S RX (ES8326 playback) - LPI i2s0, SD0 = ASDIN
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-playback.m4, `Quaternary', QUATERNARY_MI2S_RX,
	`S16_LE', 48000, 48000, 2, 2,
	LPAIF_INTF_TYPE_RXTX, I2S_INTF_TYPE_PRIMARY, SD_LINE_IDX_I2S_SD0, DATA_FORMAT_FIXED_POINT,
	0x00004005, 0x00004005, 0x00006050, `QUATERNARY_MI2S_RX')
dnl Quaternary MI2S TX (ES8326 capture) - LPI i2s0, SD1 = gpio3 ADC data-out
DEVICE_SG_ADD(audioreach/subgraph-device-i2s-capture.m4, `Quaternary', QUATERNARY_MI2S_TX,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_RXTX, I2S_INTF_TYPE_PRIMARY, SD_LINE_IDX_I2S_SD1, DATA_FORMAT_FIXED_POINT,
	0x00004006, 0x00004006, 0x00006070, `QUATERNARY_MI2S_TX', `QUATERNARY_MI2S_TX')
dnl VA_CODEC_DMA_TX_0 (on-board DMIC capture via VA macro)
DEVICE_SG_ADD(audioreach/subgraph-device-codec-dma-capture.m4, `VA_CODEC_DMA_TX_0', VA_CODEC_DMA_TX_0,
	`S16_LE', 48000, 48000, 1, 2,
	LPAIF_INTF_TYPE_VA, CODEC_INTF_IDX_TX0, 0, DATA_FORMAT_FIXED_POINT,
	0x00004012, 0x00004012, 0x00006120)
#
# Mixers / Routes
#
STREAM_DEVICE_PLAYBACK_MIXER(PRIMARY_MI2S_RX, ``PRIMARY_MI2S_RX'', ``MultiMedia1'')
STREAM_DEVICE_PLAYBACK_MIXER(QUATERNARY_MI2S_RX, ``QUATERNARY_MI2S_RX'', ``MultiMedia2'')
dnl
STREAM_DEVICE_PLAYBACK_ROUTE(PRIMARY_MI2S_RX, ``PRIMARY_MI2S_RX Audio Mixer'', ``MultiMedia1, stream0.logger1'')
STREAM_DEVICE_PLAYBACK_ROUTE(QUATERNARY_MI2S_RX, ``QUATERNARY_MI2S_RX Audio Mixer'', ``MultiMedia2, stream1.logger1'')
dnl
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA3, ``QUATERNARY_MI2S_TX'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA3, ``MultiMedia3 Mixer'', ``QUATERNARY_MI2S_TX, device23.logger1'')
dnl
STREAM_DEVICE_CAPTURE_MIXER(FRONTEND_DAI_MULTIMEDIA4, ``VA_CODEC_DMA_TX_0'')
STREAM_DEVICE_CAPTURE_ROUTE(FRONTEND_DAI_MULTIMEDIA4, ``MultiMedia4 Mixer'', ``VA_CODEC_DMA_TX_0, device110.logger1'')
