FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y openssh-server sudo && \
    mkdir -p /var/run/sshd /opt/admin/logs

# analyst account
RUN useradd -m -s /bin/bash analyst && \
    echo "analyst:blue_team_rocks" | chpasswd && \
    usermod -aG sudo analyst

# Allow password auth
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's/PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config

EXPOSE 22

CMD ["/usr/sbin/sshd", "-D"]
