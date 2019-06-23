BEGIN {
  use TestInit;
#    chdir 't' if -d 't';
#    @INC = qw(../lib uni .);
  push @INC, 'uni';
    require "case.pl";
}

casetest("Lower", \%utf8::ToSpecLower,
	 sub { lc $_[0] }, sub { my $a = ""; lc ($_[0] . $a) },
	 sub { lcfirst $_[0] }, sub { my $a = ""; lcfirst ($_[0] . $a) });
