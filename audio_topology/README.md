# Audio Topology

Source files for Armada's Qualcomm AudioReach topology blobs.

Only the generated topology blobs under the following directory are copied into
the firmware image; the `.m4` sources remain in this directory.

```text
system_files/usr/lib/firmware/qcom/<soc>/
```

To regenerate a topology using [audioreach-topology](https://git.codelinaro.org/linaro/qcomlt/audioreach-topology):

```sh
m4 -I <audioreach-topology> sm8750/SM8750-AYN.m4 > SM8750-AYN.conf
alsatplg -c SM8750-AYN.conf -o SM8750-AYN-tplg.bin
```

Replace the corresponding `-tplg.bin` in `system_files` after regeneration.

The Duo source, `eliza/ELIZA-RetroidPocket-I2S.m4`, comes from
[Retroid's topology tree](https://github.com/RetroidPocket/audioreach-topology/tree/2c2f735ae853e450ea50142435a6585c32711509).
Its two speaker format declarations change from `S16_LE` to `S32_LE`;
the headphone and microphone paths are unchanged. Speaker output was confirmed
on the Duo after a clean boot with kernel patches 1179–1180 on 2026-10-22.
Ship the updated topology and both kernel patches together; updating only the
kernel package does not replace the topology supplied by the system image.

Use that pinned checkout for its macro dependencies:

```sh
m4 -I <retroid-audioreach-topology> eliza/ELIZA-RetroidPocket-I2S.m4 > ELIZA-RetroidPocket-I2S.conf
alsatplg -c ELIZA-RetroidPocket-I2S.conf -o ELIZA-RetroidPocket-I2S-tplg.bin
```
