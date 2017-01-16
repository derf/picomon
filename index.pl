#!/usr/bin/env perl

use Mojolicious::Lite;
use DateTime;
use DBI;
use 5.020;
use utf8;

our $VERSION = qx{git describe --dirty} || '0.00';

my $dbh = DBI->connect( "dbi:SQLite:dbname=picomon.sqlite", q{}, q{} );

my @int_fields = (
	qw(
	  load1 load5 load15 num_threads
	  mem_total mem_free mem_available
	  swap_total swap_free
	  uptime
	  )
);
my @text_fields = (
	qw(
	  debian_version
	  df_raw
	  kernel_version
	  os
	  )
);

$dbh->do(
	qq{
	create table if not exists hostdata (
		hostname text not null unique,
		last_contact integer not null,
	}
	  . join( q{, }, map { "$_ integer" } @int_fields ) . q{, }
	  . join( q{, }, map { "$_ text" } @text_fields ) . q{)}
);

sub update_db {
	my %data = @_;
	my @query_data;

	my @fields    = ( qw(hostname last_contact), @int_fields, @text_fields );
	my @values    = (q(?)) x @fields;
	my $query_str = sprintf(
		'insert or replace into hostdata (%s) values (%s)',
		join( q{,}, @fields ),
		join( q{,}, @values )
	);

	my $query = $dbh->prepare($query_str);

	for my $field (@fields) {
		if ( exists $data{$field} ) {
			chomp( $data{$field} );
			push( @query_data, $data{$field} );
		}
		else {
			push( @query_data, undef );
		}
	}

	$query->execute(@query_data);
}

app->defaults( layout => 'default' );
app->attr( dbh => sub { return $dbh } );

get '/' => sub {
	my ($self) = @_;
	my @hostdata;

	my $hostdata_raw = $dbh->selectall_arrayref(
		qq{select * from hostdata order by last_contact desc}
	);
	my @fields = (qw(hostname contact), @int_fields, @text_fields);

	for my $host (@{$hostdata_raw}) {
		push(@hostdata, {
			map { ($fields[$_], $host->[$_]) } (0 .. $#fields)
		});
	}

	$self->render(
		'main',
		hosts => \@hostdata,
		version => $VERSION,
	);
};

post '/update' => sub {
	my ($self) = @_;
	my $param = $self->req->params->to_hash;
	my $now = DateTime->now( time_zone => 'Europe/Berlin' );

	my %data = (
		hostname     => $param->{hostname},
		last_contact => $now->epoch,
	);

	if ( exists $param->{debian} ) {
		$data{debian_version} = $param->{debian};
	}
	if ( exists $param->{uptime} ) {
		$data{uptime} = int( ( split( qr{ }, $param->{uptime} ) )[0] );
	}
	if ( exists $param->{load} ) {
		if ( $param->{load}
			=~ m{ ^ (?<l1> \S+ ) \s (?<l5> \S+ ) \s (?<l15> \S+ ) \s \d+ / (?<nthr> \d+ ) }x
		  )
		{
			$data{load1}       = $+{l1};
			$data{load5}       = $+{l5};
			$data{load15}      = $+{l15};
			$data{num_threads} = $+{nthr};
		}
	}
	if ( exists $param->{uname} ) {
		my ( $os, $kv ) = split( qr{ }, $param->{uname} );
		$data{os}             = $os;
		$data{kernel_version} = $kv;
	}
	if ( exists $param->{df} ) {
		$data{df_raw} = $param->{df};
	}
	if ( exists $param->{meminfo} ) {
		my %meminfo
		  = ( $param->{meminfo} =~ m{ ^ (\S+) : \s+ (\d+) \s kB $ }gmx );
		$data{mem_total}     = $meminfo{MemTotal};
		$data{mem_free}      = $meminfo{MemFree};
		$data{mem_available} = $meminfo{MemAvailable};
		$data{swap_total}    = $meminfo{SwapTotal};
		$data{swap_free}     = $meminfo{SwapFree};
	}

	update_db(%data);

	$self->render(
		data   => q{},
		status => 204,
	);
};

app->config(
	hypnotoad => {
		listen => [ $ENV{LISTEN} // 'http://*:8099' ],
		pid_file => '/tmp/picomon.pid',
		workers  => 1,
	},
);

$ENV{MOJO_MAX_MESSAGE_SIZE} = 1048576;

app->start;
