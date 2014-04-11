#!/bin/bash
set -e -x -u

vagrant ssh-config > ssh_config
rsync -arq --rsh="ssh -F ssh_config" --exclude .vagrant $1/ default:workspace
