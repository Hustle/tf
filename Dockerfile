FROM node:carbon-alpine
ARG terraform_version=0.11.3

COPY . /opt/tf

RUN apk add --update openssl unzip

RUN cd /opt/tf && npm i
RUN ln -s /opt/tf/tf /usr/local/bin
RUN wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip \
    -P /tmp
RUN unzip /tmp/terraform_${terraform_version}_linux_amd64.zip -d /usr/local/bin/

ENTRYPOINT [ "tf" ]