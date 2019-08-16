FROM perl:latest
MAINTAINER Kyle M Hall <kyle@bywatersolutions.com>

LABEL maintainer="kyle@bywatersolutions.com"

RUN cpanm --notest Modern::Perl Slack::RTM::Bot YAML::XS
# RUN apt-get update && apt-get install -y curl \
#    && rm -rf /var/cache/apt/archives/* \
#    && rm -rf /var/lib/api/lists/*

WORKDIR /app
COPY . .

CMD perl bwsbot.pl
