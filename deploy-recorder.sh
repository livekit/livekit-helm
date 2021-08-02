#!/bin/sh

set -euxo pipefail

rm -rf build
mkdir -p build
helm package livekit-recorder --destination build
cd build
AWS_REGION=us-east-1 helm s3 push --relative ./livekit-recorder*.tgz livekit

aws cloudfront create-invalidation --distribution-id E2MJ94T12TAUZU --paths "/*"
