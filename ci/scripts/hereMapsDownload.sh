#!/bin/bash

######################################################################
# Download map data files from Here Maps website: 
# 1. download the fileDownloadable.xml which contains downloading info
# 2. parse fileDownloadable.xml to get the filenames, urls and md5sum
# 3. carry out the file downloading
# 4. make md5sum against downloaded files and save result to file
# 5. check md5sum to make sure downloaded files valid
######################################################################

set -e

## Expected env variables HERE_USERNAME and HERE_PASSWORD
if [[ ! ($HERE_USERNAME && $HERE_PASSWORD) ]]; then
  echo "===> Error: Expected env variable HERE_USERNAME and HERE_PASSWORD!"
  exit 1
fi

## install wget if not already installed in the docker container
whoami
apt-get update && apt-get -y install wget    ### install wget
wget --version | awk 'NR==1 {print}'          ### test wget and awk installed
md5sum --version | awk 'NR==1 {print}'		 ### test md5sum installed
echo "===> Info: Completed installation of wget. awk and md5sum should be installed as well if you saw me!"


DIR_DOWNLOADED="downloaded"
FILES_DOWNLOADABLE=filesDownloadable.xml
FILES_DOWNLOADABLE_URI="https://here.flexnetoperations.com/control/navt/login?username=$HERE_USERNAME&password=$HERE_PASSWORD&action=authenticate&accountID=NA01208&nextURL=%2Fcontrol%2Fnavt%2FfilesDownloadable%3Faction%3Dxml%26limitDays%3D10"

echo "===> Cleaning up any existing files and folders"
if [[ -d $DIR_DOWNLOADED ]]; then
	rm -rf $DIR_DOWNLOADED
	echo "===> Info: deleted existing folder $DIR_DOWNLOADED"
fi

if [[ -f verifymd5.tmp ]]; then
	rm verifymd5.tmp
	echo "===> Info: deleted existing file verifymd5.tmp"
fi

if [[ -f verifymd5.txt ]]; then
	rm verifymd5.txt
	echo "===> Info: deleted existing file verifymd5.txt"
fi

echo "===> Here maps username: $HERE_USERNAME, Here maps password: $HERE_PASSWORD"
echo "===> Downloding $FILES_DOWNLOADABLE: url=$FILES_DOWNLOADABLE_URI"

wget -q -L -O $FILES_DOWNLOADABLE "$FILES_DOWNLOADABLE_URI"

if ! [[ -e $FILES_DOWNLOADABLE && -s $FILES_DOWNLOADABLE ]]; then
  echo "===> Error: $FILES_DOWNLOADABLE was not downloaded or empty!"
  exit 1
fi


awk 'BEGIN {filename=""; md5=""; link=""}
     /<FileName>/ {filename=$0; gsub("<FileName><!\\[CDATA\\[", "", filename); gsub("\\]\\]></FileName>", "", filename); gsub("\\s", "", filename)}
     /<MD5CheckSum>/ {md5=$0; gsub("<MD5CheckSum><!\\[CDATA\\[", "", md5); gsub("\\]\\]></MD5CheckSum>", "", md5); gsub("\\s", "", md5); print md5 " " filename > "md5.txt"}
     /<DownloadLink>/ {link=$0; gsub("<DownloadLink><!\\[CDATA\\[", "", link); gsub("\\]\\]></DownloadLink>", "", link); gsub("\\s", "", link); print "wget -L -O \"" filename "\" \"" link"\"" > "dcmd.sh"}
' $FILES_DOWNLOADABLE

if ! [[ -e dcmd.sh && -s dcmd.sh && -e md5.txt && -s md5.txt ]]; then
  echo "===> Warn: dcmd.sh and/or md5.txt was not created or empty! There might be no files available for downloading."
  exit 0
fi

# Allow 60s to manually remove large files from download cmd - comment out in production
#echo "===> Sleeping for 60 seconds... you can manully remove unwanted files now..."
#sleep 60


mkdir -p $DIR_DOWNLOADED
cd $DIR_DOWNLOADED

echo "===> Downloading Here Maps data files to folder $DIR_DOWNLOADED ... this may take a while..."
source ../dcmd.sh


echo "===> Creating md5sum for downloaded files"
for afile in *
do
  if [[ -f $afile ]]; then
    md5sum $afile >> ../verifymd5.tmp
  fi
done


cd ..
awk '{gsub("\*",""); print $1 " " $2 > "verifymd5.txt"}' verifymd5.tmp 

echo "===> Verify verifiymd5.txt against md5.txt ..."
while read -r line
do 
  if grep -q "$line" md5.txt; then
    echo "===> Info: md5sum checked OK: $line"
  else
    echo "===> Error: md5sum does not match: $line"
    exit 1
  fi
done < verifymd5.txt

echo "===> Here Maps data downloaded successfully"

exit 0