#!/bin/bash

###############################################################################
# Download Here Maps tools utility, extract and run the tools
# 1. download the Here Maps tools - latest release
# 2. extract the latest Here Maps tools
# 3. create RDF database and run the Here Maps tool against Here Maps RDF files
###############################################################################


if [[ $# -lt 5 ]]; then
  echo "===> Usage: <script.sh> absolute-path-to-rdf-files, rdf-db-username, rdf-db-password, rdf-db-name, rdf-db-host [,rdf-db-port]"
  exit 1
fi

if [[ ! (-d $1) || ($(ls -A $1 | wc -l) -eq 0) ]]; then
  echo "===> Error: Here Maps RDF file folder not found or empty: $1"
  exit 1
elif [[ ${1:0:1} != '/' ]]; then
  echo "===> Error: Path to RDF files was not an absolute path: $1"
  exit 1
fi

export RDF_FILE_DIR=$1
export PGUSER=$2
export PGPASSWORD=$3
export RDF_DB_NAME=$4
export RDF_DB_HOST=$5

if [[ ! $6 ]]; then
  export RDF_DB_PORT="5432"
else
  if [[ ($6 =~ ^[0-9]+$) && ($6 -gt 1024) && ($6 -lt 65535) ]]; then
    export RDF_DB_PORT=$6
  else
    echo "===> Error: $6 is not a valid port number!"
    exit 1
  fi
fi

psql="psql -h ${RDF_DB_HOST} -p ${RDF_DB_PORT} "

$psql -c 'select 1' &> /dev/null
if [[ $? -ne 0 ]]; then
  echo "===> Error: Could not connect with ${PGUSER}/${PGPASSWORD} at ${RDF_DB_HOST}:${RDF_DB_PORT}"
  exit 1
fi

$psql -d $RDF_DB_NAME -c 'select 1' &> /dev/null
if [[ $? -eq 0 ]]; then
  echo "===> Error: Database already exists: ${RDF_DB_NAME} at ${RDF_DB_HOST}:${RDF_DB_PORT}"
  exit 1
fi

echo "===> Arguments validated: RDF_FILE_DIR=${RDF_FILE_DIR}, PGUSER/PGPASSWORD=${PGUSER}/${PGPASSWORD}, RDF_DB_HOST=${RDF_DB_HOST}, RDF_DB_NAME=${RDF_DB_NAME}, RDF_DB_PORT=${RDF_DB_PORT}"


RDF_LOAD_TEMP=""
HERE_MAPS_TOOLS_HTML="hereMapTools.html"
HERE_MAPS_TOOLS_URI="https://tcs.ext.here.com/maptools/distributions"

echo "===> Downloading Here Maps tools page $HERE_MAPS_TOOLS_HTML from uri: $HERE_MAPS_TOOLS_URI"
wget --timeout=180 -O $HERE_MAPS_TOOLS_HTML "$HERE_MAPS_TOOLS_URI"

if ! [[ -f $HERE_MAPS_TOOLS_HTML && -s $HERE_MAPS_TOOLS_HTML ]]; then
  echo "===> Error: $HERE_MAPS_TOOLS_HTML was not downloaded properly!"
  exit 1
fi

echo "===> Downloading the latest release of Here Maps Tool"
awk '/<a href=\"\/maptools\/distributions\/Map_Tools_[0-9]+\.zip\">/ {gsub("<li class=\"hvr-overline-reveal\"><a href=\"\/maptools\/distributions\/Map_Tools_[0-9]+\.zip\">",""); gsub("</a></li>",""); gsub("\\s",""); print > "toolFiles.txt"}' $HERE_MAPS_TOOLS_HTML

if  [[ ! (-f toolFiles.txt && -s toolFiles.txt) ]]; then
  echo "===> Error: toolFiles.txt was not created or empty!"
  exit 1
fi

cat toolFiles.txt | sort -r > toolFilesSorted.txt
LATEST_HERE_MAPS_TOOL_FILE=$(awk 'NR==1{print}' toolFilesSorted.txt)
LATEST_HERE_MAPS_TOOL_URI="${HERE_MAPS_TOOLS_URI}/${LATEST_HERE_MAPS_TOOL_FILE}"
echo "===> Info: LATEST_HERE_MAPS_TOOL_URI: $LATEST_HERE_MAPS_TOOL_URI"

echo "===> Downloading Here Maps latest tool: $LATEST_HERE_MAPS_TOOL_FILE"
wget --timeout=180 -O $LATEST_HERE_MAPS_TOOL_FILE "$LATEST_HERE_MAPS_TOOL_URI"

if [[ ! (-e $LATEST_HERE_MAPS_TOOL_FILE && -s $LATEST_HERE_MAPS_TOOL_FILE) ]]; then
  echo "===> Error: $LATEST_HERE_MAPS_TOOL_FILE was not downloaded properly!"
  exit 1
fi


echo "===> Extracting Here Maps latest tool"
LATEST_HERE_MAPS_TOOL_DIR=$(echo $LATEST_HERE_MAPS_TOOL_FILE | awk '{gsub("\.zip","");print}')
if [[ -d $LATEST_HERE_MAPS_TOOL_DIR ]]; then
  rm -rf $LATEST_HERE_MAPS_TOOL_DIR
  echo "===> Info: Deleted existing folder $LATEST_HERE_MAPS_TOOL_DIR"
fi

unzip -q $LATEST_HERE_MAPS_TOOL_FILE

ls -l $LATEST_HERE_MAPS_TOOL_DIR | grep 'install_RDF.sh'
if [[ $? -ne 0 ]]; then
  echo "===> Error: Here Maps tool incomplete, missing install_RDF.sh"
  exit 1
fi


echo "===> Creating database ${RDF_DB_NAME} with owner central..."
$psql '-c CREATE DATABASE '${RDF_DB_NAME}' WITH OWNER central'

if [[ $? -eq 0 ]]; then
  echo "===> Creating database entension postgis..."
  $psql -d ${RDF_DB_NAME} -c 'CREATE EXTENSION postgis'
else
  echo "===> Error: Could not create database ${RDF_DB_NAME}!"
  exit 1
fi

if [[ $? -eq 0 ]]; then
  RDF_LOAD_TEMP=$(pwd)'/RDF_Load_Temp'
  if [[ -d $RDF_LOAD_TEMP ]]; then
    rm -rf $RDF_LOAD_TEMP
    echo "===> Info: Deleted existing rdf-load-temp-dir $RDF_LOAD_TEMP"
  fi
  mkdir -p $RDF_LOAD_TEMP
  echo "===> Info: Created rdf-load-temp-dir $RDF_LOAD_TEMP"
  
  cd $LATEST_HERE_MAPS_TOOL_DIR
  echo "===> Running Here Maps latest tool: command psql is ${psql}, RDF_DB_NAME: ${RDF_DB_NAME}, temp dir is ${RDF_LOAD_TEMP}. This may take a while..."
  ./install_RDF.sh -jdbcurl 'jdbc:postgresql://'${RDF_DB_HOST}':'${RDF_DB_PORT}'/'${RDF_DB_NAME}';searchpath=public' -user ${PGUSER} -pass ${PGPASSWORD} -rdfdir ${RDF_FILE_DIR} -tempdir ${RDF_LOAD_TEMP} -wktString
  
  echo "===> Running Here Maps latest tool completed successfully."
  exit 0
else
  echo "===> Error: Could not create database ${RDF_DB_NAME} with extension postgis"
  exit 1
fi
