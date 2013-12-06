#!/bin/bash

set -e

cd $(dirname $0)/pb

export BEEFCAKE_NAMESPACE=Warden::Protocol

protoc --beefcake_out=. *.proto

rm ../pb.rb

for generated in *.pb.rb; do
  sed -e "s/Beefcake::Message/Warden::Protocol::BaseMessage/" $generated >> ../pb.rb
done

rm -f *.pb.rb
