set -e -x -u

vagrant ssh-config > ssh_config
rsync -arq --rsh="ssh -F ssh_config" $1/ default:workspace
