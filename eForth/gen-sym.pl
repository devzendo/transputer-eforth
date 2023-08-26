#!/usr/bin/perl
#
# Extract all addresses, in order, from the end of the .LST file to give the
# eForth memory map.
use warnings;
use strict;
open(my $fh, "<", "EFORTH.LST") or die "Can't open EFORTH.LST: $!\n";
my $found_symbol_table = 0;
my @address_lines = ();
while (<$fh>) {
  chomp;
  if (/^Symbol Table - by Address/) {
    $found_symbol_table = 1;
  }
  next unless $found_symbol_table;
  if ($_ !~ /StartTime|CALLL|Symbol Table|DevZendo.org|InMos/) {
    push @address_lines, $_ if $_;
  }
}
close $fh;

foreach (@address_lines) {
  print "$_\n";
}
