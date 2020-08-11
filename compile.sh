#!/bin/bash
set -e

echo Copying files...

cp -r scripting/ addons/sourcemod/
cp -r translations/ addons/sourcemod/
cp -r configs/ addons/sourcemod/

echo Compiling to .smx files...
cd addons/sourcemod/scripting
chmod +x spcomp

./spcomp pugsetup.sp
./spcomp pugsetup_autokicker.sp
./spcomp pugsetup_chatmoney.sp
./spcomp pugsetup_damageprint.sp
./spcomp pugsetup_hostname.sp
./spcomp pugsetup_rwsbalancer.sp
./spcomp pugsetup_teamlocker.sp
./spcomp pugsetup_teamnames.sp

echo Moving compiled files...

cd ..
mv scripting/*.smx plugins

echo Success!