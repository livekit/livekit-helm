#!/bin/sh

set -euxo pipefail

rm -rf build
mkdir -p build
helm package livekit-server --destination build
cd build
AWS_REGION=us-east-1 helm s3 push ./livekit-server*.tgz livekit
