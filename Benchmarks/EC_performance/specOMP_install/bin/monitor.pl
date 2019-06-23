#
# monitor.pl
#
# Copyright 1999-2011 Standard Performance Evaluation Corporation
#  All Rights Reserved
#
# $Id: monitor.pl 1198 2011-09-20 21:25:53Z CloyceS $

use strict;

my $version = '$LastChangedRevision: 1198 $ '; # Make emacs happier
$version =~ s/^\044LastChangedRevision: (\d+) \$ $/$1/;
$::tools_versions{'monitor.pl'} = $version;

sub monitor_shell {
    my ($name, $config, @refs) = @_;
    my @cmds = ();
    foreach my $line (grep { /^$name\d*$/ } $config->list_keys) {
      my ($idx) = $line =~ m/^$name(\d*)$/;
      my $val = $config->accessor($line);
      $cmds[$idx] = $val;
    }
    # The linefeeds will be substituted with the correct command join
    # character ('&&' for Windows cmd, ';' for all others)
    my $cmd = join("\n", @cmds);
    # Arrange for mini-batch files to work
    if (   $^O =~ /MSWin/
        && $cmd !~ /^\s*$/
       	&& $cmd !~ /^cmd /) {
	$cmd = 'cmd /E:ON /D /C "'.$cmd.'"';
    }
    if ($cmd =~ m#^cmd # && $^O =~ /MSWin/) {
	# Convert line feeds into && for cmd.exe
	$cmd =~ s/[\r\n]+/\&\&/go;
    } else {
	$cmd =~ s/[\r\n]+/;/go;
    }

    my $rc = undef;

    # Cull out non-hash entries
    @refs = [ grep { (::reftype($_) eq 'HASH') } @refs ];

    if (defined($cmd) && ($cmd ne '')) {
	Log(0, "Executing $name: $cmd\n");
	#$rc = log_system_noexpand($cmd, $name, 0, [ $config, @refs ], 0);
	$rc = log_system($cmd, $name, istrue($config->accessor_nowarn('fake')), [ $config, @refs ], 0);
	if ($rc) {
	    Log(0, "$name returned non-zero exit code ($rc)\n");
	    do_exit(1);
        }
    }

    $cmd = $config->accessor_nowarn("${name}_perl");
    if (defined($cmd) && ($cmd ne '')) {
        ::Log(0, "NOTICE: If you use the monitor_*_perl feature, please run\n");
        ::Log(0, "convert_to_development, uncomment the code in monitor.pl, fix the bugs,\n");
        ::Log(0, "and send the patch to ${main::lcsuite}support\@spec.org.  We'll put the\n");
        ::Log(0, "next release if they're not dangerous.\n");
        ::Log(0, "For now, your setting for ${name}_perl is being ignored.\n");
#	my $s = new Safe 'tmp';
#	if (istrue($main::runconfig->safe_eval())) {
#            $s->permit_only(':base_core', ':base_mem', 'padany', 'padsv',
#                            'padav', 'padhv', 'sprintf');
#	} else {
#	    $s->deny_only();
#	}
#	$s->share('%ENV', '$main::runconfig');
#	if (istrue($config->accessor_nowarn('fake'))) {
#	    Log(0, "_NOT_ executing the following perl code:\n---------------\n$cmd\n-----------------\n");
#	} else {
#	    $s->reval($cmd);
#	}
#	if ($@) {
#	    Log(0, "Error executing ${name}_perl:\n$@\n");
#	}
#	no strict 'refs';
#	%{*{"main::".$s->root."::"}{HASH}} = ();
    }
}

sub monitor_pre        { monitor_shell('monitor_pre',        @_); }
sub monitor_pre_run    { monitor_shell('monitor_pre_run',    @_); }
sub monitor_pre_bench  { monitor_shell('monitor_pre_bench',  @_); }
sub monitor_post_bench { monitor_shell('monitor_post_bench', @_); }
sub monitor_post       { monitor_shell('monitor_post',       @_); }

1;
