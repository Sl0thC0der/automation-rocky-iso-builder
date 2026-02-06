FROM rockylinux/rockylinux:10

# ISO build toolchain
RUN dnf -y update \
 && dnf -y install lorax xorriso isomd5sum curl ca-certificates \
 && dnf clean all

WORKDIR /work

# Example invocation:
#   mkksiso --ks /work/ks.cfg /work/input.iso /work/output.iso
ENTRYPOINT ["bash","-lc"]
