# Cible piégée : le fichier sshd_config semble conforme (PermitRootLogin no),
# mais un drop-in lu en premier le surcharge en 'yes'. La config EFFECTIVE est
# donc 'yes' (non conforme), invisible pour un check qui lit le seul fichier.
FROM debian:12-slim
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/*
RUN mkdir -p /run/sshd /etc/ssh/sshd_config.d \
 && printf 'Include /etc/ssh/sshd_config.d/*.conf\nPermitRootLogin no\n' > /etc/ssh/sshd_config \
 && printf 'PermitRootLogin yes\n' > /etc/ssh/sshd_config.d/99-override.conf \
 && ssh-keygen -A
CMD ["/usr/sbin/sshd","-D","-e"]
