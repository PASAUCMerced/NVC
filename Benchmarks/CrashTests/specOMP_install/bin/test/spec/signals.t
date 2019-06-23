#!specperl

BEGIN {
  if ($^O =~ /MSWin/i
      # NOSIGTEST: || 1
      ) {
      print "1..0 # Skip: No SIGCHLD testing needed\n";
      exit(0);
  }
  eval {
          use POSIX qw(:signal_h :errno_h :sys_wait_h);
       };
  if ($@) {
      print "1..0 # Skip: POSIX module is missing\n";
      exit(0);
  }

  # Not needed now that all child handling is done via polling
  print "1..0 # Skip: Not used any longer\n";
  exit(0);
}

sub REAPER {
    my $child;
    my $handled = 0;
    while (($child = waitpid(-1, WNOHANG)) > 0) {
        if (WIFEXITED($?)) {
          my $exit = $? >> 8;
          my $sig = $? & 127;
#          print '# '.join(' ', gettimeofday)." $child: exited $exit (signal $sig)\n";
          $::ended++;
          $handled++;
          my $found = 0;
          for(my $i = 0; $i < @running; $i++) {
            if ($::running[$i] == $child) {
              $::running[$i] = undef;
              $found = 1;
              last;
            }
          }
          if ($found == 0) {
            print "# Could not locate slot for child PID $child\n";
          }
        } else {
          print "# $child: strange return: $?\n";
        }
    }
    print "# Handled $handled children this time\n" if $handled != 1;
    $SIG{'CHLD'} = \&main::REAPER;
}

my @try = (
           'DEFAULT',
           #'IGNORE'
          );

print "1..".(@try + 0)."\n";

for(my $k = 1; $k <= @try; $k++) {
  my $try = $try[$k - 1];
  print "# Test SIGCHLD = $try\n";
  $SIG{'CHLD'} = \&main::REAPER;
  my $start = time();
  my $started = 0;
  $::ended = 0;
  for(my $i = 0.1; $i <= 5; $i += 0.1) {
    my $pid = fork();
    if ($pid) {
      $started++;
      push @::running, $pid;
print "# Delay for $pid is $i\n";
    } else {
      $SIG{'CHLD'} = 'DEFAULT';
      sleep(int($i) || 1);
      exit(int($i));
    }
  }
  # Sleep for 1 second; let some children be reaped
  $start = time();
  while((time() - $start) < 1) {
    # Waste time spinning
  }
  #print "# Begin testing (".(time() - $start)." elapsed)\n";
  $start = time();
  my $oldsig = $SIG{'CHLD'};
  $SIG{'CHLD'} = $try;
  print "# $started started; $::ended already finished (".($started - $::ended)." still running)\n";
  # This would be the critical section that doesn't want to be disturbed
  while((time() - $start) <= 2) {
    # Waste time spinning
  }
  print "# $started started; $::ended already finished (".($started - $::ended)." still running)\n";
  print "# End testing (".(time() - $start)." elapsed from test start)\n";
  $SIG{'CHLD'} = $oldsig;
  my $tries = 0;
  $start = time();
  while($tries < 5 && ($started > $::ended || grep { defined } @::running)) {
    my $localstart = time();
    while((time() - $localstart) < 1) {
      # Waste time spinning
    }
    $tries++;
  }
  print "# End test of $try (".($started - $::ended)." children MIA; ".(time() - $start)." elapsed since end of test)\n";
  $SIG{'CHLD'} = 'DEFAULT';
  if ($started > $::ended || grep { defined } @::running) {
      print "# MIA list:\n";
      for(my $i = 0; $i < @::running; $i++) {
          next unless defined $::running[$i];
          my $stillgoing = kill 0, $::running[$i];
          print "#  $i: $::running[$i] (".($stillgoing ? 'running' : 'GONE').")\n";
      }
      print "not ok $k # some child processes went missing\n";
  } else {
      print "ok $k\n";
  }
  $::ended = 0;
  @::running = ();
}
