package WWW::Subsonic;
# ABSTRACT: Interface with the Subsonic API

=head1 SYNOPSIS

This module provides a very simple interface to using the Subsonic API.

    use Path::Tiny;
    use WWW::Subsonic;

    my $subsonic = WWW::Subsonic->new(
        username => 'user1',
        password => 'Assw0rd1P',
    );

    my $pinged = $subsonic->api_request('ping.view');

    my $starred = $subsonic->api_request('getStarred2');

    foreach my $song (@{ $starred->{song} }) {
        my $dst = path($song->{path});
        $dst->parent->mkpath;
        $dst->spew_raw( $subsonic->api_request(download => { id => $song->{id} }) );
    }

=cut

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use HTML::Entities qw(decode_entities);
use JSON::MaybeXS;
use Mojo::UserAgent;
use Moo;
use Types::Standard qw(Enum InstanceOf Int Str);
use URI;
use URI::QueryParam;
use version 0.77;

# Clean Up the Namespace
use namespace::autoclean;

# VERSION

=attr B<protocol>

Subsonic protocol, https (the default) or http.

=cut

has 'protocol' => (
    is      => 'ro',
    isa     => Enum[qw(http https)],
    default => sub { 'https' },
);

=attr B<server>

Subsonic server name, defaults to localhost

=cut

has 'server' => (
    is      => 'ro',
    isa     => Str,
    default => sub { 'localhost' },
);

=attr B<port>

Subsonic server port, default 4000

=cut

has 'port' => (
    is      => 'ro',
    isa     => Int,
    default => sub { 'localhost' },
);

=attr B<username>

Subsonic username, B<required>.

=cut

has 'username' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

=attr B<password>

Subsonic user's password, B<required>.  This is never sent over the wire,
instead it's hashed using a salt for the server to verify.

=cut

has 'password' => (
    is       => 'ro',
    isa      => Str,
    required => 1,
);

=attr B<salt>

Salt for interacting with the server, regenerated each object instantiation.
Will be randomly generated.

=cut

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
    $salt .= $chars[int(rand(@chars))] for 1..12;
    return $salt;
}

=attr B<token>

Generated from the B<salt> and B<password>.

=cut

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

=attr B<ua>

UserAgent object used to interface with the Subsonic server.  Needs
to be an instance of Mojo::UserAgent.

=cut

has 'ua' => (
    is       => 'ro',
    isa      => InstanceOf['Mojo::UserAgent'],
    default  => sub { Mojo::UserAgent->new() },
);

=attr B<api_version>

The Subsonic API verion to target, currently defaults to the latest, Subsonic
6.1, API version 1.15.0.

=cut

has 'api_version' => (
    is       => 'ro',
    isa      => Str,
    default  => sub { '1.15.0' },
);

=attr B<client_id>

The identifier to use for interfacing with the server, defaults to
perl(WWW::Subsonic).

=cut

has 'client_id' => (
    is       => 'ro',
    isa      => Str,
    default  => sub { 'perl(WWW::Subsonic)' },
);

=method B<api_request>

Builds an API request using the parameters.

=over 2

=item 1. API Method

This is the name of of the method to call, ie, C<getStarred>, C<download>, etc.

=item 2. Hash Reference of Arguments

Most API calls take one or more named arguments.  Specify those named arguments
in this hash reference and they will be encoded properly and joined with the
other parameters to form the request.

=back

This method provides the following arguments to all API calls so you don't have
to: B<u> - username, B<s> - salt, B<t> - token, B<v> - API version, B<c> -
client identified, B<f> - format (json).

=cut

sub api_request {
    my ($self,$path,$params) = @_;

    my $uri = URI->new( sprintf "%s://%s:%d/rest%s/%s",
        $self->protocol,
        $self->server,
        $self->port,
        version->parse($self->api_version) >= version->parse('2.0.0') ? 2 : '',
        $path
    );
    my %q = (
        u => $self->username,
        s => $self->salt,
        t => $self->token,
        v => $self->api_version,
        c => $self->client_id,
        f => 'json',
        defined $params ? %{ $params } : (),
    );
    foreach my $k ( keys %q ) {
        $uri->query_param( $k => $q{$k} );
    }

    my $as_url = $uri->as_string;
    my $result = $self->ua->get( $as_url )->result;
    my $data;
    if( $result->is_success ) {
        my $body = $result->body;
        if( $result->headers->content_type =~ m{application/json} ) {
            eval {
                my $d = decode_json($body);
                $data = $d->{'subsonic-response'};
                1;
            } or do {
                my $err = $@;
                warn sprintf "Failed JSON Decode from: %s\n%s\n\n%s\n",
                    $as_url, $err, $result->message;
            };
        }
        else {
            # Don't try to decode, just pass back our response
            $data = $body;
        }
    }
    else {
        warn sprintf "Failed request(%s): %s\n\n%s\n",
            $as_url,
            $result->message,
            $result->body,
        ;
    }
    return $data;
}

=head1 SEE ALSO

L<Subsonic API Docs|http://www.subsonic.org/pages/api.jsp>

=cut

1;
