#!/usr/bin/env perl
use strict;
use warnings;

App::Dispatch->new(
    "/etc/dispatch.conf",
    "/etc/dispatch",
    "$ENV{HOME}/.dispatch.conf",
)->dispatch(@ARGV);

BEGIN {

    package App::Dispatch;

    sub programs { shift->{programs} }
    sub config   { shift->{config} }

    sub new {
        my $class = shift;

        my $self = bless {
            config   => {},
            programs => {},
        } => $class;

        $self->read_config($_) for @_;

        return $self;
    }

    sub read_config {
        my $self = shift;
        my ($file) = @_;
        unless ( -e $file ) {
            $self->config->{$file} = "No such file or directory: '$file'.";
            return;
        }
        $self->config->{$file} = 1;

        if ( -d $file ) {
            opendir( my $dir, $file ) || die "Failed to open '$file': $!\n";
            $self->read_config("$file/$_") for sort grep { $_ !~ m/^\./ } readdir($dir);
            close($dir);
            return;
        }

        open( my $fh, '<', $file ) || die "Failed to open '$file': $!\n";

        my $program;
        my $ln = 0;
        while ( my $line = <$fh> ) {
            $ln++;
            chomp($line);
            next unless $line;
            next if $line =~ m/^#/;

            if ( $line =~ m/^\s*\[([a-zA-Z0-9_]+)\]\s*$/i ) {
                $program = $1;
                $self->programs->{$program} ||= {};
                next;
            }

            if ( !$program ) {
                die "Error in '$file', line $ln: '$line'.\nItem is not under a program specification.\n";
            }

            if ( $line =~ m/^\s*([a-zA-Z0-9_]+)\s*=\s*(\S+)\s*$/ ) {
                $self->programs->{$program}->{$1} = $2;
                next unless $1 eq 'SYSTEM' && $file ne '/etc/dispatch.conf';
                die "SYSTEM alias can only be specified in /etc/dispatch.conf.\n";
            }

            die "'$file' line $ln not valid: '$line'\n";
        }

        close($fh);
    }

    sub dispatch {
        my $self = shift;
        my ( $program, @argv ) = @_;

        die "No program specified\n" unless $program;

        return $self->debug if $program eq 'DEBUG';

        my @cascade;

        push @cascade => shift @argv while @argv && $argv[0] ne '--';
        shift @argv;

        @cascade = ( 'DEFAULT', 'SYSTEM' ) unless @cascade;

        my $conf = $self->programs->{$program} || {};

        my $run;
        for my $item (@cascade) {
            if ( $item eq 'ENV' ) {
                $run = $program;
            }
            elsif ( my $alias = $conf->{$item} ) {
                next unless -x $alias;
                $run = $alias;
            }
            elsif ( -x $item ) {
                $run = $item;
            }
        }
        exec( $run, @argv ) if $run;

        print STDERR "Could not find valid '$program' to run.\n";
        print STDERR "Searched: " . join( ', ', @cascade ) . "\n";
        print STDERR "'$program' config: ";
        if ( keys %$conf ) {
            print "\n";
            for my $alias ( keys %$conf ) {
                print STDERR "  $alias = $conf->{$alias}\n";
            }
        }
        else {
            print STDERR "No config for '$program'\n";
        }

        print STDERR "\n";
        exit 1;
    }

    sub debug {
        my $self = shift;
        require Data::Dumper;
        print Data::Dumper::Dumper($self);
    }
}
