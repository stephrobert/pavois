# Cible piégée : le fichier sshd_config semble conforme (PermitRootLogin no),
# mais un drop-in lu en premier le surcharge en 'yes'. La config EFFECTIVE est
# donc 'yes' (non conforme), invisible pour un check qui lit le seul fichier.
# Pinned by digest, not by tag. `debian:12-slim` moves, so the same Dockerfile built twice can
# produce two different images, and a trap target whose contents drift is a trap that no longer
# tests what it was written to test. The digest is the multi-arch index, so it resolves on any
# architecture. Refresh with: docker buildx imagetools inspect debian:12-slim
FROM debian:12-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d \
 && printf 'Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin no\n' > /etc/ssh/sshd_config \
 && printf 'PermitRootLogin yes\n' > /etc/ssh/sshd_config.d/99-override.conf \
 && ssh-keygen -A
CMD ["/usr/sbin/sshd","-D","-e"]
