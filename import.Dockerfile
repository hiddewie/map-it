FROM debian:13-slim AS compilation

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgdal-dev \
    build-essential \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

RUN mkdir -p /compilation
WORKDIR /compilation

COPY scripts/isolation.c .
RUN gcc isolation.c -Wall -o isolation -lgdal -lm -O2

FROM debian:13-slim AS generation

ENV DEBIAN_FRONTEND noninteractive

RUN mkdir -p /generation
WORKDIR /generation
ENV PATH $PATH:/generation

RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    python3 \
    python3-lxml \
    python3-pip \
    && pip3 install --no-cache-dir --break-system-packages pyyaml \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

COPY legend/legend.yaml .
COPY scripts/generate/legend.py .
RUN chmod +x legend.py
RUN legend.py legend.yaml > legend.osm

FROM debian:13-slim

LABEL maintainer="Hidde Wieringa <hidde@hiddewieringa.nl>"

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        wget \
        unzip \
        gdal-bin \
        osm2pgsql \
        postgresql-client \
        postgis \
        python3-gdal \
        python3-bs4 \
        python3-lxml \
        libboost-dev \
        libgdal-dev \
        osmium-tool \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# Install phyghtmap
COPY scripts/phyghtmap /usr/lib/phyghtmap
RUN ln -s /usr/lib/phyghtmap/main.py /usr/bin/phyghtmap
RUN chmod +x /usr/lib/phyghtmap/main.py

RUN mkdir -p /data
RUN mkdir -p /style
RUN mkdir -p /script
ENV PATH $PATH:/script

WORKDIR /data

COPY --from=compilation /compilation/isolation /script
COPY --from=generation /generation/legend.osm /legend/legend.osm
COPY style/map-it.style /script/map-it.style
COPY scripts/download.sh /script/download.sh
COPY style/shade /style/shade
RUN chmod +x /script/download.sh

CMD ["download.sh"]
