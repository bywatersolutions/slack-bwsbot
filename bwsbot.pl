#!/usr/bin/env perl

=head1 NAME

bwsbot - A Slackbot for ByWater Solutions

=cut

use Modern::Perl;
use Slack::RTM::Bot;

my $slack_bot_token = $ENV{SLACK_BOT_TOKEN};

die "No SLACK_BOT_TOKEN set!" unless $slack_bot_token;

my $bot = Slack::RTM::Bot->new( token => $slack_bot_token );

=head1 Capabilities

=head2 handle_ticket_numbers

    Converts RT ticket numbers into URLs.
    Can be of the form "ticket 1234" or "rt 1234".
    The keywords are case insenstivie.

=cut

my $regex_rt     = qr/(ticket|rt)\s*([0-9]+)/mi;
my $handle_ticket_numbers = sub {
    my ($response) = @_;

    return unless $response->{channel};

    $response->{text} =~ $regex_rt;
    my $ticket = $2;

    my $url =
        "https://ticket.bywatersolutions.com"
      . "/Ticket/Display.html?id="
      . $ticket;
    my $text = "RT Ticket $ticket: $url";

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_rt }, $handle_ticket_numbers );

=head2 handle_bug_numbers

    Converts Koha community bug numbers into URLs.
    Can be of the form "bug 1234" or "bz 1234".
    The keywords are case insenstivie.

=cut

my $regex_bz     = qr/(bug|bz)\s*([0-9]+)/mi;
my $handle_bug_numbers = sub {
    my ($response) = @_;

    return unless $response->{channel};

    $response->{text} =~ $regex_bz;
    my $bug = $2;

    my $url  = "https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=$bug";
    my $text = "Koha community bug $bug: $url";

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_bz }, $handle_bug_numbers );

=head2 handle_coffee

    Prints a nice bar indicating the percentage of wakefullness you are at.
    E.g. coffee 50

=cut

my $regex_coffee = qr/(coffee)\s*([0-9]+)/mi;
my $handle_coffee = sub {
    my ($response) = @_;

    return unless $response->{channel};

    $response->{text} =~ $regex_coffee;

    my $percent = $2;

    my $pointer =
        ( ( abs $percent ) < 5 )  ? ''
      : ( ( abs $percent ) < 10 ) ? '|'
      : ( ( abs $percent ) < 95 ) ? '>|'
      :                             '>';

    my $bars = ( ( abs $percent ) / 5 ) - length($pointer);

    my $dots = 20 - $bars - length($pointer);

    my $meter = "|" . "=" x $bars . $pointer . "." x $dots . "|";
    if ( $percent < 0 ) {
        $meter =~ s/>/</;
        $meter = reverse($meter);
    }

    $bot->say(
        channel => $response->{channel},
        text    => "`Coffee: $meter`",
    );
};
$bot->on( { text => $regex_coffee }, $handle_coffee );

$bot->start_RTM(
    sub {

        $bot->say(
            channel => 'general',
            text    => 'bwsbot at your service!',
        );

        my $step = 1;
        while (1) {
            sleep 10;
            print time . " ";
            say $step % 3 ? "Stayin' alive!" : "Ah, ha, ha, ha";
            $step++;
        }
    }
);

