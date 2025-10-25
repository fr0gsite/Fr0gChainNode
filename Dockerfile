FROM ubuntu:24.04

RUN mkdir /usr/node
RUN mkdir /usr/node/chaindata
WORKDIR /usr/node

#Install basic setup
RUN apt-get update && apt-get install software-properties-common git net-tools iputils-ping curl jq build-essential nano -y && apt-get clean

#Install EOSIO and CDT (Contract Development Toolkit)
RUN apt-get install -y wget \
&& wget https://github.com/AntelopeIO/spring/releases/download/v1.2.2/antelope-spring_1.2.2_amd64.deb \
&& apt install -y ./antelope-spring_1.2.2_amd64.deb \
&& rm antelope-spring_1.2.2_amd64.deb \
&& apt-get remove -y wget \
&& apt-get clean

COPY scripts/init_node.sh .
COPY jsonfiles/genesis.json .

RUN chmod +x init_node.sh
EXPOSE 8888
EXPOSE 1001