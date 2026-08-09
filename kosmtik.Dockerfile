FROM debian:13-slim

ENV DEBIAN_FRONTEND=noninteractive

# Style dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    fonts-noto-cjk \
    fonts-noto-hinted \
    fonts-noto-unhinted \
    fonts-hanazono \
    fonts-unifont \
    python3 \
    python3-mapnik \
    python3-lxml \
    nodejs \
    npm \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

# Kosmtik with plugins, forcing prefix to /usr because bionic sets
# npm prefix to /usr/local, which breaks the install
RUN npm set prefix /usr && npm install -g kosmtik

WORKDIR /usr/lib/node_modules/kosmtik/
RUN kosmtik plugins --install kosmtik-overpass-layer \
                    --install kosmtik-fetch-remote \
                    --install kosmtik-overlay \
                    --install kosmtik-open-in-josm \
                    --install kosmtik-map-compare \
                    --install kosmtik-osm-data-overlay \
                    --install kosmtik-mapnik-reference \
                    --install kosmtik-geojson-overlay \
    && cp /root/.config/kosmtik.yml /tmp/.kosmtik-config.yml

# Closing section
RUN mkdir -p /map-it
WORKDIR /map-it
RUN cp /tmp/.kosmtik-config.yml .kosmtik-config.yml
ENV KOSMTIK_CONFIGPATH=".kosmtik-config.yml"

COPY style style

COPY scripts/generate/shields.py .
RUN chmod +x shields.py
RUN shields.py
RUN mv symbols style/symbols

COPY carto/map-it/project.mml .
COPY carto/map-it/styles.mss .
# Remove fancy placements because kosmtik does not support replacing contents of generated XML
RUN sed -i "s/--PLACEMENTS--//" styles.mss

CMD ["kosmtik", "serve", "project.mml", "--host", "0.0.0.0"]
