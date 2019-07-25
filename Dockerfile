FROM perl:latest
MAINTAINER Kyle M Hall <kyle@bywatersolutions.com>

LABEL maintainer="kyle@bywatersolutions.com"

RUN cpanm --notest Modern::Perl Slack::RTM::Bot YAML::XS

WORKDIR /app
COPY . .

CMD perl bwsbot.pl
