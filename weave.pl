#!/usr/bin/env perl
#
# weave.pl - overlays multiple directories into one with symlinks
#
# Originally written by Sam Hanes <sam@maltera.com>. 
# To the extent possible under law, the author has waived all copyright
# and related or neighboring rights in this work, which was originally
# published in the Unted States. Attribution is appreciated but not
# required. The complete legal text of the release is available at
# http://creativecommons.org/publicdomain/zero/1.0/

use strict;
use warnings;

# import the S_IF* constants for testing file types
use Fcntl ":mode";

use Cwd qw(abs_path);

our $target;

########################################################################
# Subroutines                                                          #
########################################################################

sub type_name ($) {
    my ($mode) = @_;
    return "file"       if (S_ISREG( $mode ));
    return "directory"  if (S_ISDIR( $mode ));
    return "symlink"    if (S_ISLNK( $mode ));
    return "special";
}

# @param $path the source-relative path to weave
# @param @sources the list of sources for the directory
sub weave_dir {
    our $target;
    my ($path, @sources) = @_;
    my %mapped;
    my %subdirs;
    
    # create the target directory and clone the source's permissions
    {   my $targetpath = "$target/$path";
    
        if (!mkdir $targetpath) {
            print STDERR 
                "warning: unable to create target directory '$path': $!\n";
            return;
        }

        my @dirstat = stat( $sources[ 0 ] . "/$path" );
        chmod S_IMODE( $dirstat[ 2 ] ), $targetpath;
        chown $dirstat[ 4 ], $dirstat[ 5 ], $targetpath;
    }

    SOURCE:
    foreach my $source (@sources) {
        my $dirpath = "$source/$path";
        my $dir;

        if (!opendir $dir, $dirpath) {
            print STDERR "warning: unable to open directory "
                . "'$path' in '$source': $!\n";
            next SOURCE;
        }
        
        FILE:
        while (readdir $dir) {
            next FILE if (/^\./);

            my $entry = "$path/$_";
            my $entrypath ="$dirpath/$_";

            # try to get the entry's metainformation
            my @stat = lstat $entrypath;
            if (!@stat) {
                print STDERR
                    "warning: unable to stat '$entry' in '$source'\n";
                next FILE;
            }

            my $mode = S_IFMT( $stat[ 2 ] );

            # check whether we've already mapped the entry
            my $mapping = $mapped{ $entry };
            if ($mapping) {
                my %mapping = %$mapping;
                my $mapmode = S_IFMT( @{ $mapping{ 'stat' } }[ 2 ] );

                # show a warning if the masked entry is of a
                # different type than the one that was chosen
                if ($mapmode != $mode) {
                    print STDERR
                        "warning: type conflict on '$entry':\n"
                        . "    using a " . type_name( $mapmode )
                            . " from '" . $mapping{ 'source' } . "'\n"
                        . "    found a " . type_name( $mode )
                            . " in '$source'\n";

                    next FILE;
                }

                if ($mode & S_IFDIR) {
                    push( @{ $subdirs{ $entry } }, $source );
                }

                next FILE;
            }


            if (S_ISREG( $mode )) {
                if (!link $entrypath, "$target/$entry") {
                    print STDERR
                        "warning: unable to create link for "
                        . "'$entry' from '$source'\n";
                    next FILE;
                }
            } elsif (S_ISDIR( $mode )) {
                $subdirs{ $entry } = [ $source ];
            } elsif (S_ISLNK( $mode )) {
                my $destpath = abs_path( $entrypath );
                if (!symlink $destpath, "$target/$entry") {
                    print STDERR
                        "warning: unable to create symlink for "
                        . "'$entry' in '$source' to '$destpath'\n";
                    next FILE;
                }
            } else {
                print STDERR "warning: enountered special file "
                    . "'$entry' in '$source'\n";
                next FILE;
            }
                
            # remember the mapping
            $mapped{ $entry } = {
                "source"    => $source,
                "stat"      => \@stat
            };
        }

        closedir $dir;
    }

    for my $subdir (keys %subdirs) {
        weave_dir( $subdir, @{ $subdirs{ $subdir } } );
    }
}

########################################################################
# Executable Body                                                      #
########################################################################

if ($#ARGV < 1) {
    print STDERR "usage: weave.pl <sources...> <destination>\n";
    exit 1;
}

my @sources = @ARGV[ 0 .. $#ARGV - 1 ];
$target = $ARGV[ $#ARGV ];

# check that the source directories exist and the target doesn't
{   my $errors = "";
    my $devnum;

    foreach my $source (@sources) {
        if (!-e $source) {
            $errors .= "source '$source' does not exist\n";
        } elsif (!-d $source) {
            $errors .= "source '$source' is not a directory\n";
        }

        my $curdev = ( stat(_) )[ 0 ];
        if (defined $devnum) {
            if ($devnum != $curdev) {
                $errors .= "source '$source' is on another device\n";
            }
        } else {
            $devnum = $curdev;
        }
    }

    if (-e $target) {
        $errors .= "target '$target' already exists\n";
    }

    if ("" ne $errors) {
        print STDERR $errors;
        exit 2;
    }
}

weave_dir( "", @sources );


# vim: se sts=4 sw=4 et :miv
