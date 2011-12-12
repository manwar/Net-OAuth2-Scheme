use warnings;
use strict;

package Net::OAuth2::Scheme::Mixin::Transport;
# ABSTRACT: the 'transport' option group and helper functions

use Net::OAuth2::Scheme::Option::Defines;
use parent 'Net::OAuth2::Scheme::Mixin::Bearer';
use parent 'Net::OAuth2::Scheme::Mixin::HMac';

use URI::Escape;

# transport helper functions

# INTERFACE transport
# DEFINES
#   http_extract
#   http_insert
#   accept_hook
#   accept_needs
Define_Group transport => undef,
  qw(http_extract  http_insert  accept_hook  accept_needs);

Default_Value transport_header => 'Authorization';

Define_Group transport_header_re => 'default';

sub pkg_transport_header_re_default {
    my __PACKAGE__ $self = shift;
    my $transport_header = $self->uses('transport_header');
    $self->install(transport_header_re => qr(\A\Q$transport_header\E\z));
    return $self;
}

Define_Group transport_auth_scheme_re => 'default';

sub pkg_transport_scheme_re_default {
    my __PACKAGE__ $self = shift;
    my $scheme = $self->uses('transport_auth_scheme');
    $self->install(transport_auth_scheme_re => qr(\A\Q$scheme\E\z));
    return $self;
}

Define_Group transport_auth_scheme => 'default';

sub pkg_transport_auth_scheme_default {
    # spec 8.1 says auth scheme SHOULD be identical to the token_type name
    my __PACKAGE__ $self = shift;
    my $type_name = $self->uses('token_type');
    if ($type_name =~ m{\A[-._0-9A-Za-z]+\z}) {
        # followed specified syntax for registered token_type names,
        # so it is not a URI, yay
        $self->install(transport_auth_scheme => $type_name);
    }
    # URI-style names really should not be used for auth schemes
    # so we give up and let uses() complain
    return $self;
}

#
# for defining http_insert and http_extract
# when token is being stashed in a header
# 

sub http_header_extractor {
    my __PACKAGE__ $self = shift;
    my %o = @_;
    my $uses_params = $o{uses_params};

    my $header_re = $self->uses_param(transport => $uses_params, 'header_re');
    $header_re = qr{$header_re}is unless ref($header_re);

    if (my $header = $self->installed('transport_header')) {
        Carp::croak("transport_header_re does not match transport_header")
            if ($header !~ $header_re);
    }
    
    if (my ($parse_header) = $o{parse_header}) {
        return sub {
            my ($plack_req) = @_;
            my @found = ();
            $plack_req->headers->scan(sub {
                return unless lc(shift) =~ $header_re;
                my @t = $parse_header->(shift, $plack_req);
                push @found, \@t if @t;
            });
            return @found;
        };
    }

    # what most people want to do
    my $parse_auth = $o{parse_auth} || sub {$_[0]};

    my $scheme_re = $self->uses_param(transport_auth => $uses_params, 'scheme_re');
    $scheme_re = qr{$scheme_re}is unless ref($scheme_re);

    if (my $scheme = $self->installed('transport_auth_scheme')) {
        Carp::croak("transport_auth_scheme_re does not match transport_auth_scheme")
            if ($scheme !~ $scheme_re);
    }
    return sub {
        my ($plack_req) = @_;
        my @found = ();
        $plack_req->headers->scan(sub {
            return unless lc(shift) =~ $header_re;
            return unless my ($s,$auth) = shift =~ m{([-A-Za-z0-9!#-'*+.^-`|~]+)\s+(.*\S|)\s*\z}s;
            return unless lc($s) =~ $scheme_re;
            my @t = $parse_auth->($auth, $plack_req);
            push @found, \@t if @t;
        });
        return @found;
    };
}

sub http_header_inserter {
    my __PACKAGE__ $self = shift;
    my %o = @_;
    my $uses_params = $o{uses_params};
    my $header = $self->uses_param('transport' => $uses_params, 'header');
    if (my $mk_header = $o{make_header}) {
        $self->install( http_insert => sub {
            my ($http_req) = @_;
            my ($error, $hcontent) = &$mk_header;
            $http_req->headers->push_header($header, $hcontent)
              unless $error;
            return ($error, $http_req)
        });
    }
    else {
        my $scheme = $self->uses_param('transport_auth' => $uses_params, 'scheme');
        my $mk_auth = $o{make_auth} || sub { return (undef, $_[1]) };
        $self->install( http_insert => sub {
            my ($http_req) = @_;
            my ($error, $auth) = &$mk_auth;
            $http_req->headers->push_header($header, "$scheme $auth")
              unless $error;
            return ($error, $http_req);
        });
    }
}

#  $body_or_query  : where to find parameters (body, query, or dontcare)
#  $token_param_re : regexp matching token parameter name
#  $other_re       : regexp matching all other parameter names that matter
sub http_parameter_extractor {
    my __PACKAGE__ $self = shift;
    my ($body_or_query, $token_param_re, $other_re) = @_;
    my $parameters = ($body_or_query eq 'dontcare' ? "parameters" 
                      : "${body_or_query}_parameters");
    return sub {
        my ($plack_req) = @_;
        my @found = ();
        my @others = ();
        $plack_req->$parameters->each(sub {
            my ($kwd, $value) = @_;
            if ($kwd =~ $token_param_re) {
                push @found, [$value];
            }
            elsif ($other_re && $kwd =~ $other_re) {
                push @others, $kwd, $value;
            }
        });
        if (@others) {
            push @$_, @others foreach (@found);
        }
        return @found;
    };
}

sub _put_body_params {
    my $http_req = shift;
    my $i = 1;
    my $content = $http_req->content;
    $http_req->add_content
      ((defined($content) && length($content) ?  "&" : "") .
       join('', map {(($i=!$i)?'=':'').uri_escape($_)} @_));
    $http_req->content_length(length($http_req->content));
}

sub _REQUIRED_CTYPE { 'application/x-www-form-urlencoded' };

sub http_parameter_inserter {
    my __PACKAGE__ $self = shift;
    my ($body_or_query, $param_name, $token_to_params) = @_;
    if ($body_or_query eq 'query') {
        $self->install( http_insert => sub {
            my $http_req = shift;
            $http_req->uri->query_form
              ($http_req->uri->query_form, $param_name, $token_to_params->(@_));
            return (undef, $http_req);
        });
    }
    elsif ($body_or_query eq 'body') {
        $self->install( http_insert => sub {
            my $http_req = shift;
            if (my $method = $http_req->method) {
                return ('bad_method', $http_req)
                  if $method =~ m{\A(?:GET|HEAD)\z};
            }
            else {
                $http_req->method('POST');
            }
            if (my $ctype = $http_req->content_type) {
                return ('wrong_content_type', $http_req)
                  unless $ctype eq _REQUIRED_CTYPE;
            }
            else {
                $http_req->content_type(_REQUIRED_CTYPE);
            }
            _put_body_params($http_req, $param_name, $token_to_params->(@_));
            return (undef, $http_req);
        });
    }
    elsif ($body_or_query eq 'dontcare') {
        # put it wherever we can;
        $self->install( http_insert => sub {
            my $http_req = shift;
            my @params = ($param_name, $token_to_params->(@_));
            my $ctype = $http_req->content_type;
            my $method = $http_req->method;

            if (((! defined $method) || $method !~ m{\A(?:GET|HEAD)\z})
                && ((! defined $ctype) || ($ctype eq _REQUIRED_CTYPE))) {
                # we can cram them into the body, yay...
                $http_req->method('POST') unless $method;
                $http_req->content_type(_REQUIRED_CTYPE) unless $ctype;
                _put_body_params($http_req, @params);
            }
            else {
                # we have to use query parameters, bleah
                $http_req->uri->query_form($http_req->uri->query_form, @params);
            }
            return (undef, $http_req);
        });
    }
    else {
        Carp::croak("http_parameter_inserter expects 'body','query', or 'dontcare':  $body_or_query");
    }
    return $self;
}


1;

=pod

=head1 SYNOPSIS

=head1 DESCRIPTION

This defines transport schemes.

