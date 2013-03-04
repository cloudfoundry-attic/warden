#!/bin/bash

set -e

cd $(dirname $0)/pb

export BEEFCAKE_NAMESPACE=Warden::Protocol

out=bundle
(echo "package protocol;" && (find . -name '*.proto' | sort | xargs cat | sed /^package/d)) > $out
protoc --beefcake_out=. $out
sed -e "s/Beefcake::Message/Warden::Protocol::BaseMessage/" $out.pb.rb > ../pb.rb
rm -f $out*
