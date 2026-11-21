# patches/ubuntu

Kernel patches this packaging needs on top of Omarchy's. `scripts/build.sh` applies every
`*.patch` here in name order after Omarchy's patches, with `patch -Np1 --fuzz=0`.

There are none so far: what Ubuntu's user space needs is config, in `config/n1x.config`.

Name a patch `NNNN-short-description.patch`. Give it a git-format header that says why Ubuntu
needs it and Omarchy doesn't, and when it can be dropped.
