#!/bin/bash
set -ev

VERSION=$1

echo "Download und extract sourcemod"
wget "http://www.sourcemod.net/latest.php?version=$VERSION&os=linux" -O sourcemod.tar.gz
tar -xzf sourcemod.tar.gz

echo "Give compiler rights for compile"
chmod +x addons/sourcemod/scripting/spcomp

addons/sourcemod/scripting/compile.sh plugin.sp
#