use warnings;
use strict;

package Net::OAuth2::TokenType;
# ABSTRACT: Token type objects and definition framework for OAuth 2.0

our %_all = ();
our $Factory_Class = 'Net::OAuth2::TokenType::Factory';
my $This = 'a';

sub new {
    my $class = shift;
    # really, no one should ever need to subclass this,
    # since the $Factory_Class is endlessly customizable
    # But now that I've said that, someone will find an excuse,
    # so we'll just follow the paradigm anyway...

    my $factory_class;
    if ($_[0] eq 'factory') {
        (undef, $factory_class) = splice(@_,0,2); # shift shift
        # yes, this means factory => classname has to be first;
        # cope...
    }
    else {
        $factory_class = $Factory_Class;
    }
    my $factory = $factory_class->new(@_);

    # start the cascade of methods being implemented
    $factory->uses('root');

    # build the object, install the method definitions
    my $tag = ++$This;
    for my $method ($factory->all_exports) {
        no strict 'refs';
        ${"${class}::$method"}{$tag} = $factory->uses($method);
        ${"${class}::${method}::"}{CODE} ||= sub {
              my $self = shift; 
              return ${$method}{$$self}->(@_);
          };
        $_all{$method}++;
    }
    return bless \ $tag, $class;
}

sub DESTROY {
    my $self = shift;
    my $class = ref($self);
    for my $method (keys %_all) {
        no strict 'refs';
        delete ${"${class}::$method"}{$$self};
    }
}


1;

__END__

=head1 DESCRIPTION

A token type object represents a particular combination of

providing token creation, validation, and transmission methods
that are specialized for the given situation.

Note that for the purposes of this module, authorization codes are
essentially another kind of token and thus can likewise have token
type objects for manipulating them.

=head1 SYNOPSIS

Exactly how this would look depends on the respective server
frameworks in use, but...

  our %access_token_scheme = (... options describing token scheme ...);

  ##
  ## Within a Client Implementation
  ##

  our $token_type = Net::OAuth2::TokenType->new
    (%access_token_scheme, context => 'client');

  ... obtain authorization grant
  ... send token request

  # receive token
  #
  my %params = ... parameters from token response

  my ($error, @token) = $token_type->token_accept(%params)
  ... complain if $error

  # use token
  #
  my $request = ... build HTTP request as per resource API

  ($error, $request) = $token_type->http_insert($request, @token);

  ... complain if $error
  ... send $request

  ##
  ## Within an Authorization Server Implementation
  ##

  our $access_token_type = 
    Net::OAuth2::TokenType->new
     (%access_token_scheme, context => 'auth_server');

  our $refresh_token_type = 
    Net::OAuth2::TokenType->new
     (kind => 'refresh', ... options ... );

  # create tokens
  #
  ($error, my @token) = 
    $token_type->token_create($now=time(), 900, ...);
    ... complain if $error

  ($error, my $refresh) = 
    $refresh_token_type->token_create($now, 86400, ...);
    ... complain if $error
  }

  # issue tokens
  #
  ...respond( access_token => @token, refresh_token => $refresh );

  ##
  ## Within a Resource Server Implementation
  ##

  our $token_type = Net::OAuth2::TokenType->new
    (%access_token_scheme, context => 'resource_server');

  HANDLER for resource endpoint = sub {
     my Plack::Request $request = shift;

     # extract tokens from request
     # 
     my ($error, @tokens_found) = $token_type->http_extract($request);
     ... complain if $error
     ... deal with (@tokens_found != 1) as appropriate

     my @token = $tokens_found[0];     

     # validate token
     # 
     my ($error, $issue_time, $expires_in, @bindings) =
       $token_type->token_validate(@token);

     ... check $error
     ... check $issue_time + $expires_in vs. time()
     ... check @bindings
     ... perform API actions
  }

  ##########################################################
  %access_token_scheme = (... vtable => 'authserv_push' ...)

  ##
  ## within an Authorization Server implementation
  ##

  our $access_token_type = 
    Net::OAuth2::TokenType->new
     (%access_token_scheme,
      context => 'auth_server',
      vtable_push => \&my_vtable_push,
     );

  sub my_vtable_push {
    my @new_entry = @_

    ... send serialization of @new_entry to authserv_push endpoint

    return ($error) if ... something bad happened
    return ()
  }

  ##
  ## within a Resource Server implementation
  ##

  our $access_token_type = 
    Net::OAuth2::TokenType->new
     (%access_token_scheme, context => 'resource_server');

  HANDLER for authserv_push endpoint... = sub {
    ... authenticate authorization server

    my @new_entry = ... unserialize from request;
    my ($error) = $token_type->vtable_pushed(@new_entry);

    ... return error response if $error
    ... return success 
  }

  ##########################################################
  %access_token_scheme = (... vtable => 'resource_pull' ...)

  ##
  ## within an Authorization Server implementation
  ##

  our $access_token_type = 
    Net::OAuth2::TokenType->new
     (%access_token_scheme, context => 'auth_server');

  HANDLER for resource_pull endpoint ... = sub {
    ... authenticate resource server

    my @pull_query = ... unserialize from request
    my @pull_response = $token_type->vtable_dump(@pull_query);

    ... return response with serialization of @pull_response
  }

  ##
  ## within a Resource Server implementation
  ##

  our $access_token_type = 
    Net::OAuth2::TokenType->new
     (%access_token_scheme, 
      context => 'resource_server',
      vtable_pull => \&my_vtable_pull,
     );

  sub my_vtable_pull {
    my @pull_query=@_;

    ... send serialization of @pull_query to resource_pull endpoint

    my @pull_response = ... unserialize from response
    return @pull_response;
  }



=head1 CONSTRUCTOR

=head2 new

 $type = new(%token_scheme);


=head1 METHODS

The parameter and return values that are used in common amongst the
various type object methods are as follows:

=over

=item I<$issue_time>

time of token issue in seconds UTC since The Epoch (midnight, January 1, 1970)

=item I<$expires_in>

number of seconds after I<$issue_time> that token expires

=item I<@bindings>

an arbitrary sequence of string values that are bound into the token.  

For the purposes of this module these values are opaque and up to the
module user, though an OAuth2 implementation will almost certainly be
including at least resource_id, client_id, and scope

=item I<$request_out>

an outgoing request as might be composed by a user agent or
application, either an L<HTTP::Request|HTTP::Request> object or
something with a similar interface.

=item I<$request_in>

an incoming request as received by a server URI handler,
either a L<Plack::Request|Plack::Request> object or
something with a similar interface.

=item I<@token_as_issued>

the token string (C<access_token> value) followed by the sequence of
alternating keyword-value pairs that comprise the token as issued by
the authorization server.  The keywords here will be C<token_type> and
the names of any extension parameters defined as part of this token
scheme that are needed in order to construct an access request using
this token.  All values are as they appear in a successful token or
authorization endpoint response (i.e., prior to being encoded into a
JSON structure or URI fragment on the authorization server, or,
equivalently, after such decoding on the client side).

Note that C<expires_in>, C<scope>, and C<refresh_token> are
specifically I<not> included here (see next item).

For refresh tokens and authorization codes, I<@token_as_issued> will
always be a one-element list consisting solely of the string token
value.

=item I<@non_token_params>

the keyword-value pairs corresponding to the C<expires_in>, C<scope>,
C<refresh_token> and any other parameters (whether due to an exension,
local variation, or specified in some future version of OAuth)
received in a token response that are I<not> needed in order to
construct an access request using this token.

=item I<@token_as_saved>

the token string plus I<keyword> C<=E<gt>> I<value> pairs that comprise
the token in the form that it is to be saved on the client.  

This may include additional client-side data as required by the token
scheme (e.g., http_hmac requires the receive time).  Some or all of
I<@non_token_params> can also be included at the discretion of the client
implementer.

=item I<@token_as_used>

the token string plus I<keyword> C<=E<gt>> I<value> pairs that
comprise the token in the form that it is to be sent to the resource
server.  Here, the I<keyword>s will refer to Authorization header
attributes, body parameters, or URI parameters depending on the
transport scheme in use and need not have anything to do with the
keywords that appear in I<@token_as_issued> or I<@token_as_saved>.

For refresh tokens and authorization codes, I<@token_as_issued> and
I<@token_as_used> are one-element lists consisting solely of the
string token value.

=item I<$error>

in return values will be C<undef> when the method call succeeds,
and otherwise will be some true value when the method call fails.

=back

The following methods will be defined on token type objects,
depending on the context chosen:

=head2 token_create  I<[Authorization Server]>

 ($error, @token_as_issued) =
   type->token_create($issue_time, $expires_in, @bindings)

creates a new token in the form to be sent to the client.  As a side
effect this also communicates any necessary secrets and perhaps also
some subset of the expiration and binding information to the resource
server as needed.

Questions of token format, whether (and which) bindings are physically
included with the token as sent to the client vs. communicated
separately to the resource server, and how such communication takes
place are determined by the format and vtable specifications chosen
for this token type.

=head2 token_accept  I<[Client]>

 ($error, @token_as_saved)
   = type->token_accept(@token_as_issued, @non_token_params)

=over

=item *

checks that the C<token_type> parameter is as expected for 
this token type.

=item *

includes in @token_as_saved, additional client-side information (e.g.,
the time of receipt for C<http_hmac> tokens) that may be needed to
construct access requests,

=item *

includes some or all of I<@non_token_params> as determined by the
option settings C<accept_keep> and C<accept_remove>.  Note that the
I<@non_token_params> supplied to this call can be a (possibly empty)
subset of the originally received I<@non_token_params> (i.e., it's
okay to remove these parameters beforehand if you want).

=back

Clients I<can> simultaneously accomodate multiple token transport types
provided each expected C<token_type> value corresponds to at most one
specified token type, e.g.,

  my ($error, $use_type, @token_as_saved);
  for my $type ($bearer_type, $hmac_http_type, ...) {
     ($error, @token_as_saved)
       = $type->token_accept(@token_as_issued);
     unless ($error) {
         $use_type = $type;
         last;
     }
  }
  unless ($use_type) { ... complain... }

=head2 http_insert  I<[Client]>

 ($error, $request_out)
  = type->http_insert($request_out, @token_as_saved)

converts I<@token_as_saved> to I<@token_as_used> E<mdash> silently ignoring any
I<@non_token_params> that might be present E<mdash> then modifies (in-place) 
the outgoing request so as to include I<@token_as_used> as authorization,
returning the modified request.  This may either add headers,
post-body parameters, or uri parameters as per the transport scheme
for this token type.

=head2 http_extract  I<[Resource Server]>

 ($error, [@token_as_used],...) = type->http_extract($request_in)

extracts I<all> apparent tokens present in an incoming request that
conform to this token type's transport specification.

Ideally, there would be at most one valid token in any given request,
however, other headers or parameters may, depending on how the
resource API is structured, spuriously match the token transport
specification and we won't find this out until we attempt to validate
the resulting "tokens" (not that this should happen with a
well-designed API, but there may be legacies and compromises to
contend with...)

It may also be that one may wish for a given resource API to accept
multiple tokens in certain situations.  If you go this route, it is
B<strongly recommended> that there be a fixed, small limit on number
of tokens that may be included in any request E<mdash> otherwise you
risk providing an attacker an easy means of brute-force search to
forge/discover token values.

=head2 token_validate  I<[Resource Server], [Refresh Tokens/Authcodes]>

 ($error, $issue_time, $expires_in, @bindings)
   = type->token_validate(@token_as_used);

Decodes the token, retrieves expiration and binding information, and
verifies any signature/hmac-values that may be included in the token
format.

The caller is responsible for deciding whether/how to observe the
expiration time and for checking correctness of binding values.

=head2 vtable_pushed  I<[Resource Server]>

 ($error) = type->vtable_pushed(@push_entry)

For use in C<authserv_push> handlers (see ...).  Here I<@push_entry> is an
opaque sequence of strings extracted from the C<authserv_push> message 
constructed and sent by B<vtable_push>.

=head2 vtable_dump  I<[Authorization Server]>

 @pull_response = $token_type->vtable_dump(@pull_query)

For use in C<resource_pull> handlers (see ...).  Here I<@pull_query> is
an opaque sequence of strings extracted from the pull request
constructed and sent by B<vtable_pull> and I<@pull_response> is the
corresponding opaque sequence to be included in the response and
returned from B<vtable_pull> on the resource server side.  Note that
I<@pull_response> may contain an error indication, but if so, that
should be handled by the resource server.

