#!/usr/bin/env bash

set -o pipefail

DATA_DIR=/data
STYLE_DIR=/style

python -V
gdalinfo --version
osm2pgsql --version
psql --version | grep psql
osmium --version | grep version
echo -n "shp2pgsql " && shp2pgsql | grep RELEASE

if [[ ! -v USGS_USERNAME ]]; then
  echo "Set the environment variable USGS_USERNAME"
  exit 1
fi
if [[ ! -v USGS_PASSWORD ]]; then
  echo "Set the environment variable USGS_PASSWORD"
  exit 1
fi
if [[ ! -v BBOX ]]; then
  echo "Set the environment variable BBOX"
  exit 1
fi

echo "Using USGS username '$USGS_USERNAME'"
echo "Using feature countries '$FEATURE_COUNTRIES'"
echo "Using bounding box '$BBOX'"
echo

PGPASSWORD="$PG_PASSWORD"
POSTGRES_ARGS="-h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE""

mkdir -p $DATA_DIR

echo
echo " -- Height, contours & shade -- "
echo

mkdir -p $DATA_DIR/dem

echo "Downloading height data for bounding box $BBOX"

# Revert to
#  --srtm=1 \
#  --srtm-version=3.0 \
# when downloading of SRTM 3.0 works again
phyghtmap --download-only \
  --source=view3 \
  --earthexplorer-user=$USGS_USERNAME \
  --earthexplorer-password=$USGS_PASSWORD \
  --hgtdir=$DATA_DIR/dem \
  --area $BBOX \
  | tee downloaded.txt \
  || exit 1

FILES=$(cat downloaded.txt | grep -oP 'using (existing )?file \K.*' | sed 's/\.$//' | uniq | xargs)

echo "Done downloading height data"
echo "Found downloaded files: $FILES"

echo "Merge height data for combination into one height file"
rm -f combined.hgt || exit 1
gdal_merge.py -o $DATA_DIR/combined.hgt -n -32767 -a_nodata -32767 -of GTiff $FILES || exit 1
echo "Done merging height data"

gdalinfo $DATA_DIR/combined.hgt

echo "Contours"
rm -f $DATA_DIR/combined.shp || exit 1
gdal_contour -i 25 -snodata -32767 -a height $DATA_DIR/combined.hgt $DATA_DIR/combined.shp || exit 1

ARGS="-I -d"
echo "Import contours"
shp2pgsql $ARGS -g way -s 4326 $DATA_DIR/combined.shp contours | psql $POSTGRES_ARGS | grep -v 'INSERT' || exit 1

echo "Shade"
rm -f $DATA_DIR/combined.tif || exit 1
gdaldem hillshade -s 111120 -compute_edges $DATA_DIR/combined.hgt $DATA_DIR/combined.raw.tif || exit 1
gdaldem color-relief combined.raw.tif -alpha $STYLE_DIR/shade/shade.ramp $DATA_DIR/combined.tif || exit 1
rm -f $DATA_DIR/combined.{dbf,hgt.aux.xml,prj,shp,shx,raw.tif,tfw} || exit 1

echo "Done"

sleep 1

echo
echo " -- Map content -- "
echo

FILES=""
for COUNTRY in $FEATURE_COUNTRIES
do
  echo "Downloading $COUNTRY from http://download.geofabrik.de/$COUNTRY-latest.osm.pbf"
  if [[ -f $DATA_DIR/$COUNTRY.osm.pbf ]]; then
    echo "The file $DATA_DIR/$COUNTRY.osm.pbf is already present and will not be downloaded."
  else
    FILE=$DATA_DIR/$COUNTRY.osm.pbf
    mkdir -p -- "${FILE%/*}"
    wget http://download.geofabrik.de/$COUNTRY-latest.osm.pbf -O $DATA_DIR/$COUNTRY.osm.pbf || exit 1
  fi

  FILES="$FILES $DATA_DIR/$COUNTRY.osm.pbf"

  echo "Done $COUNTRY"
done

echo "Combining OSM data"
if [ "$(echo $FILES | wc -w)" = "1" ]; then
  echo "Copying $FILES to $DATA_DIR/combined.osm.pbf"
  cp $FILES $DATA_DIR/combined.osm.pbf
else
  echo "Merging files $FILES to $DATA_DIR/combined.osm.pbf"
  osmium merge --output=$DATA_DIR/combined.osm.pbf --overwrite $FILES || exit 1
fi
echo "Done combining OSM data"

echo "Importing combined OSM data"

# The following values can be tweaked
# See https://github.com/gravitystorm/openstreetmap-carto/blob/master/scripts/docker-startup.sh
OSM2PGSQL_CACHE=${OSM2PGSQL_CACHE:-1024}
OSM2PGSQL_NUMPROC=${OSM2PGSQL_NUMPROC:-4}
PGPASS=$PG_PASSWORD

echo "Using OSM2PGSQL_CACHE = $OSM2PGSQL_CACHE"
echo "Using $OSM2PGSQL_NUMPROC processes"

echo "Starting import from $DATA_DIR/combined.osm.pbf"

# No --hstore is used, because no tag data is needed
# Everything that is needed should be put into style/map-it.style
osm2pgsql \
  --cache $OSM2PGSQL_CACHE \
  --number-processes $OSM2PGSQL_NUMPROC \
  --multi-geometry \
  --host $PG_HOST \
  --database $PG_DATABASE \
  --username $PG_USER \
  --unlogged \
  --style /script/map-it.style \
  --slim \
  --drop \
  $DATA_DIR/combined.osm.pbf \
  || exit 1

echo "Done importing OSM data"

echo "Importing coastlines"

mkdir -p $DATA_DIR/coastlines

if [[ -f $DATA_DIR/coastlines/coastlines.zip ]]; then
  echo "The file $DATA_DIR/coastlines/coastlines.zip is already present and will not be downloaded."
else
  wget https://osmdata.openstreetmap.de/download/water-polygons-split-3857.zip -O $DATA_DIR/coastlines/coastlines.zip || exit 1
fi

if [[ -f $DATA_DIR/coastlines/water-polygons-split-3857/water_polygons.shp ]]; then
  echo "The file $DATA_DIR/coastlines/water-polygons-split-3857/water_polygons.shp is already present and will not be unzipped."
else
  unzip -o $DATA_DIR/coastlines/coastlines.zip -d $DATA_DIR/coastlines
fi

if psql $POSTGRES_ARGS -c "select count(*) from coastlines" > /dev/null; then
  echo "Coastlines table exists and will not be reimported. Remove the coastlines table to reimport the data."
else
  shp2pgsql -I -d -g way -s 3857 $DATA_DIR/coastlines/water-polygons-split-3857/water_polygons.shp coastlines \
    | psql $POSTGRES_ARGS | grep -v 'INSERT' || exit 1
fi

echo "Done importing coastlines"

echo "Processing peak prominence"

psql $POSTGRES_ARGS -c "DROP TABLE IF EXISTS peak_isolation;"
psql $POSTGRES_ARGS -c "$(cat <<QUERY
CREATE TABLE peak_isolation (
  osm_id bigint PRIMARY KEY,
  isolation int
);
QUERY
)"

# See https://github.com/der-stefan/OpenTopoMap/blob/c54cd2201b06c476d23d088e105eb69e924214d7/mapnik/tools/update_isolations.sh
QUERY=$(cat <<QUERY
SELECT
  osm_id,
  ST_X(ST_AsText(ST_Transform(way, 4326))),
  ST_Y(ST_AsText(ST_Transform(way, 4326))),
  ele
FROM
  planet_osm_point
WHERE
  "natural" IN (
    'peak',
    'volcano'
  ) AND
  ST_Transform(way, 4326) && ST_MakeEnvelope($(echo $BBOX | cut -d : -f 1 -), $(echo $BBOX | cut -d : -f 2 -), $(echo $BBOX | cut -d : -f 3 -), $(echo $BBOX | cut -d : -f 4 -), 4326)
;
QUERY
)

psql -A -t -F ";" $POSTGRES_ARGS -c "$QUERY" \
  | /script/isolation -f /data/combined.hgt \
  | awk -F ';' '{print "INSERT INTO peak_isolation(osm_id, isolation) VALUES (" $1 ", " $4 ");"}' \
  | psql $POSTGRES_ARGS \
  | wc -l

echo "Done processing peak prominence"

echo "Processing mountain passes"

psql $POSTGRES_ARGS -c "DROP TABLE IF EXISTS mountain_pass_road;"
psql $POSTGRES_ARGS -c "$(cat <<QUERY
CREATE TABLE mountain_pass_road (
  osm_id bigint PRIMARY KEY,
  road_osm_id bigint
);
QUERY
)"

psql $POSTGRES_ARGS -c "$(cat <<QUERY
INSERT INTO
  mountain_pass_road(osm_id, road_osm_id)
SELECT
  planet_osm_point.osm_id as osm_id,
  (
    SELECT
      road.osm_id
    FROM
      planet_osm_line as road
    WHERE
      ST_DWithin(planet_osm_point.way, road.way, 50) AND
      highway IN (
        'motorway_link',
        'trunk_link',
        'secondary_link',
        'primary_link',
        'motorway',
        'trunk',
        'cycleway',
        'tertiary',
        'secondary',
        'primary'
      )
    LIMIT 1
  ) as road_osm_id
FROM
  planet_osm_point
WHERE
  mountain_pass = 'yes'
;
QUERY
)"

echo "Done processing mountain passes"

echo "Done"
