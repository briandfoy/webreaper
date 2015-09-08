#!/usr/bin/perl -w
# $Id$
use strict;

use Benchmark;
use Carp;
use Cwd qw( cwd );
use Data::Dumper;
use ExtUtils::Command qw(mkpath);
use File::Basename qw(basename dirname);
use File::Find;
use File::Spec::Functions qw(catfile);
use FindBin;
use Getopt::Std;
use HTML::SimpleLinkExtor;
use HTTP::Cookies;
use HTTP::Status qw(status_message);
use LWP::UserAgent;
use MIME::Base64 qw(encode_base64);
use POSIX;
use Socket;
use URI;
use YAML;

=encoding utf8

=head1 NAME

webreaper -- download a web page and its links

=head1 SYNOPSIS

	webreaper [OPTIONS] URL

=head1 DESCRIPTION

THIS IS ALPHA SOFTWARE

The webreaper program downloads web sites.  It creates a directory,
named after the host of the URL given on the command line, in the
current working directory, and will optionally create a tarball of
it.

=head2 Getting around web site misfeatures

This script has many features to make it look like a normal, interaction
web browser.  You can set values for some features, or use the defaults,
enumerated later.

Set the user-agent string with the -a switch.  Some web sites
refuse to work with certain browsers because they want you to use
Internet Explorer.  While webreaper is not subject to javascript
checks (except for ones that try to redirect you), some servers try
that behind-the-scenes.

Set the referer [sic] string.  Some sites limit what you can see based
on how they think you got to the address (i.e. they want you to click
on a certain link).  The script automatically sets the referer strings
for links it finds in web pages, but you can set the referer for the
first link (the one you specify on the command line) with the -r switch.

=head2 Basic browser features

For websites that use a login and password, use the -u and -p switches.
This feature is still a bit broken because it sends the authorization
string for every address.

=head2 Script features

Watch the action by turning on verbose messages with the -v switch.  If
you run this script from another script, cron, or some other automated
method, you probably want no output, so do not use -v.  You can also
set the WEBREAPER_VERBOSE environment variable.

To get even more output, use the -d switch to turn on debugging output.
You can also set the WEBREAPER_DEBUG varaible.

You can create a single file of everything that you download by creating
an archive with the -t switch, which creates a tarball.

The script limits its traversal to URLs below the starting URL.  This may
change in the future.

=head2 Command line switches

=over 4

=item -a USER_AGENT

set the user agent string

=item -e

list of file extensions to store (not yet implemented)

=item -E

list of file extensions to skip (not yet implemented)

=item -d

turn on debugging output

=item -D DIRECTORY

use this directory for downloads

=item -f

store all files in the same directory (flat)

=item -h HOST1[,HOST2...]

allowed hosts, comma separated.

=item -n NUMBER

stop after requesting NUMBER resources, whether or not webreaper stored them

=item -N NUMBER

stop after storing NUMBER resources

=item -r REFERER_URL

referer for the first URL

=item -p PASSWORD

password for basic auth

=item -s SECONDS

sleep between requests

=item -t

create tar archive

=item -u USERNAME

username for basic auth

=item -v

verbose ouput

=item -z

create a zip archive

=back

=head2 Examples

=over 4

=item scrape a site, with a randomizing pause between requests

webreaper -s 10 http://www.example.com

=item make a tar archive

webreaper -t http://www.example.com

=item make a zip archive

webreaper -z http://www.example.com

=item make a tar and a zip archive

webreaper -t -z http://www.example.com

=item set the user agent string

webreaper -a "Mozilla 19.2 (Sony PlayStation)" http://www.example.com

=item stop after making 10 requests or storing 5 files, whichever comes first

webreaper -N 5 -n 10 http://www.example.com

=back

=head1 Environment variables

=over 4

=item WEBREAPER_DEBUG

Show debugging output (implies verbose output). This is the same
as the -d switch.

=item WEBREAPER_VERBOSE

Show progress information. This is the same as the -v switch.

=item WEBREAPER_DIR

Store downloads in this directory.  Script uses the current
working directory if this directory does not exist.  This is
the same as the -D switch.

=back

=head2 Wish list

=over 4

=item limit directory level

=item limit content types, file names to store

=item specify a set of patterns to ignore

=item do conditional GETs

=item Tk or curses interface?

=item create an error log, report, or something

=item download stats (clock time, storage space, etc)

=item multiple levels of verbosity for output

=item read items from a config file

=item allow user to add/delete allowed domains during runtime

=item ensure that path names are safe (i.e. no ..)

=back

=head1 SEE ALSO

lwp-rget (comes with LWP)

=head1 SOURCE AVAILABILITY

This source is part of a SourceForge project which always has the
latest sources in CVS, as well as all of the previous releases.

	http://sourceforge.net/projects/brian-d-foy/

If, for some reason, I disappear from the world, one of the other
members of the project can shepherd this module appropriately.

=head1 AUTHOR

brian d foy, E<lt>bdfoy@cpan.orgE<gt>

=head1 COPYRIGHT

Copyright 2003-4, brian d foy, All rights reserved.

You may use this program under the same terms as Perl itself.

=cut

my $Script  = $FindBin::Script;

my %Referers;
my %Allowed;
my %Directories;

$|++;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

my %opts;
getopts('a:dD:fh:n:N:p:r:s:tu:vz', \%opts);

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
my $Debug   = defined $opts{d} || $ENV{WEBREAPER_DEBUG} || 0;
my $Verbose = defined $opts{v} || $ENV{WEBREAPER_VERBOSE} || $Debug || 0;

my $directory = $opts{D} || $ENV{WEBREAPER_DIR} ||
	do { print "Using current working directory\n" if $Verbose; cwd };

die "Could not change directory to $directory: $!" unless chdir $directory;

print_debug( "Options are", YAML::Dump( \%opts ) ) if $Debug;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
if( defined $opts{h} and $opts{h} )
	{
	foreach my $domain ( split /,/, $opts{h} )
		{
		add_allowed_domain( $domain );
		}
	}

die "I do not see a URL to process\n" unless @ARGV;

my $Url    = URI->new( $ARGV[-1] );
my @start  = ( $Url );

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
my $Domain = lc $Url->host;
$Domain    = add_allowed_domain( $Domain );
print "Domain is $Domain\n"               if $Debug;

my $Path   = dirname( $Url->path );
print "Path is $Path\n"                   if $Debug;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
my $authorization = encode_base64( join ":", @opts{qw(u p)} )
	if defined $opts{u} && defined $opts{p};
print "User is $opts{u}\n"                if $Debug;
print "Password is $opts{p}\n"            if $Debug;
print "Authorization is $authorization\n" if $Debug;
print "Sleep is $opts{s}\n"               if $Debug;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
if( defined $opts{r} and $opts{r} )
	{
	print "Referer is $opts{r}\n"                   if $Debug;
	$Referers{$start[0]} = $opts{r};
	my $referer_host = URI->new( $opts{r} )->host;
	print "Referer host is $referer_host\n"         if $Debug;
	$Allowed{ $referer_host } = 1;
	}

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
my $User_agent = $opts{a} || $ENV{WEBREAPER_UA} ||
	q|Mozilla/4.5 (compatible; iCab 2.9.7; Macintosh; U; PPC; Mac OS X)|;
print "User Agent is $opts{a}\n"             if $Debug;

my $UA = LWP::UserAgent->new;
$UA->agent( $User_agent );

my $cookie_jar = HTTP::Cookies->new();
$UA->cookie_jar( $cookie_jar );

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
my %Stats;
my %Seen;
my @Domains = ( $Domain );
my $count = 1;

init_stats();

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
$Stats{start} = Benchmark->new();
URL: while( @start )
	{
	my $url = shift @start;
	   $url = $url->canonical if ref $url;

	my $url_string = ref $url ? $url->as_string : $url;

	next URL if exists $Seen{ $url_string };

	$url_string =~ s/#.*//;
	if( exists $Seen{ $url_string } )
		{
		print "\tSkipping [$url]: Seen $Seen{ $url_string } times\n" if $Debug;
		next URL;
		}

	$Seen{ $url_string }++;

	printf "[%5d] %s ... ", $count++, $url_string if $Verbose;

	my $request   = make_request( $url );

	my $response  = $UA->request( $request );

	my( $base, $type, $data ) = process_response( $response );

	next URL unless( defined $base and defined $type );

	extract_links( $data, $base, $url, \@start ) if( $type eq 'text/html' );

	last URL if stop();

	whoa() if defined $opts{'s'};
 	}
$Stats{stop} = Benchmark->new;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
print_summary() if $Verbose;

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
tar() if $opts{t};
zip() if $opts{z};

# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
 # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
sub stop
	{
	my $stop = do {
		if( defined $opts{N} && $Stats{stored_files} >= $opts{N} )
			{
			print "Stopping after storing $opts{N} files\n";
			1;
			}
		elsif( defined $opts{n} && $Stats{requests} >= $opts{n} )
			{
			print "Stopping after storing $opts{n} files\n";
			1;
			}
		else
			{
			0
			}
		};

	return $stop
	}


sub init_stats
	{
	@Stats{ qw(stored_files requests) } = ( 0, 0 );
	}

sub extract_links
	{
	my( $data, $base, $referer, $urls ) = @_;

	print_debug( "Base is $base" ) if $Debug;
	my $extor = HTML::SimpleLinkExtor->new( $base );
	$extor->parse( $$data );

	my @links = $extor->links;
	print_debug( "Found " . @links . " links\n" ) if $Debug;

	use Data::Dumper;
	print_debug( Dumper( \%Allowed ) ) if $Debug;

	push @$urls,
		map { $Referers{ $_->[1] } = $referer; $_->[1] }
		grep {
			not exists $Seen{ $_->[1] }   and
			exists $Allowed{ $_->[0] }    and
			not $_->[1] =~ m/^javascript/ and
			$_->[1]->path =~ m/^\Q$Path/
			}
		map {
			eval {
				my $url    = URI->new( $_ );
				my $domain = lc $url->host;
				$domain ? [ $domain, $url ] : ();
				} || ();
			} $extor->links;

	print_debug( "Found " . @$urls . " links that I kept\n" ) if $Debug;

	print "Queue is now " . @$urls . "\n" if $Debug;
	}

sub process_response
	{
	my $response = shift;

	my $final_url = $response->request->uri->canonical->as_string;

	$Seen{ $final_url }++;
	print_debug( "Final is [$final_url]\n" ) if $Debug;

	return if $final_url =~ m/^file:/;

	my $file = get_store_name( $final_url );

	return if( -e $file && -s $file );

	my $data   = $response->content_ref;
	my $code   = $response->code;
	my $type   = $response->content_type;
	my $server = $response->server;

	print "\n\tServer is $server ... " if $Debug;
	print "$code\n" if $Verbose;

	$Stats{servers}{$server}++;
	$Stats{codes}{$code}++;

	return if $response->is_error;

	# if Not-Modified, we don't store the file but we need to
	# get the links from the stored version, because those
	# resources might have changed
	store( $data, $file ) if $file;

	my $base = $response->base;

	return( $base, $type, $data );
	}

sub print_summary
	{
	my $rule = "-" x 73 . "\n";

	print $rule;
	my $Time = timestr( timediff( @Stats{ qw(stop start) } ) );

	print "$FindBin::Script: $Time\n";

	my( $magnitude, $units ) = convert( $Stats{stored_bytes} );
	printf "\trequested %d urls\n", $Stats{requests};
	printf "\tstored %d files, %.2f %s\n", $Stats{stored_files},
		$magnitude, $units;

	foreach my $code ( sort { $a <=> $b } keys %{ $Stats{codes} } )
		{
		my $reason = status_message( $code );
		printf "%5d: %d %-20s\n", $Stats{codes}{$code}, $code, $reason;
		}
	print $rule;

	}

sub convert
	{
	my $number = shift;
	my @units = qw(bytes kB MB GB);

	print "Number is $number\n" if $Debug;
	my $nearest = floor( log( $number ) / log( 1024 ) );
	print "Floor is $nearest\n" if $Debug;

	foreach my $index ( 1 .. $nearest )
		{
		$number /= 1024;
		}

	return ( $number, $units[$nearest] )
	}

sub whoa
	{
	my $sleep = int rand( $opts{'s'} + 3 );
	print_debug( "Sleeping $sleep seconds\n" ) if $Debug;
	sleep $sleep;
	}

sub tar
	{
	eval "use Archive::Tar";
	if( $@ ) { carp "You need Archive::Tar to create tar archives"; return }

	print "Domains is @Domains\n" if $Debug;

	my @files = ();

	find({
		no_chdir => 1,
		wanted   => sub { push @files, $_ if -f $_ },
		}, @Domains );


	my $compression = eval "IO::Zlib" ? 9 : 0;
	my $extension   = $compression ? 'tgz' : 'tar';
	Archive::Tar->create_archive( "$Domains[0].$extension", 9, @files );
	}

sub zip
	{
	eval "use Archive::Zip";
	if( $@ ) { carp "You need Archive::Zip to create zip archives"; return }

	my $zip = Archive::Zip->new();

	foreach my $domain ( @Domains )
		{
		$zip->addTree( $domain );
		}

	$zip->writeToFileNamed( "$Domains[0].zip" );
	}

sub add_allowed_domain
	{
	my $domain = shift;

	$Allowed{$domain}++;

	if( $domain =~ m/(?:[012]?\d\d?)(?:\.[012]?\d\d?){1,3}/ )
		{
		my $iaddr = inet_aton( $domain );
		my $host = gethostbyaddr($iaddr, AF_INET);

		print "Matched IP address [$domain|$host]\n";
		$domain = $host;
		}

	$domain;
	}

sub make_request
	{
	my $url = shift;

	my $url_o = ref $url ? $url : URI->new( $url );
	my $host = $url_o->host;

	my $store_name = File::Spec->rel2abs( get_store_name( $url_o->as_string ) );

	#print "Store name is $store_name\n";

	if( -e $store_name && -s $store_name )
		{
		print "Using localfile: $store_name\n";
		$url_o = URI->new( "file://localhost/$store_name" );
		}

	my $request = HTTP::Request->new( GET => $url_o );

	$request->authorization_basic( $opts{u}, $opts{p} ) if $authorization;

	$request->referer( "$Referers{$url}" ) if defined $Referers{$url};

	$request->header( 'Accept-Language' => 'en'        );
	$request->header( 'Connection'      => 'close'     );
	$request->header( 'Accept'          => '*/*'       );
	$request->header( 'Host'            => $host       );
	$request->header( 'User-Agent'      => $User_agent );

	$Stats{requests}++;

	return $request;
	}

# XXX: break this into a function that determines the filename
# XXX: store should remember the directories it creates so it
# can tar those later
# XXX: store needs to remember how many bytes it wrote
sub get_store_name
	{
	my $url    = URI->new( shift );

	my $domain = $url->host;
	warn "No domain in $url\n" unless $domain;

	my $path   = $url->path || '/';
	print_debug( "Path is [$path]" ) if $Debug;

	$path =~ s|/$|/index.html|;
	$path =~ s|^/||;

	if( defined $opts{f} )
		{
		my $name = basename( $path );
		return catfile( $domain, $name );
		}

	if( $path =~ m|/$| )
		{
		print_debug( "Skipping path that looks like directory [$path]" )
			if $Debug;
		return;
		}

	$path =  catfile( $domain, $path );

	print_debug( "Store path is [$path]" ) if $Debug;

	return $path;
	}

sub store
 	{
	my $data_ref = shift;
	my $file     = shift;

	print_debug( "Saving [$file]" ) if $Debug;

	if( -d $file )
		{
		print_debug( "Error: file path is already a directory [ $file ]" )
			if $Debug;
		return;
		}

	my $dir = dirname $file;
	print_debug( "Directory is $dir" ) if $Debug;

	local @ARGV = ( $dir );

	if( -e $dir and not -d $dir )
		{
		print_debug( "Error: Removing file that should be a dir [$dir]" )
			if $Debug;
		unlink $dir;
		}
	else
		{
		$Directories{$dir}++;
		}

	eval { mkpath unless -e $dir };
	if( $@ )
		{
		print_debug( "Error: mkpath could not make $dir: $@" )
			if $Debug;
		return;
		}

	my $fh;
	unless( open $fh, "> $file" )
		{
		print_debug( "Could not open file [$file]: $!" )
			if $Debug;
		return;
		}

	print $fh $$data_ref;
	close $fh;

	$Stats{stored_bytes} += length $$data_ref;
	$Stats{stored_files}++;
	}

sub print_debug
	{
	print "!!!! " . join( "\n", @_ ) . "\n";
	}
