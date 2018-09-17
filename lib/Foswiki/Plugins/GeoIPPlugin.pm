# Plugin for Foswiki - The Free and Open Source Wiki, https://foswiki.org/
#
# GeoIPPlugin is Copyright (C) 2017-2018 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::GeoIPPlugin;

use strict;
use warnings;

use Foswiki::Func ();

our $VERSION = '1.00';
our $RELEASE = '10 Sep 2018';
our $SHORTDESCRIPTION = 'Geo Location Information';
our $NO_PREFS_IN_TOPIC = 1;
our $core;

sub initPlugin {

  Foswiki::Func::registerTagHandler('GEOIP', sub { return getCore()->handleGEOIP(@_); });

  return 1;
}

sub getCore {
  unless (defined $core) {
    require Foswiki::Plugins::GeoIPPlugin::Core;
    $core = Foswiki::Plugins::GeoIPPlugin::Core->new();
  }
  return $core;
}

sub finishPlugin {
  $core->finish if $core;
  undef $core;
}

1;
