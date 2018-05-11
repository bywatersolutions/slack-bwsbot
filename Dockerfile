FROM perl:latest

LABEL maintainer="kyle@bywatersolutions.com"

RUN cpanm Modern::Perl Slack::RTM::Bot

WORKDIR /app
ADD . /app

CMD perl bwsbot.pl
