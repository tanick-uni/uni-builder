#!/bin/bash
cd $(dirname "$0")
fakeroot dpkg-deb -b work uni-os-build-conflicts_1.0_all.deb
