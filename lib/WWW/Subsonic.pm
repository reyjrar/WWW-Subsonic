package WWW::Subsonic;
# ABSTRACT: Interface with the Subsonic API

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use HTML::Entities qw(decode_entities);
use Mojo::UserAgent;
use Moo;
use Types::Standard qw(InstanceOf Str);
use URI;
use URI::QueryParam;
use XML::Simple qw(XMLin);

# Clean Up the Namespace
use namespace::autoclean;

# VERSION

has 'username' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has 'password' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

has 'server' => (
    is => 'ro',
    isa => Str,
    lazy => 1,
    builder => '_build_server',
);
sub _build_server {
    my ($self) = @_;
    return sprintf "http://%s.subsonic.org", $self->username;
}

has 'salt' => (
    is       => 'ro',
    isa      => Str,
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_salt',
);
sub _build_salt {
    my @chars = ( 'a'..'z', 0..9, 'A'..'Z' );
    my $salt = '';
    $salt .= $chars[int(rand(@chars))] for( 1..12 );
    return $salt;
}

has 'token' => (
    is       => 'ro',
    isa      => Str,
    init_arg => undef,
    lazy     => 1,
    builder  => '_build_token',
);
sub _build_token {
    my ($self) = @_;
    return md5_hex( $self->password . $self->salt );
}

has 'ua' => (
    is       => 'ro',
    isa      => InstanceOf['Mojo::UserAgent'],
    init_arg => undef,
    default  => sub { Mojo::UserAgent->new() },
);

has 'api_version' => (
    is       => 'ro',
    isa      => Str,
    init_arg => undef,
    default  => sub { '1.15.0' },
);

has 'client_id' => (
    is       => 'ro',
    isa      => Str,
    init_arg => undef,
    default  => sub { 'perl(WWW::Subsonic)' },
);

sub api_request {
    my ($self,$path,$params) = @_;

    my $uri = URI->new( sprintf "%s/rest/%s", $self->server, $path );
    my %q = (
        u => $self->username,
        s => $self->salt,
        t => $self->token,
        v => $self->api_version,
        c => $self->client_id,
        defined $params ? %{ $params } : (),
    );
    foreach my $k ( keys %q ) {
        $uri->query_param( $k => $q{$k} );
    }

    my $as_url = $uri->as_string;
    my $result = $self->ua->get( $as_url )->result;
    my $ref;
    if( $result->is_success ) {
        my $body = $result->body;
        # If there are unprintable characters, XML::Simple gets
        # upset and we lose all the data.
        $body =~ s/[^[:print:]]//g;
        eval {
           $ref = XMLin($body);
        } or do {
            my $err = $@;
            warn sprintf "Failed XML Decode from: %s",
                $as_url, $err, $result->message;
        };
    }
    else {
        warn sprintf "Failed request: %s\n\n%s\n",
            $as_url,
            $result->message,
            $result->body,
        ;
    }
    return $ref;
}

1;
