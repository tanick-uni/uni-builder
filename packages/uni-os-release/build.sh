#!/bin/bash

cd $(dirname "$0")
fakeroot dpkg-deb -b work uni-os-release_1.0~builder_all.deb
