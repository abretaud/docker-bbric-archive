#!/usr/bin/perl

use lib "/var/www/html/lib/int/";
use lib "/var/www/html/lib/ext/";
use lib "/var/www/html/corelib/";

use strict;
use warnings;
use utf8;
use Carp;

use DBI;
use File::Basename;
use Data::Dumper;
use JSON;
use LWP::UserAgent;
use XML::Twig;
use Digest::MD5 qw(md5_hex);


MAIN:
{
    ArchiveSync();
}

sub ArchiveSync
{
	my $sql_query =
"SELECT archive_file.id, archive_file.rawdata_filepath, archive_file.metadata_filepath, array_agg(archive_group.name) as groups FROM archive_file, archive_group_fileaccess, archive_group WHERE archive_group.id = archive_group_fileaccess.archive_group_id AND archive_group_fileaccess.archive_file_id = archive_file.id AND archive_file.collection = 'sequence' GROUP BY archive_file.id, archive_file.metadata_filepath, archive_file.rawdata_filepath";
	my $o_dbh = DBH('bbric');
	my $o_sth = $o_dbh->prepare($sql_query);
	$o_sth->execute();
	my $rh_files = $o_sth->fetchall_hashref('id');
	$o_sth->finish;
	$o_dbh->disconnect;

	my %h_data      = ();
	my $dest_mountpoint  = $ENV{'ARCHIVE_CLIENT_MOUNTPOINT'};
	my $destination = '/data/client';

	foreach my $rh_entry ( values(%$rh_files) )
	{
		my $filename = basename( $rh_entry->{'rawdata_filepath'} );
		$filename =~ s/^\w{32}_//;
		$filename =~ /^([^\.]+)/;
		my $barecode = md5_hex($1);

		if ( !exists $h_data{$barecode} )
		{
			my $o_twig    = new XML::Twig( keep_encoding => 1, pretty_print => 'indented' );
			my $o_xml     = $o_twig->parsefile( $rh_entry->{'metadata_filepath'} );
			my $data_path = $destination;
			$data_path .= '/' . join( '-', map { my $data = $_->text; $data =~ s/\s+/_/g; $_ = $data } $o_xml->get_xpath("//species") );
			$data_path .= '/' . join( '-', map { my $data = $_->text; $data =~ s/\s+/_/g; $_ = $data } $o_xml->get_xpath("//funding/source/project") );
			$data_path .= '/' . join( '-', map { my $data = $_->text; $data =~ s/\s+/_/g; $_ = $data } $o_xml->get_xpath("//date") );
			$data_path .= '/' . join( '_', map { my $data = $_->text; $data =~ s/\s+/_/g; $_ = $data } $o_xml->get_xpath("//strain") ) if ( $o_xml->get_xpath("//strain") > 0 );
			$data_path .= '/' . join( '_', map { my $data = $_->text; $data =~ s/\s+/_/g; $_ = $data } $o_xml->get_xpath("//genotype") ) if ( $o_xml->get_xpath("//genotype") > 0 );
			$h_data{$barecode}{path} = $data_path;
			system("mkdir -p $data_path") if ( !-e $data_path );
		}

		my $dest_path = $rh_entry->{'rawdata_filepath'};
		$dest_path =~ s|/data/store|$dest_mountpoint|g;

		system("ln -s $dest_path $h_data{$barecode}{path}/$filename") if ( !-l "$h_data{$barecode}{path}/$filename" );
	}
}

sub DBH
{
	my $db = shift;

	my $dbh = DBI->connect("dbi:Pg:database=$ENV{'DB_NAME'};host=$ENV{'DB_HOST'};port=5432", $ENV{'DB_USER'}, $ENV{'DB_PASS'} ) or Carp::croak("Connexion to $ENV{'DB_NAME'} failed");
	return $dbh;
}
