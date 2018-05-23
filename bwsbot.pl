#!/usr/bin/env perl

use Modern::Perl;
use Slack::RTM::Bot;

my $slack_bot_token = $ENV{SLACK_BOT_TOKEN};

die "No SLACK_BOT_TOKEN set!" unless $slack_bot_token;

my $bot = Slack::RTM::Bot->new( token => $slack_bot_token );

my $regex_rt = qr/(ticket|rt)\s*([0-9]+)/mi;
my $regex_bz = qr/(bug|bz)\s*([0-9]+)/mi;
my $regex_coffee = qr/(coffee)\s*([0-9]+)/mi;

my $handle_ticket_numbers = sub {
    my ($response) = @_;

    return unless $response->{channel};

    $response->{text} =~ $regex_rt;
    my $ticket = $2;

    my $url =
      "https://ticket.bywatersolutions.com/Ticket/Display.html?id=$ticket";
    my $text = "RT Ticket $ticket: $url";

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};

my $handle_coffee = sub {
    my ($response) = @_;

    return unless $response->{channel};

    $response->{text} =~ $regex_bz;

    my $percent = $2;
    
    my $pointer = ( (abs $percent)  < 5) 
                ?  '' : (  (abs $percent)  < 10 ) 
                ?  '|' : (  (abs $percent) < 95 )
                ?  '>|'  : '>' ;

    my $bars = (  (abs $percent)/5 ) - length( $pointer );

    my $dots=20 - $bars - length( $pointer );

    my $meter = "|" . "=" x $bars . $pointer . "." x $dots . "|";
    if ( $percent < 0 ) {
        $meter =~ s/>/</;
        $meter = reverse( $meter );
    }

    $bot->say(
        channel => $response->{channel},
        text    => $meter,
    );
};

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

$bot->on(
    {
        text => $regex_rt,
    },
    $handle_ticket_numbers
);

$bot->on(
    {
        text => $regex_bz,
    },
    $handle_bug_numbers
);

$bot->on(
    {
        text => $regex_coffee,
    },
    $handle_coffee
);

$bot->start_RTM(
    sub {

        $bot->say(
            channel => 'general',
            text    => '<!here> bwsbot at your service!',
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

