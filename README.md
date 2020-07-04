
## Generating a custom cycling map with Mapnik and Carto

View blogpost at https://dev.to/hiddewie/creating-a-custom-cycling-map-3g2a.

## Getting started

There are three scripts in this repository:
- `download.sh`

  Downloads the required data into a Postgres database for the map.
- `generate.py`

  A Python script which will generate the map for a Mapnik configuration. The Mapnik configuration can be generated by running
  Carto against `project.mml`.
- `bounds.py`

  A Python script which will output a list of bounding boxes that will fit the configured page size and bounding box perfectly.
  
See the environment variables which can be configured for the scripts below.

### Manually

Make sure you have a running Postgres database, with a `gis` schema with GIS extensions enabled.

Run the command
```bash
./download.sh
```
to download the data and insert it into the database. Make sure that the environment variables listed below are set.

Run the command 
```bash
carto project.mml > mapnik.xml
./generate.py mapnik.xml
```
to generate the Mapnik XML configuration using Carto and the printable PDF map in the folder `output`. Make sure that the environment variables listed below are set.

### Using Docker

#### Database

Start a database with GIS extensions enabled using the image `openfirmware/postgres-osm`
```bash
docker run -d --name postgres-osm openfirmware/postgres-osm
```

#### Map bounds

Determine the bounding box of the region you want to print. The tool [Geofabrik tool](https://tools.geofabrik.de/calc/#type=geofabrik_standard&bbox=0.110816,47.68199,9.943825,55.331672&tab=2) can be used to choose coordinates on a map. The bounding box will be used to determine the number of pages to print. If everything fits on one page (of the configured paper size) then padding is added until the page is filled exactly. If the content needs more than one page, then multiple tiled pages are generated to cover the bounding box area, with the configured page overlap (5% by default).

To assist with finding the correct bounding boxes that will fit exactly on a page of the correct size, the following script container can be used. The output will contain the bounding boxes for each page that will be generated. These values can be used for other commands. 
```bash
docker run \ 
  -ti \
  --rm \
  -e BBOX="6.2476:52.2157:6.9457:52.4531" \
  -e PAPER_SIZE="A2" \
  -e PAGE_OVERLAP="5%" \
  -e PAPER_ORIENTATION="landscape" \
  -e SCALE="1:150000" \
  hiddewie/map-it-bounds
```

(You can also build it yourself using `docker build -t map-it-bounds -f bounds.Dockerfile .`)

#### Data download & import

Make sure you have created an account [U.S. Geological Survey](https://www.usgs.gov/). The USGS service is used to download terrain height information in high resolution.

Then, download and import the data of the map using the docker image `hiddewie/map-it-import` [![](https://images.microbadger.com/badges/image/hiddewie/map-it-import.svg)](https://hub.docker.com/r/hiddewie/map-it-import). Map the data directory of this project to the container. Some files are downloaded there that are used for shading the map. Run it using
```bash
docker run \
  -ti \
  --rm \
  -v $PROJECT_DIR/data:/data \
  --link postgres-osm:postgres-osm \
  -e PG_HOST=postgres-osm \
  -e PG_PORT=5432 \
  -e PG_USER="osm" \
  -e PG_PASSWORD="" \
  -e PG_DATABASE="gis" \
  -e USGS_USERNAME="$USGS_USERNAME" \
  -e USGS_PASSWORD="$USGS_PASSWORD" \
  -e FEATURE_COUNTRIES="europe/netherlands/overijssel" \
  -e BBOX="6.2476:52.2157:6.9457:52.4531" \
  hiddewie/map-it-import
```
where `$PROJECT_DIR` is the project directory and `$USGS_USERNAME` and `$USGS_PASSWORD` are credentials for the [U.S. Geological Survey](https://www.usgs.gov/).

(You can also build it yourself using `docker build -t map-it-import -f import.Dockerfile .`)

#### Map 

Let's generate a map. Use the image `hiddewie/map-it` [![](https://images.microbadger.com/badges/image/hiddewie/map-it.svg)](https://hub.docker.com/r/hiddewie/map-it) and run it using 
```bash
docker run \
  -ti \
  --rm \
  -v $PROJECT_DIR/data:/map-it/data \
  -v $PROJECT_DIR/output:/map-it/output \
  --link postgres-osm:postgres-osm \
  -e PG_HOST=postgres-osm \
  -e PG_PORT=5432 \
  -e PG_USER="osm" \
  -e PG_PASSWORD="" \
  -e PG_DATABASE="gis" \
  -e MAP_NAME="map" \
  -e BBOX="6.2476:52.2157:6.9457:52.4531" \
  -e SCALE="1:150000" \
  -e PAPER_SIZE="A2" \
  -e PAPER_ORIENTATION="landscape" \
  -e PAGE_OVERLAP="5%" \
  hiddewie/map-it
```

The map will be written to the mapped volume in the `/output` directory. The mapnik XML config will also be written there.

The bounding box does not need to fit perfectly on one page. If it does not, padding will be added or multiple pages will be generated.

(You can also build it yourself using `docker build -t map-it .`)

### Script parameters

The lists below describe the parameters used for the scripts, including defaults.

#### Import script

- `PG_HOST` (default `localhost`)
  
  The Postgres database host
- `PG_PORT` (default `5432`)
  
  The Postgres database port
- `PG_USER` (default `osm`)
  
  The Postgres database user
- `PG_PASSWORD` (default empty)
  
  The Postgres database password
- `PG_DATABASE` (default `gis`)
  
  The Postgres database host
- `FEATURE_COUNTRIES` (required, default empty)
  
  Countries that will be downloaded from [GeoFabrik](http://download.geofabrik.de/). Separated by whitespace. For example `europe/netherlands/overijssel europe/slovakia europe/poland/slaskie europe/poland/malopolskie`.
- `USGS_USERNAME` and `USGS_PASSWORD` (required, default empty)
  
  Create an account for accessing [U.S. Geological Survey](https://www.usgs.gov/) for terrain information. This can be done for free [here](https://store.usgs.gov/user/register). Set the credentials in these environment variables.
  
  The [phyghtmap](http://katze.tfiu.de/projects/phyghtmap/phyghtmap.1.html) tool is used for downloading terrain information.
- `BBOX` (required, default empty)
  
  Of the form `A:B:C:D`, for example `5.3:51.1:6.8:53.0056` where `(A, B)` is the lower left corner of the bounding box and `(C, D)` is the top right corner. Specify in longitude - latitude order in the [EPSG:4326](https://epsg.io/4326) coordinate system.

Optional extra parameters for tweaking the import of downloaded OpenStreetMap data into the database:

- `OSM2PGSQL_CACHE` (default `1024`)

  The cache size in mega bytes that the import script may use.
- `OSM2PGSQL_NUMPROC` (default `4`)

  The number of processes that import script may use.

#### Map generation & bounding box script

- `PG_HOST` (default `localhost`)
  
  The Postgres database host
- `PG_PORT` (default `5432`)
  
  The Postgres database port
- `PG_USER` (default `osm`)
  
  The Postgres database user
- `PG_PASSWORD` (default empty)
  
  The Postgres database password
- `PG_DATABASE` (default `gis`)
  
  The Postgres database host
- `MAP_NAME` (default `map`)
  
  The name of the map. Used for generating filenames. Existing files will be overwritten. The filename will be suffixed with the index of the generated page if more than one page is generated because the bounding box area does not fit on one page. 
- `BBOX` (required, default empty)
  
  Of the form `A:B:C:D`, for example `5.3:51.1:6.8:53.0056` where `(A, B)` is the lower left corner of the bounding box and `(C, D)` is the top right corner. Specify in longitude - latitude order in the [EPSG:4326](https://epsg.io/4326) coordinate system.

- `SCALE` (default `1:150000`)
  
  The scale of the map, when printed on the indicated paper size. The value is of the form `1:N` with `N` a number.
- `PAPER_ORIENTATION` (default `portrait`)
  
  The orientation of the generated page. Valid values: `portrait` and `landscape`.
- `PAPER_SIZE` (default `A4`)
  
  The size of the generated page. Valid values: `A0`, `A1`, `A2`, `A3` and `A4`, or any value of the form `A mm x B mm` (millimeters), `A in x B in` (inches) or `A m x B m` (meters) with `A` and `B` numeric values. For example `A1`, `10 mm x 100 mm` or `20 in x 5 in`.
- `PAGE_OVERLAP` (default `5%`)
  
  A percentage of the form '5%' or '10.1%'. The percentage of each page is taken on all four sides of the paper as padding. When multiple pages are generated the padding will cause overlap between the pages. 

### Examples

[Example PDF Output](https://github.com/hiddewie/map-it/releases/download/v1.0.0/output.pdf)

![Expected output](assets/cover.jpg)

![Printed map](assets/printed.jpg)
