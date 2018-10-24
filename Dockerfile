FROM ubuntu:bionic

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y -q && \
  apt-get install -y mysql-client-5.7 wget apt-transport-https curl gnupg && \
  echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ bionic main" | \
  tee /etc/apt/sources.list.d/azure-cli.list && \
  curl -L https://packages.microsoft.com/keys/microsoft.asc | apt-key add - && \
  apt-get update -y -q && \
  apt-get install -y azure-cli && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists/*

ADD start.sh /start.sh
RUN chmod 0755 /start.sh

ENTRYPOINT ["/start.sh"]
