FROM debian:13-slim

LABEL maintainer="Hidde Wieringa <hidde@hiddewieringa.nl>"

WORKDIR /map-it
ENV PATH=$PATH:/map-it

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3-mapnik \
    && rm -rf /var/lib/apt/lists/* && apt-get clean

COPY scripts/environment.py .
COPY scripts/bounds.py .

RUN chmod +x bounds.py

CMD ["bounds.py"]
