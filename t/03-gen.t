use strict;
use warnings;
use Test::More tests => 30;


use Net::OAuth2::Scheme;
use HTTP::Request::Common;
use Cache::Memory;
use HTTP::Message::PSGI;
use Plack::Request;

our $cache = Cache::Memory->new();

our ($as,$cs,$rs);
sub doit {
    my ($spec) = @_;
    ($as,$cs,$rs) = map {Net::OAuth2::Scheme->new(%{$spec},context=>$_)} qw(auth_server client resource_server);

    my $now = time;
    my ($e,@tt) = $as->token_create($now, 100, qw(a b c d e));
    ok( !defined($e));
    ($e,@tt) = $cs->token_accept(@tt);
    ok( !defined($e));
    ($e, my $q) = $cs->http_insert((GET 'http://example.com/gmap?x=1'), @tt);
    ok( !defined($e));
    my @ts = $rs->psgi_extract($q->to_psgi);
    ok (@ts == 1);
    ($e,my @tr) = $rs->token_validate(@{$ts[0]});
    ok( !defined($e));
    is_deeply(\@tr, [$now, 100, qw(a b c d e)]);
}

our %spec1 = 
  (
   transport => 'bearer', bearer_client_uses_param =>1, bearer_allow_uri=>1, 
   accept_keep=>[], format=>'bearer_handle', cache=>$cache
  );
doit(\%spec1);

our %spec2 = (transport => 'bearer', accept_keep=>[], format=>'bearer_signed', cache=>$cache);
doit(\%spec2);

our %spec3 = (transport => 'http_hmac', accept_keep=>[], format=>['http_hmac', hmac => 'hmac_sha224'], cache=>$cache);
doit(\%spec3);


our %spec4 = (transport => 'bearer', accept_keep=>[], format=>'bearer_handle', cache=>$cache,
  vtable => 'authserv_push', vtable_push => sub { return $rs->vtable_pushed(@_); },
);
doit(\%spec4);

our %spec5 = (transport => 'bearer', accept_keep=>[], format=>'bearer_handle', cache=>$cache,
  vtable => 'resource_pull', vtable_pull => sub { return $as->vtable_dump(@_); },
);
doit(\%spec5);
