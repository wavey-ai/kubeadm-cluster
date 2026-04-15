# HAProxy Ingress

This directory contains the pinned values used by the HAProxy Technologies
Helm chart during cluster bootstrap.

The bootstrap installs HAProxy ingress as a DaemonSet bound to host ports
`80/443` on nodes labeled `wavey.ai/ingress=true`.
