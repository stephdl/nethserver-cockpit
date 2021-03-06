#!/usr/bin/perl

#
# Copyright (C) 2018 Nethesis S.r.l.
# http://www.nethesis.it - nethserver@nethesis.it
#
# This script is part of NethServer.
#
# NethServer is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License,
# or any later version.
#
# NethServer is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with NethServer.  If not, see COPYING.
#

use strict;
use warnings;
use JSON;
use POSIX qw(getgroups);

sub read_json
{
    my $file = shift || return undef;
    return undef if (! -e $file);

    my $json;
    {
        local $/; #Enable 'slurp' mode
        open my $fh, "<", $file or return undef;
        $json = <$fh>;
        close $fh;
    }

    return decode_json($json);
}

sub whoami
{
    my $user = scalar getpwuid $<;
    # strip domain
    $user =~ s/@.*$//;
    return $user;
}

sub list_applications
{
    my @apps;
    foreach my $manifest (glob("/usr/share/cockpit/nethserver/applications/*.json")) {
        my $app = read_json($manifest);
        push(@apps, $app->{'id'});
    }
    return @apps;
}

sub get_acl
{
    my $user = shift;
    my $role = shift;
    my $roles = read_json("/etc/nethserver/cockpit/authorization/roles.json");

    if(exists($roles->{$role})) {
        return $roles->{$role}
    }

    return {};
}

sub list_system_routes
{
    my $ret = read_json("/etc/nethserver/cockpit/authorization/system-routes.json");
    return @$ret;
}

sub in_array {
    my (@arr,$search_for) = @_;
    return grep {$search_for eq $_} @arr;
}

sub get_role
{
    my $user = shift || return undef;
    my @groups = getgroups();
    my $roles = read_json("/etc/nethserver/cockpit/authorization/roles.json");
    foreach my $g (getgroups()) {
        my $gname = getgrgid($g);
        $gname =~ s/@.*$//; # strip domain
        foreach my $r (keys $roles) {
            return $gname if ($r eq $gname);
        }
    }
    return '';
}

1
