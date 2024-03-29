#!/usr/bin/env perl

=head1 NAME

bwsbot - A Slackbot for ByWater Solutions

=cut

use feature qw(say);

use Modern::Perl;

use List::Util qw(shuffle);
use Slack::RTM::Bot;
use YAML::XS qw(LoadFile DumpFile Load);
use JSON;
use Text::CSV::Slurp;
use LWP::Simple;

my $slack_bot_token = $ENV{SLACK_BOT_TOKEN};
my $data_file       = $ENV{DATA_FILE};
my $debug           = $ENV{DEBUG} || 0;
my $csv_url         = $ENV{CSV_URL};
my $minutes_to_live = $ENV{MINUTES_TO_LIVE} || undef;

say "BWSBot is starting!" if $debug;

die "No SLACK_BOT_TOKEN set!" unless $slack_bot_token;

warn "No DATA_FILE set!"       unless $data_file;
$data_file = '/tmp/bwsbot.yml' unless $data_file;
warn "DATA FILE: $data_file" if $debug;

`touch $data_file`;
my $data = LoadFile($data_file);
unless ($data) {
    warn "DATA FILE is empty, initializing." if $debug;
    $data = { agendas => {} };
    DumpFile( $data_file, $data );
}

my $bot = Slack::RTM::Bot->new( token => $slack_bot_token );

=head1 Capabilities

=head2 bug_branches

    Given a bug number and optionally a shortname, e.g.
    branches 5676
    branches 5676 clic
    this command will return the branches in bywater-koha
    that contain that bug, filtered by the given shortname.

    If no branch is supplied, the default shortname is 'bywater'

=cut

my $regex_bug_branches  = qr/(branches)\s*(\d+)\s*(\w*)/mi;
my $handle_bug_branches = sub {
    my ($response) = @_;
    warn "handle_bug_branches" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_bug_branches;
    my $bug = $2;
    my $shortname = $3 || q{bywater};

    $bug =~ s/^\s+|\s+$//g;
    $shortname =~ s/^\s+|\s+$//g;

    my $json = qx{curl http://find-branches-by-bugs.bwsdocker1.bywatersolutions.com/$bug/$shortname};
    my $data = Load($json);

    my $text;
    if ( @$data ) {
        $text = qq{I found bug $bug on the following branches for $shortname\n};
        $text .= "* $_\n" for @$data;
    } else {
        $text = qq{I could not find bug $bug in any branches for $shortname!\n};
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_bug_branches }, $handle_bug_branches );

=head2 handle_ticket_numbers

    Converts RT ticket numbers into URLs.
    Can be of the form "ticket 1234" or "rt 1234".
    The keywords are case insenstivie.

=cut

my $regex_rt              = qr/(ticket|rt)\s*([0-9]+)/mi;
my $handle_ticket_numbers = sub {
    my ($response) = @_;
    warn "handle_ticket_numbers" if $debug;

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

my $regex_bz           = qr/(bug|bz)\s*([0-9]+)/mi;
my $handle_bug_numbers = sub {
    my ($response) = @_;
    warn "handle_bug_numbers" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_bz;
    my $bug = $2;

    my $url  = "https://bugs.koha-community.org/bugzilla3/show_bug.cgi?id=$bug";

    my $res = decode_json( qx{curl https://bugs.koha-community.org/bugzilla3/rest/bug/$bug} );
    my $bug_data = $res->{bugs}[0];

    my $text = "Koha community <$url|bug $bug>: _" . $bug_data->{summary} . "_ [*". $bug_data->{status} ."*]";

    $bot->say(
        channel => $response->{channel},
        text    => $text,
        mrkdwn  => 1,
    );
};
$bot->on( { text => $regex_bz }, $handle_bug_numbers );

=head2 handle_coffee

    Prints a nice bar indicating the percentage of wakefullness you are at.
    E.g. coffee 50

=cut

my $regex_coffee  = qr/(coffee)\s*([0-9]+)/mi;
my $handle_coffee = sub {
    my ($response) = @_;
    warn "handle_coffee" if $debug;

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

my $regex_agenda_help  = qr/(agenda help)\s*/mi;
my $handle_agenda_help = sub {
    my ($response) = @_;
    warn "handle_agenda_help" if $debug;

    return unless $response->{channel};

    my $text = q{BWSBot Agenda Manager help:
`agenda list`: List agendas
`agenda create <agenda name>`: Create a new agenda
`agenda destroy <agenda name>`: Delete an existing agenda
`agenda <agenda name> list`: List the items on the agenda
`agenda <agenda name> add <item>`: Add an item to the agenda
`agenda <agenda name> del <index>`: Delete an item from the agenda by its list index
};

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_help }, $handle_agenda_help );

my $regex_agenda_create  = qr/(agenda create)\s*(.+)/mi;
my $handle_agenda_create = sub {
    my ($response) = @_;
    warn "handle_agenda_create" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_agenda_create;
    my $agenda = $2;

    $agenda =~ s/^\s+|\s+$//g;

    my $text;
    if ( $data->{agendas}->{$agenda} ) {
        $text = "The agenda `$agenda` already exists";
    }
    else {
        $data->{agendas}->{$agenda} = {};
        $text = "The agenda `$agenda` has been created";
        DumpFile( $data_file, $data );
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_create }, $handle_agenda_create );

my $regex_agenda_destroy  = qr/(agenda destroy)\s*(.+)/mi;
my $handle_agenda_destroy = sub {
    my ($response) = @_;
    warn "handle_agenda_destroy" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_agenda_destroy;
    my $agenda = $2;

    $agenda =~ s/^\s+|\s+$//g;

    my $text;
    if ( !exists $data->{agendas}->{$agenda} ) {
        $text = "The agenda `$agenda` doesn't exist";
    }
    else {
        delete $data->{agendas}->{$agenda};
        $text = "The agenda `$agenda` has been destroyed";
        DumpFile( $data_file, $data );
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_destroy }, $handle_agenda_destroy );

my $regex_agenda_list  = qr/(agenda list)\s*/mi;
my $handle_agenda_list = sub {
    my ($response) = @_;
    warn "handle_agenda_list" if $debug;

    return unless $response->{channel};

    my @agendas = $data->{agendas} ? keys %{ $data->{agendas} } : undef;

    my $text;
    if (@agendas) {
        $text = "Agendas:\n";
        my $i = 1;
        map { $text .= $i++ . ". $_\n" } @agendas;
    }
    else {
        $text = "There are no agendas at this time";
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_list }, $handle_agenda_list );

my $regex_agenda_add_item  = qr/(agenda)\s*(.+)(add)\s*(.+)/mi;
my $handle_agenda_add_item = sub {
    my ($response) = @_;
    warn "handle_agenda_add_item" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_agenda_add_item;
    my $agenda = $2;
    my $item   = $4;

    $agenda =~ s/^\s+|\s+$//g;
    $item   =~ s/^\s+|\s+$//g;

    my $text;
    if ( !exists $data->{agendas}->{$agenda} ) {
        $text = "The agenda `$agenda` doesn't exist";
    }
    else {
        if ( ref $data->{agendas}->{$agenda}->{items} eq 'ARRAY' ) {
            push( @{ $data->{agendas}->{$agenda}->{items} }, $item );
        }
        else {
            $data->{agendas}->{$agenda}->{items} = [$item];
        }

        $text = "The item `$item` has been added to the agenda `$agenda`";
        DumpFile( $data_file, $data );
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_add_item }, $handle_agenda_add_item );

my $regex_agenda_del_item  = qr/(agenda)\s*(.+)(del)\s*([0-9]+)/mi;
my $handle_agenda_del_item = sub {
    my ($response) = @_;
    warn "handle_agenda_del_item" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_agenda_del_item;
    my $agenda = $2;
    my $index  = $4;

    $agenda =~ s/^\s+|\s+$//g;
    $index  =~ s/^\s+|\s+$//g;

    $index--;    # Because programmers count from zero ;)

    my @items =
      $data->{agendas}->{$agenda}->{items}
      ? @{ $data->{agendas}->{$agenda}->{items} }
      : undef;

    my $text;
    if ( !exists $data->{agendas}->{$agenda} ) {
        $text = "The agenda `$agenda` doesn't exist";
    }
    elsif ( !exists $items[$index] ) {
        $text = "The agenda `$agenda` doesn't have an item at that index";
    }
    else {
        my $item = $items[$index];
        splice @items, $index, 1;
        $data->{agendas}->{$agenda}->{items} = \@items;
        $text = "The item `$item` has been deleted from the agenda `$agenda`";
        DumpFile( $data_file, $data );
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_del_item }, $handle_agenda_del_item );

my $regex_agenda_list_items  = qr/(agenda)\s+(.+)\s+(list)\s*/mi;
my $handle_agenda_list_items = sub {
    my ($response) = @_;
    warn "handle_agenda_list_items" if $debug;

    return unless $response->{channel};

    $response->{text} =~ $regex_agenda_list_items;
    my $agenda = $2;

    $agenda =~ s/^\s+|\s+$//g;

    my @items =
      $data->{agendas}->{$agenda}->{items}
      ? @{ $data->{agendas}->{$agenda}->{items} }
      : undef;

    my $text;
    if (@items) {
        $text = "Agenda `$agenda` items:\n";
        my $i = 1;
        map { $text .= $i++ . ". $_\n" } @items;
    }
    else {
        $text = "The agenda `$agenda` has no items at this time";
    }

    $bot->say(
        channel => $response->{channel},
        text    => $text,
    );
};
$bot->on( { text => $regex_agenda_list_items }, $handle_agenda_list_items );

my $regex_taco_me  = qr/taco me$/mi;
my $handle_taco_me = sub {
    my ($response) = @_;
    warn "hanlde_taco_me" if $debug;

    my $json = qx{curl http://taco-randomizer.herokuapp.com/random/};
    my $data = Load($json);

    my $msg = qq{Here's your taco:\n
<$data->{base_layer}->{url}|Base layer>\n
$data->{base_layer}->{recipe}\n
<$data->{seasoning}->{url}|Seasoning>\n
$data->{seasoning}->{recipe}\n
<$data->{mixin}->{url}|Mixin>\n
$data->{mixin}->{recipe}\n
<$data->{shell}->{url}|Shell>\n
$data->{shell}->{recipe}\n
<$data->{condiment}->{url}|Condiment>\n
$data->{condiment}->{recipe}\n};

    $bot->say(
        channel => $response->{channel},
        text    => $msg,
    );
};
$bot->on( { text => $regex_taco_me }, $handle_taco_me );

$bot->start_RTM(
    sub {
        $bot->say(
            channel => 'general',
            text    => get_quote(),
        );

        my $step = 1;
        while (1) {
            sleep 60;
            print time . " " . "MINUTES RUN: $step";
            $step++;
            if ( $minutes_to_live && $step > $minutes_to_live ) {
                $bot->stop_RTM();
                exit(0);
            }
        }
    }
);

sub get_quote {
    if ($csv_url) {
        print "Downloading quotes CSV...";
        my $raw_csv = get($csv_url);
        say "Done!";
        my $quotes  = Text::CSV::Slurp->load( string => $raw_csv );
        my $index   = rand @$quotes;
        my $quote   = $quotes->[$index]->{Quote};

        if ( $quote =~ /^PQ: / ) {
            $quote =~ s/^PQ: /Partner Quote: /;
        }
        elsif ( $quote =~ /^HAHA: / ) {
            $quote =~ s/^HAHA: //;
        }
        elsif ( $quote =~ /^MOVE: / ) {
            $quote =~ s/^MOVE: /Get up and move! /;
        }
        elsif ( $quote =~ /^FACT: / ) {
            $quote =~ s/^FACT: /Fun Fact! /;
        }
        elsif ( $quote =~ /^Koha sys pref:/ ) {
            $quote =~ s/^Koha sys pref: /Koha SysPref Quiz! Do you know what this setting does\? /;
        }

        say "Using Quote: $quote";
        return $quote;
    }
    else {
        my @APIs =
          shuffle( \&get_math_fact, \&get_joke, \&get_cat_fact,
            \&get_insperational_quote, \&get_programming_quote, );
        my $sub = $APIs[0];
        return $sub->();
    }
}

sub get_joke {
    my $joke = qx{curl -H "Accept: text/plain" https://icanhazdadjoke.com/};
    $joke ||= "No joke for you!";
    return $joke;
}

sub get_cat_fact {
    my $json = qx{curl https://cat-fact.herokuapp.com/facts/random/};
    my $data = Load($json);
    my $fact = $data->{text};
    return $fact;
}

sub get_insperational_quote {
    my $json =
qx{curl http://api.forismatic.com/api/1.0/?method=getQuote&lang=en&format=json};
    my $data = Load($json);
    return "$data->{quoteText} - $data->{quoteAuthor}";
}

sub get_programming_quote {
    my $json =
      qx{curl https://programming-quotes-api.herokuapp.com/quotes/random};
    my $data = Load($json);
    return "$data->{en} - $data->{author}";
}

sub get_math_fact {
    my $fact = qx{curl http://numbersapi.com/random/trivia};
    return $fact;
}
