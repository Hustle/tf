FROM node:carbon-alpine
ARG terraform_version=0.11.3

COPY . /opt/tf

RUN cd /opt/tf && npm i
RUN ln -s /opt/tf/tf /usr/local/bin
RUN wget https://releases.hashicorp.com/terraform/${terraform_version}/terraform_${terraform_version}_linux_amd64.zip \
    -P /usr/local/bin/
RUN unzip /usr/local/bin/
CMD [ "/tf" ]