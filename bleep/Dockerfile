FROM ubuntu:24.04

ARG BLEEP_REVISION
ENV DEBIAN_FRONTEND=noninteractive \
    BLEEP_DB_PATH=/home/bleep/.bleep/observations.db

RUN apt-get update && apt-get install -y --no-install-recommends \
        bluez \
        libbluetooth3 \
        libbluetooth-dev \
        bluez-obexd \
        bluez-alsa-utils \
        alsa-utils \
        sox \
        ca-certificates \
        dbus \
        git \
        openssh-server \
        procps \
        python3 \
        python3-dev \
        python3-gi \
        python3-gi-cairo \
        python3-pip \
        python3-venv \
        pkg-config \
        build-essential \
        cmake \
        libdbus-1-dev \
        gir1.2-glib-2.0 \
        gir1.2-gstreamer-1.0 \
        gir1.2-gst-plugins-base-1.0 \
        libgirepository1.0-dev \
        libgirepository-2.0-dev \
        libcairo2-dev \
        gstreamer1.0-tools \
        gstreamer1.0-alsa \
        gstreamer1.0-plugins-base \
        gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad \
        gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /run/sshd /etc/ssh/sshd_config.d

RUN test -n "$BLEEP_REVISION" \
    && git clone --depth 1 https://github.com/Mauddib28/bleep-tool.git /opt/bleep \
    && test "$(git -C /opt/bleep rev-parse HEAD)" = "$BLEEP_REVISION"

COPY patches/db-report-stdout.patch /tmp/db-report-stdout.patch
RUN git -C /opt/bleep apply /tmp/db-report-stdout.patch \
    && rm /tmp/db-report-stdout.patch

COPY patches/sdp-source-stdout.patch /tmp/sdp-source-stdout.patch
RUN git -C /opt/bleep apply /tmp/sdp-source-stdout.patch \
    && rm /tmp/sdp-source-stdout.patch

COPY patches/classic-hostnet.patch /tmp/classic-hostnet.patch
RUN git -C /opt/bleep apply /tmp/classic-hostnet.patch \
    && rm /tmp/classic-hostnet.patch

COPY patches/sdp-continue.patch /tmp/sdp-continue.patch
RUN git -C /opt/bleep apply /tmp/sdp-continue.patch \
    && rm /tmp/sdp-continue.patch

WORKDIR /opt/bleep

RUN pip install --break-system-packages -e . \
    && ln -sfn "$(command -v bleep)" /usr/bin/bleep

LABEL org.opencontainers.image.title="bleep" \
      org.opencontainers.image.source="https://github.com/Mauddib28/bleep-tool" \
      org.opencontainers.image.revision="${BLEEP_REVISION}"

RUN useradd --create-home --uid 10001 --gid bluetooth --shell /bin/bash bleep \
    && printf 'BLEEP_DB_PATH=/home/bleep/.bleep/observations.db\n' >> /etc/environment

COPY sshd-bleep.conf /etc/ssh/sshd_config.d/bleep.conf
COPY entrypoint.sh /usr/local/sbin/bleep-entrypoint
RUN chmod 755 /usr/local/sbin/bleep-entrypoint

COPY hostnet/bleep-hostnetd /usr/local/sbin/bleep-hostnetd
COPY hostnet/bleep-hostnet-client /usr/local/lib/bleep-hostnet-client
COPY hostnet/sdptool /usr/local/bin/sdptool
COPY hostnet/l2ping /usr/local/bin/l2ping
RUN chmod 755 /usr/local/sbin/bleep-hostnetd /usr/local/lib/bleep-hostnet-client \
        /usr/local/bin/sdptool /usr/local/bin/l2ping

ENTRYPOINT ["/usr/local/sbin/bleep-entrypoint"]
