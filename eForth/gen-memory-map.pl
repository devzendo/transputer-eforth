#!/usr/bin/perl
#
# Extract key addresses, in order, from the end of the .LST file to give the
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
  if
(/^(DOLIT|CMOVE|SZERO|AT|RFROM|MemStart|COLDD|UZERO|ULAST|CODEE|COLD|COLD1|NTOP|LASTN|NAMEE|UPP|SPP|TIBB|RPP|EM)\s/) {
    push @address_lines, $_;
  }
}
close $fh;

foreach (@address_lines) {
  print "$_\n";
}
