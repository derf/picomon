#!/usr/bin/env perl

use Mojolicious::Lite;
use Data::Dumper;
use DBI;
use 5.020;
use utf8;

our $VERSION = qx{git describe --dirty} || '0.00';

my $dbh = DBI->connect( "dbi:SQLite:dbname=picomon.sqlite", q{}, q{} );

$dbh->do(qq{
	create table if not exists hostdata (
		hostname text not null unique,
		integer last_contact not null,
		load1 integer,
		load5 integer,
		load15 integer,
		uptime integer
	)
});

app->defaults( layout => 'default' );
app->attr( dbh => sub { return $dbh } );

get '/' => sub {
	my ($self) = @_;

	$self->render(
		'main',
		version => $VERSION,
	);
};

post '/update' => sub {
	my ($self) = @_;
	my $params = $self->req->params->to_hash;

	say Dumper($params);

	say Dumper($self->req->uploads);

	$self->render(
		data => q{},
		status => 204,
	);
};

app->config(
	hypnotoad => {
		listen   => [ $ENV{PICOMON_LISTEN} // 'http://*:8099' ],
		pid_file => '/tmp/picomon.pid',
		workers  => 1,
	},
);

$ENV{MOJO_MAX_MESSAGE_SIZE} = 1048576;

app->start;
