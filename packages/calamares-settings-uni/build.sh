#!/bin/bash

cd $(dirname "$0")
fakeroot dpkg-deb -b work calamares-settings-uni_1.0_all.deb
