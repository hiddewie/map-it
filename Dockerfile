FROM ubuntu:18.04

LABEL maintainer="Hidde Wieringa <hidde@hiddewieringa.nl>"

RUN apt-get update && apt-get install -y \
    # aufs-tools \
    # automake \
    # build-essential \
    python-mapnik \
    python-cairo \
    libmapnik2-2.0 \
    mapnik-utils \
    # mapnik \
    # libmapnik-dev \
    # all\
    # your\
    # other\
    # packages \
    python \
  && apt-get autoclean \
  && rm -rf /var/lib/apt/lists/*

# RUN mapnik-config -v

RUN mkdir /map-it
WORKDIR /map-it

# Database config
ENV PG_HOST postgres-osm
# COPY ./countries.txt ./coutries.txt
ENV PG_PORT 5432
ENV PG_USER postgres
ENV PG_PASSWORD ""

# you might have to update your outdated clang
# RUN add-apt-repository -y ppa:ubuntu-toolchain-r/test
# RUN apt-get update -y
# RUN apt-get install -y gcc-6 g++-6 clang-3.8
# RUN export CXX="clang++-3.8" && export CC="clang-3.8"

# # install mapnik
# RUN git clone https://github.com/mapnik/mapnik mapnik -b 2.3.x --depth 10
# RUN cd mapnik
# RUN git submodule update --init
# RUN apt-get install python zlib1g-dev clang make pkg-config curl
# RUN source bootstrap.sh
# RUN ./configure CUSTOM_CXXFLAGS="-D_GLIBCXX_USE_CXX11_ABI=0" CXX=${CXX} CC=${CC}
# RUN make
# RUN make test
# RUN make install

CMD ["/usr/bin/python", "./generate.py"]