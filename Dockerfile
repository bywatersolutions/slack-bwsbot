FROM perl:latest
MAINTAINER Kyle M Hall <kyle@bywatersolutions.com>

LABEL maintainer="kyle@bywatersolutions.com"

RUN cpanm --notest Modern::Perl Slack::RTM::Bot YAML::XS Text::CSV::Slurp LWP::Simple

RUN apt-get update && apt-get install -y cron \
 && rm -rf /var/cache/apt/archives/* \
 && rm -rf /var/lib/api/lists/*

WORKDIR /app
COPY . .

COPY self-destruct /etc/cron.d/self-destruct
RUN chmod 0644 /etc/cron.d/self-destruct

CMD perl bwsbot.pl
