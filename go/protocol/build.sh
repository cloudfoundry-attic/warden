#!/bin/bash

set -e
set -x

cd pb

out=bundle
(echo "package protocol;" && (find . -name '*.proto' | sort | xargs cat | sed /^package/d)) > $out
protoc --go_out=. $out
cat $out.pb.go | gofmt > ../pb.go

rm -f $out*
