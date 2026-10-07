# This package's stage lives in its own Containerfile: package-hash.sh hashes
# packages/Containerfile whole, so a stage there would rebuild every package.
# Same contract as the stages there; the build context is packages/.

ARG BUILDER_IMAGE

FROM ${BUILDER_IMAGE} AS pkg-tb321fu-sensors
COPY toolchain.env scrub-scratch.sh /src/
COPY tb321fu-sensors/ /work/
WORKDIR /work
RUN ./build.sh && /src/scrub-scratch.sh

FROM scratch AS out-tb321fu-sensors
COPY --from=pkg-tb321fu-sensors /work/out/ /rpms/
