# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# GeoIPPlugin is Copyright (C) 2017-2019 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::GeoIPPlugin::Core;

use strict;
use warnings;

use Foswiki::Func ();
use GeoIP2::Database::Reader ();
use LWP::Simple ();
use Archive::Tar ();

# SMELL: can't use Error as it can't catch GeoIP2 errors
use Try::Tiny;

use constant TRACE => 0; # toggle me

sub writeDebug {
  return unless TRACE;
  #Foswiki::Func::writeDebug("GeoIPPlugin::Core - $_[0]");
  print STDERR "GeoIPPlugin::Core - $_[0]\n";
}

sub new {
  my $class = shift;

  my $this = bless({
    databaseUrl => $Foswiki::cfg{GeoIPPlugin}{DatabaseUrl} || "https://geolite.maxmind.com/download/geoip/database/GeoLite2-City.tar.gz",
    databaseFile => $Foswiki::cfg{GeoIPPlugin}{DatabaseFile},
    @_
  }, $class);

  if ($Foswiki::cfg{PROXY}{HOST}) {
    $LWP::Simple::ua->proxy(['http', 'https', 'ftp'], $Foswiki::cfg{PROXY}{HOST});
  }

  return $this;
}

sub finish {
  my $this = shift;

  undef $this->{_reader};
  undef $this->{_model};
}

sub reader {
  my $this = shift;

  unless($this->{_reader}) {
    $this->{_reader} = GeoIP2::Database::Reader->new(
      file => $this->getDatabaseFile(),
    );
  }

  writeDebug("reader ".($this->{_reader}//"undef"));

  return $this->{_reader};
}

sub getDatabaseFile {
  my $this = shift;

  unless ($this->{databaseFile} && -e $this->{databaseFile}) {

    $this->{databaseFile} = Foswiki::Func::getWorkArea("GeoIPPlugin")."/GeoLite2-City.mmdb";

    my $refresh = Foswiki::Func::getRequestObject()->param("refresh") || '';

    if (-e $this->{databaseFile} && !($refresh =~ /^(on|geoip)/)) {
      writeDebug("already got the geolite database");

    } else {
      my $tarFile = Foswiki::Func::getWorkArea("GeoIPPlugin")."/GeoLite2-City.tar.gz";
      writeDebug("mirroring database from ".($this->{databaseUrl}//'undef')." to $tarFile");

      my $code = LWP::Simple::mirror($this->{databaseUrl}, $tarFile);
      writeDebug("code=$code");
      return if LWP::Simple::is_error($code);    

      if ($code != 304 || !(-e $this->{databaseFile})) {
        writeDebug("extracting database from tar file");
        my $tar = Archive::Tar->new($tarFile);
        my ($mmdbFile) = grep {/\.mmdb$/} $tar->list_files(); # first mmdb file
        $tar->extract_file($mmdbFile, $this->{databaseFile});    
      } else {
        writeDebug("not modified");
      }
    } 
  }

  writeDebug("reading database from $this->{databaseFile}");

  return $this->{databaseFile};
}

sub model {
  my ($this, $ip) = @_;

  my $model = $this->{_model}{$ip};

  if ($model) {
    $model = undef if $model eq '_unknown';
  } else {
    try {
      writeDebug("reading model for ip=$ip");
      $model = $this->{_model}{$ip} = $this->reader->city(ip=>$ip);
    } catch {
      $this->{_model}{$ip} = '_unknown';
      $model = undef;
    }
  }

  return $model
}

sub _inlineError {
  my $msg = shift;

  ($msg) = $msg =~ /^(.*?)(?: at \/|\n).*/;
  #writeDebug("ERROR: $msg");

  return "<span class='foswikiAlert'>$msg</span>";
}

sub city {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^city_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->city();
    die("unknown record") unless $rec;

    $result = $rec->confidence() // '' if $prop eq 'confidence';
    $result = $rec->geoname_id()  // ''if $prop eq 'id';
    $result = $rec->name() // '' if $prop =~ /^(city|name)?$/;

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("city - prop=$prop, result=$result");

  return $result;
}

sub continent {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^continent_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->continent();
    die("unknown record") unless $rec;

    $result = $rec->code() // '' if $prop eq 'code';
    $result = $rec->geoname_id() // ''  if $prop eq 'id';
    $result = $rec->name() // '' if $prop =~ /^(continent|name)?$/;

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("continent - prop=$prop, result=$result");

  return $result;
}

sub country {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^country_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->country();
    die("unknown record") unless $rec;

    $result = $rec->confidence() // '' if $prop eq 'confidence';
    $result = $rec->geoname_id() // '' if $prop eq 'id';
    $result = $rec->is_in_european_union() ? '1': '0' if $prop eq 'is_in_european_union';
    $result = $rec->iso_code() // '' if $prop eq 'code';
    $result = $rec->name() // '' if $prop =~ /^(country|name)?$/;

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("country - prop=$prop, result=$result");

  return $result;
}

sub location {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^location_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->location();
    die("unknown record") unless $rec;

    $result = $rec->accuracy_radius() // '' if $prop eq 'accuracy_radius';
    $result = $rec->average_income() // '' if $prop eq 'average_income';
    $result = $rec->latitude() // '' if $prop eq 'latitude';
    $result = $rec->longitude() // '' if $prop eq 'longitude';
    $result = $rec->population_density() // '' if $prop eq 'population_density';
    $result = $rec->time_zone() // '' if $prop eq 'time_zone';

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("location - prop=$prop, result=$result");

  return $result;
}

sub postal {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^postal_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->postal();
    die("unknown record") unless $rec;

    $result = $rec->code() // '' if $prop eq 'code';
    $result = $rec->confidence() // '' if $prop eq 'confidence';

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("postal - prop=$prop, result=$result");

  return $result;
}

sub traits {
  my ($this, $ip, $prop) = @_;

  $prop =~ s/^traits?_//;

  my $result;

  try {
    my $model = $this->model($ip);
    die("unknown model") unless $model;

    my $rec = $model->traits();
    die("unknown record") unless $rec;

    $result = $rec->autonomous_system_number() // '' if $prop eq 'autonomous_system_number';
    $result = $rec->autonomous_system_organization() // '' if $prop eq 'autonomous_system_organization';
    $result = $rec->connection_type() // '' if $prop eq 'connection_type';
    $result = $rec->domain() // '' if $prop eq 'domain';
    $result = $rec->is_anonymous() ? '1' : '0' if $prop eq 'is_anonymous';
    $result = $rec->is_anonymous_vpn() ? '1' : '0' if $prop eq 'is_anonymous_vpn';
    $result = $rec->is_hosting_provider() ? '1' : '0' if $prop eq 'is_hosting_provider';
    $result = $rec->is_legitimate_proxy() ? '1' : '0' if $prop eq 'is_legitimate_proxy';
    $result = $rec->is_public_proxy() ? '1' : '0' if $prop eq 'is_public_proxy';
    $result = $rec->is_satellite_provider() ? '1' : '0' if $prop eq 'is_satellite_provider';
    $result = $rec->is_tor_exit_node() ? '1' : '0' if $prop eq 'is_tor_exit_node';
    $result = $rec->isp() // '' if $prop eq 'isp';
    $result = $rec->organization() // '' if $prop eq 'organization';
    $result = $rec->user_type() // '' if $prop eq 'user_type';

    die("unknown property") unless defined $result;
  } catch {
    $result = _inlineError($_);
  };

  $result //= '';

  writeDebug("traits - prop=$prop, result=$result");

  return $result;
}

sub handleGEOIP {
  my ($this, $session, $params, $topic, $web) = @_;

  writeDebug("called GEOIP()");

  my $request = Foswiki::Func::getRequestObject();
  my $format = $params->{format} // '$city';
  my $ip = $params->{_DEFAULT} || $params->{ip} || $request->remoteAddress;
  $ip =~ s/^\s+|\s+$//g;

  $format =~ s/\$addr/$ip/g;
  $format =~ s/\$found/$this->model($ip)?'1':'0'/ge;
  $format =~ s/\$(city(?:_(?:confidence|name|id))?)\b/$this->city($ip, $1)/ge;
  $format =~ s/\$(continent(?:_(?:code|name|id))?)\b/$this->continent($ip, $1)/ge;
  $format =~ s/\$(country(?:_(?:confidence|id|is_in_european_union|code|name))?)\b/$this->country($ip, $1)/ge;
  $format =~ s/\$(location(?:_(?:accuracy_radius|average_income|latitude|longitude|population_density|time_zone)?))\b/$this->location($ip, $1)/ge;
  $format =~ s/\$(traits(?:_(?:autonomous_system_number|autonomous_system_organization|connection_type|domain|is_anonymous|is_anonymous_vpn|is_hosting_provider|is_legitimate_proxy|is_public_proxy|is_satellite_provider|is_tor_exit_node|isp|organization|user_type)?))\b/$this->traits($ip, $1)/ge;
  $format =~ s/\$(postal(?:_(?:code|confidence))?)\b/$this->postal($ip, $1)/ge;

  return Foswiki::Func::decodeFormatTokens($format);
}

1;
