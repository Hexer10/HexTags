#!/bin/bash
set -ev

TAG=$1

echo "Download und extract sourcemod"
wget "http://www.sourcemod.net/latest.php?version=1.8&os=linux" -O sourcemod.tar.gz
tar -xzf sourcemod.tar.gz

echo "Give compiler rights for compile"
chmod +x addons/sourcemod/scripting/spcomp

echo "Set plugins version"
for file in addons/sourcemod/scripting/hextags.sp
do
  sed -i "s/<TAG>/$TAG/g" $file > output.txt
  rm output.txt
done

addons/sourcemod/scripting/compile.sh hextags.sp

echo "Remove plugins folder if exists"
if [ -d "addons/sourcemod/plugins" ]; then
  rm -r addons/sourcemod/plugins
fi

echo "Create clean plugins folder"
mkdir -p build/addons/sourcemod/scripting/include
mkdir build/addons/sourcemod/configs
mkdir build/addons/sourcemod/plugins

echo "Move plugins files to their folder"
mv addons/sourcemod/scripting/include/hextags.inc build/addons/sourcemod/scripting/include
mv addons/sourcemod/scripting/hextags.sp build/addons/sourcemod/scripting
mv addons/sourcemod/scripting/compiled/hextags.smx build/addons/sourcemod/plugins
mv addons/sourcemod/configs/hextags.cfg build/addons/sourcemod/configs/hextags.cfg


echo "Compress the plugin"
mv LICENCE build/
cd build/ && zip -9rq hextags.zip addons/ LICENSE && mv hextags.zip ../

echo "Build done"