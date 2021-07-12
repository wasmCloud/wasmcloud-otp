#!/bin/bash
# Should be run with the "release" commands in the Makefile

set -e

mkdir -p /host/rel/artifacts/$NAME/$VERSION/

cp /opt/rel/"$NAME.tar.gz" /host/rel/artifacts/$NAME/$VERSION/"$TARGET.tar.gz"

exit 0