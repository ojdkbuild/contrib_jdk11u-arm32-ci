#!/bin/bash
#
# Copyright 2018, akashche at redhat.com
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
set -x

# variables
export OJDK_TAG="$1"
# uncomment for standalone runs
#export OJDK_UPDATE=`echo ${OJDK_TAG} | sed 's/\./ /g' | sed 's/+/ /' | awk '{print $3}'`
#export OJDK_BUILD=`echo ${OJDK_TAG} | sed 's/+/ /' | awk '{print $2}'`
#export OJDK_MILESTONE=ojdkbuild
#export OJDK_IMAGE=jdk-11.0.${OJDK_UPDATE}-${OJDK_MILESTONE}-linux-armhf
export OJDK_WITH_NATIVE_DEBUG_SYMBOLS=none
export OJDK_WITH_DEBUG_LEVEL=release
export OJDK_CACERTS_URL=https://github.com/ojdkbuild/lookaside_ca-certificates/raw/master/cacerts
export D="docker exec builder"

# docker
sudo docker pull ubuntu:trusty
sudo docker run \
    -id \
    --name builder \
    -w /opt \
    -v `pwd`:/host \
    ubuntu:trusty \
    bash

# dependencies
$D apt update
$D apt install -y \
    autoconf \
    gcc \
    g++ \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    make \
    zip \
    unzip \
    debootstrap \
    qemu-user-static

# sysroot
$D qemu-debootstrap \
    --arch=armhf \
    --verbose \
    --include=fakeroot,build-essential,libx11-dev,libxext-dev,libxrender-dev,libxtst-dev,libxt-dev,libcups2-dev,libfontconfig1-dev,libasound2-dev,libfreetype6-dev \
    --resolve-deps trusty \
    /opt/chroot \
    || true
for fi in `$D bash -c "ls /opt/chroot/var/cache/apt/archives/*.deb"` ; do
    $D dpkg-deb -R $fi /opt/sysroot
done
$D ln -s /opt/sysroot/lib/arm-linux-gnueabihf /lib/arm-linux-gnueabihf

# boot jdk
$D wget -nv https://github.com/ojdkbuild/contrib_jdk11u-ci/releases/download/jdk-11%2B28/jdk-11.0.0-ojdkbuild-linux-x64.zip
$D unzip -q jdk-11.0.0-ojdkbuild-linux-x64.zip
$D mv jdk-11.0.0-ojdkbuild-linux-x64 bootjdk

# cacerts
$D wget -nv ${OJDK_CACERTS_URL} -O cacerts

# sources
$D wget -nv http://hg.openjdk.java.net/jdk-updates/jdk11u/archive/${OJDK_TAG}.tar.bz2
$D tar -xjf ${OJDK_TAG}.tar.bz2
$D rm ${OJDK_TAG}.tar.bz2
$D mv jdk11u-${OJDK_TAG} jdk11u

# build
$D mkdir jdkbuild
$D bash -c "cd jdkbuild && \
    bash /opt/jdk11u/configure \
    --openjdk-target=arm-linux-gnueabihf \
    --with-jvm-variants=server \
    --with-sysroot=/opt/sysroot/ \
    --with-toolchain-path=/opt/sysroot/ \
    --enable-unlimited-crypto=yes \
    --disable-warnings-as-errors \
    --disable-hotspot-gtest \
    --with-native-debug-symbols=${OJDK_WITH_NATIVE_DEBUG_SYMBOLS} \
    --with-debug-level=${OJDK_WITH_DEBUG_LEVEL} \
    --with-stdc++lib=static \
    --with-boot-jdk=/opt/bootjdk/ \
    --with-build-jdk=/opt/bootjdk/ \
    --with-cacerts-file=/opt/cacerts \
    --with-freetype-include=/opt/sysroot/usr/include/freetype2/ \
    --with-freetype-lib=/opt/sysroot/usr/lib/arm-linux-gnueabihf/ \
    --with-version-pre=${OJDK_MILESTONE} \
    --with-version-security=${OJDK_UPDATE} \
    --with-version-build=${OJDK_BUILD} \
    --with-version-opt='' \
    --with-log=info \
    --with-extra-cflags='-I/opt/sysroot/usr/include/c++/4.8 -I/opt/sysroot/usr/include/arm-linux-gnueabihf/c++/4.8' \
    --with-extra-cxxflags='-I/opt/sysroot/usr/include/c++/4.8 -I/opt/sysroot/usr/include/arm-linux-gnueabihf/c++/4.8'"
$D bash -c "cd jdkbuild && \
    make images"

# bundle
$D mv ./jdkbuild/images/jdk ${OJDK_IMAGE}
$D rm -rf ./${OJDK_IMAGE}/demo
$D zip -qyr9 ${OJDK_IMAGE}.zip ${OJDK_IMAGE}
$D mv ${OJDK_IMAGE}.zip /host/
sha256sum ${OJDK_IMAGE}.zip > ${OJDK_IMAGE}.zip.sha256
