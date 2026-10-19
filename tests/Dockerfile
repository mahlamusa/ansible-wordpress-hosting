# Throwaway Ubuntu host with systemd + SSH, used to test the playbooks.
ARG UBUNTU=24.04
FROM ubuntu:${UBUNTU}
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update \
 && apt-get install -y --no-install-recommends systemd systemd-sysv openssh-server python3 sudo ca-certificates iproute2 \
 && rm -rf /var/lib/apt/lists/* \
 && mkdir -p /root/.ssh && chmod 700 /root/.ssh \
 && systemctl enable ssh
COPY id_test.pub /root/.ssh/authorized_keys
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
