#!perl -d
use EV;
use AE;

use Promises backend => ['EV'];
use Search::Elasticsearch::Async;
use Test::More;
use strict;
use warnings;

my $trace
    = !$ENV{TRACE}       ? undef
    : $ENV{TRACE} eq '1' ? 'Stderr'
    :                      [ 'File', $ENV{TRACE} ];

die 'No $ENV{ES_VERSION} specified' unless $ENV{ES_VERSION};

my $cv = AE::cv;

my $api      = "$ENV{ES_VERSION}::Direct";
my $body     = $ENV{ES_BODY} || 'GET';
my $cxn      = $ENV{ES_CXN} || do "default_async_cxn.pl" || die( $@ || $! );
my $cxn_pool = $ENV{ES_CXN_POOL} || 'Async::Static';
my @plugins  = split /,/, ( $ENV{ES_PLUGINS} || '' );
our %Auth;

if ( $cxn eq 'Mojo' && !eval { require Mojo::UserAgent; 1 } ) {
    plan skip_all => 'Mojo::UserAgent not installed';
    exit;
}

{
    no warnings 'redefine';

#===================================
    sub wait_for {
#===================================
        my $promise = shift;
        my $cv      = AE::cv;
        $promise->done( $cv, sub { $cv->croak(@_) } );
        $cv->recv;
    }
}

my $es;
if ( $ENV{ES} ) {
    eval {
        $es = Search::Elasticsearch::Async->new(
            nodes            => $ENV{ES},
            trace_to         => $trace,
            cxn              => $cxn,
            cxn_pool         => $cxn_pool,
            client           => $api,
            send_get_body_as => $body,
            plugins          => \@plugins,
            %Auth
        );
        if ( $ENV{ES_SKIP_PING} ) {
            $cv->send(1);
        }
        else {
            $es->ping->then( sub { $cv->send(@_) }, sub { $cv->croak(@_) } );
        }
        $cv->recv;
        1;
    } or do {
        diag $@;
        undef $es;
    };
}

unless ($es) {
    plan skip_all => 'No Elasticsearch test node available';
    exit;
}

unless ( $ENV{ES_SKIP_PING} ) {
    my $version = wait_for( $es->info )->{version}{number};
    my $api     = $es->api_version;
    unless ( $api eq '0_90' && $version =~ /^0\.9/
        || substr( $api, 0, 1 ) eq substr( $version, 0, 1 ) )
    {
        plan skip_all =>
            "Tests are for API version $api but Elasticsearch is version $version\n";
        exit;
    }
}

return $es;

unless ( $ENV{ES_SKIP_PING} ) {
    my $version = wait_for( $es->info )->{version}{number};
    my $api     = $es->api_version;
    diag "$version - $api\n";
    die "Tests are for API version $api but Elasticsearch is version $version\n"
        unless $api eq '0.90' && $version =~ /^0\.9/
        || substr( $api, 0, 1 ) eq substr( $version, 0, 1 );
}

return $es;

