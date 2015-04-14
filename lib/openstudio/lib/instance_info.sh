#!/usr/bin/env bash



c="$(curl http://169.254.169.254/latest/meta-data/ami-id)"
echo $c

#printf '{"hostname":"%s","distro":"%s","uptime":"%s"}\n' "eval $LOCAL" "$distro" "$uptime"