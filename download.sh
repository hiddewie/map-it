#!/usr/bin/env bash

DATA_DIR=/data
# DATA_DIR=data
COUNTRIES="Netherlands"
# COUNTRIES="Slovakia"
COUNTRIES_LOCATION="/script/countries.txt"
# COUNTRIES_LOCATIO"countries.txt"
FEATURE_COUNTRIES="netherlands/overijssel"
# FEATURE_COUNTRIES="slovakia"
LATITUDES="N52"
LONGITUDES="E006"

PGPASSWORD="$PG_PASSWORD"

mkdir -p $DATA_DIR

echo
echo " -- Height, contours & shade -- "
echo

ARGS="-I -d"
for LAT in $LATITUDES
do
  for LON in $LONGITUDES
  do
    NAME="${LAT}${LON}"

    echo "Get $NAME"
    wget https://dds.cr.usgs.gov/srtm/version2_1/SRTM3/Eurasia/$NAME.hgt.zip -O $DATA_DIR/$NAME.hgt.zip || exit 1

    echo "Unzip $NAME"
    unzip -o $DATA_DIR/$NAME.hgt.zip -d $DATA_DIR || exit 1
    rm $DATA_DIR/$NAME.hgt.zip || exit 1

    echo "Contours $NAME"
    rm -f $DATA_DIR/$NAME.shp || exit 1
    gdal_contour -i 20 -snodata -32768 -a height $DATA_DIR/$NAME.hgt $DATA_DIR/$NAME.shp || exit 1

    echo "Import contours $NAME"
    shp2pgsql $ARGS -s 4326 $DATA_DIR/$NAME.shp contours | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1

    echo "Shade $NAME"
    rm -f $DATA_DIR/$NAME.shade || exit 1
    gdaldem hillshade $DATA_DIR/$NAME.hgt $DATA_DIR/$NAME.shade || exit 1
    rm -f $DATA_DIR/$NAME.dbf $DATA_DIR/$NAME.hgt $DATA_DIR/$NAME.prj $DATA_DIR/$NAME.shp $DATA_DIR/$NAME.shx || exit 1

    echo "Done $NAME"

    ARGS="-a"
  done
done

echo
echo " -- Country borders -- "
echo

echo "Get $COUNTRIES"
IDS=$(grep $COUNTRIES $COUNTRIES_LOCATION  | awk '{print $1}' | paste -sd "," -)
wget "https://wambachers-osm.website/boundaries/exportBoundaries?cliVersion=1.0&cliKey=192f6ee3-bde5-4c76-a655-1d68b66a91b8&exportFormat=shp&exportLayout=single&exportAreas=land&union=true&selected=$IDS" \
  -O $DATA_DIR/countries.shp || exit 1

shp2pgsql -I -d -s 4326 $DATA_DIR/countries.shp country_border | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT'

rm $DATA_DIR/countries.shp || exit 1

echo
echo " -- Map content -- "
echo

ARGS="-I -d"
for COUNTRY in $FEATURE_COUNTRIES
do
  mkdir -p $DATA_DIR/$COUNTRY

  echo "Get $COUNTRY"
  wget http://download.geofabrik.de/europe/$COUNTRY-latest-free.shp.zip -O $DATA_DIR/$COUNTRY.hgt.zip || exit 1

  echo "Unzip $COUNTRY"
  unzip -o $DATA_DIR/$COUNTRY.hgt.zip -d $DATA_DIR/$COUNTRY || exit 1
  rm $DATA_DIR/$COUNTRY.hgt.zip || exit 1

  echo "Import data $COUNTRY"
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_water_a_free_1.shp water_a | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_landuse_a_free_1.shp landuse_a | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE"  | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_waterways_free_1.shp waterways | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_natural_free_1.shp natural | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_railways_free_1.shp railways | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_roads_free_1.shp roads | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_places_free_1.shp places | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_transport_free_1.shp transport | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_pois_free_1.shp poi | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_pois_a_free_1.shp poi_a | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_pofw_free_1.shp pofw | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1
  shp2pgsql $ARGS -s 4326 $DATA_DIR/$COUNTRY/gis_osm_natural_free_1.shp natural_a | psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -d "$PG_DATABASE" | grep -v 'INSERT' || exit 1

  echo "Delete shape data $COUNTRY"
  rm -r $DATA_DIR/$COUNTRY || exit 1

  echo "Done $COUNTRY"

  ARGS="-a"
done

echo "Done"
