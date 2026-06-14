FROM debian:13-slim as generation

ENV DEBIAN_FRONTEND noninteractive

RUN mkdir -p /generation
WORKDIR /generation
ENV PATH $PATH:/generation

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-lxml \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

COPY scripts/placements.py .
RUN chmod +x placements.py
RUN placements.py > placements.xml

COPY scripts/generate/shields.py .
RUN chmod +x shields.py
RUN shields.py

FROM node:24-trixie-slim as build

RUN mkdir -p /build
WORKDIR /build
ENV PATH $PATH:/build

RUN npm install -g carto

COPY --from=generation /generation/placements.xml placements.xml
COPY carto/map-it/project.mml .
COPY carto/map-it/styles.mss .

# Generate Mapnik XML using Carto
RUN carto project.mml > mapnik.xml

# The CDATA tags are stripped of symbolizers where <Placement/> tags are inserted from placements.xml
# Also see https://github.com/mapbox/carto/issues/238#issuecomment-19673987
RUN sed -i -E "s@<!\[CDATA\[(.*)--PLACEMENTS--]]>@\1$(cat placements.xml)@g" mapnik.xml

FROM debian:13-slim

ENV DEBIAN_FRONTEND noninteractive

LABEL maintainer="Hidde Wieringa <hidde@hiddewieringa.nl>"

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-mapnik \
    python3-pypdf \
    curl \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    fonts-hanazono \
    fonts-unifont \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

RUN mkdir /map-it
WORKDIR /map-it
ENV PATH $PATH:/map-it

ENV MAPNIK_CONFIGURATION mapnik.xml

RUN mkdir -p style
COPY --from=generation /generation/symbols/shields style/symbols/shields
COPY --from=build /build/mapnik.xml mapnik.xml
COPY scripts/environment.py .
COPY scripts/bounds.py .
COPY scripts/generate.py .
COPY scripts/legend.sh .
COPY scripts/with_mapnik_environment.sh .
COPY scripts/tiles.py .
COPY scripts/tiles.sh .
COPY style style

RUN chmod +x \
    with_mapnik_environment.sh \
    bounds.py \
    generate.py \
    legend.sh \
    tiles.py \
    tiles.sh

CMD ["with_mapnik_environment.sh", "generate.py"]
