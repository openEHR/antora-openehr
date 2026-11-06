#!/bin/bash
set -euo pipefail

# Step 10c: Resolve <<...>> cross references that point to another page
#
# The legacy specs were single documents, so `<<target>>` reached any section, chapter or
# bibliography entry. After the migration splits a document into pages, Asciidoctor only
# resolves `<<...>>` within the page; everything else becomes a dead `#target` link
# (no Antora warning, only a broken jump in the HTML). Per component version this step
# indexes, from the sources:
#
#   - page titles (`= Title`)                      -> page
#   - section titles and their auto ids (`_x_y`)   -> page#id
#   - explicit ids (`[[id]]`, `[#id]`, `anchor:id[]`) -> page#id
#
# (a module partial counts as part of the page that includes it), then rewrites in module
# pages and partials:
#
#   <<id[,text]>>     id on another page   -> <<[module:]page.adoc#id,text>>
#   <<Section Title>> section on another page -> <<[module:]page.adoc#_id,Section Title>>
#   <<Chapter Title>> a page title         -> xref:[module:]page.adoc[Chapter Title]
#   <<Key>>           key in references.bib -> cite:[Key]
#
# A fragment starting with "_" is written "#{underscore}id" (attribute in global-vars.yml):
# the quotes pass runs before macros and reads "#_id ... _" as italics, and Antora keeps a
# backslash escape in the link; attributes are substituted after quotes, before macros. Targets on the same page, ambiguous ones
# and unknown ones are left unchanged and listed.
# Class references (`_x_class`) are handled by steps 10 / 10b.
#
# Run from repo root (inside the target specification repo), after step 10.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIB_FILE="${BIBTEX_FILE:-$SCRIPT_DIR/../../resources/references.bib}"

echo "Step 10c: Resolving cross references to other pages..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! compgen -G "modules/*/pages/*.adoc" >/dev/null; then
  echo "No module pages; skipping."
  echo ""
  exit 0
fi

BIB_FILE="$BIB_FILE" perl -CSD -e '
use strict; use warnings;
use File::Find;

my %bib;
if (open my $b, "<", $ENV{BIB_FILE}) { while (<$b>) { $bib{$1} = 1 if /^\s*@\w+\s*\{\s*([^,\s]+)\s*,/ } close $b }

sub slurp { my $f = shift; open my $h, "<", $f or return (); my @l = <$h>; close $h; return @l }
sub clean { my $t = shift; $t =~ s/\r?\n$//; $t =~ s/\s+\[\..*$//; $t =~ s/\s+$//; return $t }
sub auto_id {            # Asciidoctor default ids with idprefix/idseparator "_"
  my $t = lc shift;
  $t =~ s/<[^>]+>//g;
  $t =~ s/&(?:[a-z][a-z]+\d{0,2}|#\d{2,5}|#x[\da-f]{2,4});//g;
  $t =~ s/[^ \w\-.]+//g;
  $t =~ s/[ .\-]+/_/g;
  $t =~ s/_+$//;
  return "_$t";
}
sub norm { my $t = lc shift; $t =~ s/\s+/ /g; $t =~ s/^\s+|\s+$//g; return $t }

# --- which page includes each module partial --------------------------------
my (@pages, %owner);
find({ wanted => sub { push @pages, $File::Find::name if m{\.adoc$} && $File::Find::dir =~ m{^modules/[^/]+/pages(/|$)} }, no_chdir => 1 }, "modules");
@pages = sort @pages;
for my $p (@pages) {
  my ($m) = $p =~ m{^modules/([^/]+)/};
  my @queue = ($p); my %seen;
  while (my $f = shift @queue) {
    next if $seen{$f}++;
    for (slurp($f)) {
      next unless /^include::partial\$([^\[]+)\[/;
      my $part = "modules/$m/partials/$1";
      next unless -f $part;
      $owner{$part}{$p} = 1;
      push @queue, $part;
    }
  }
}

# --- index ids and titles ------------------------------------------------------
my (%id_page, %title, %page_title, %id_title, %page_anchor);   # id -> {page}, title -> {page#id}, title -> {page}, id -> title
sub index_file {
  my ($f, $page) = @_;
  my ($inblock, $pending, $first) = (0, undef, 1);
  for my $line (slurp($f)) {
    (my $l = $line) =~ s/\r?\n$//;
    if ($l =~ /^(-{4,}|\.{4,}|\+{4,}|`{3,})\s*$/) { $inblock = !$inblock; next }
    next if $inblock;
    while ($l =~ /\[\[([A-Za-z_][\w:.\-]*)(?:,[^\]]*)?\]\]|\[#([A-Za-z_][\w:.\-]*)[\].,%]|anchor:([A-Za-z_][\w:.\-]*)\[/g) {
      my $id = $1 // $2 // $3; $id_page{$id}{$page} = 1;
      $pending = $id if $l =~ /^\[(?:\[[^\]]+\]|#[^\]]+)\]\s*$/;
    }
    # id= in block or macro attribute lists: [id=x, ...], image::a.svg[id=x, ...]
    while ($l =~ /[\[,]\s*id=["\x27]?([A-Za-z_][\w:.\-]*)/g) { $id_page{$1}{$page} = 1 }
    if ($l =~ /^= (\S.*)$/ && $first && $f eq $page) {
      my $t = clean($1);
      $page_title{norm($t)}{$page} = 1;
      $id_page{auto_id($t)}{$page} = 1;   # the auto id of a chapter title: the page itself
      $id_title{auto_id($t)} //= $t;
      # an id set on the page title has no anchor in the page: it means the page
      if (defined $pending) { $page_anchor{$pending} = 1; $id_title{$pending} //= $t }
    } elsif ($l =~ /^={2,6} (\S.*)$/) {
      my $t = clean($1);
      my $id = $pending // auto_id($t);
      $id_page{$id}{$page} = 1;
      $id_title{$id} //= $t;
      $title{norm($t)}{"$page#$id"} = 1;
    }
    $pending = undef unless $l =~ /^\[/;
    $first = 0 if $l =~ /^=/;
  }
}
for my $p (@pages) { index_file($p, $p) }
for my $part (sort keys %owner) { index_file($part, $_) for keys %{$owner{$part}} }

sub pick {            # several candidates: keep those in the referring module, if that is unique
  my ($mod, @c) = @_;
  return @c if @c <= 1;
  my @same = grep { m{^modules/\Q$mod\E/} } @c;
  return @same == 1 ? @same : @c;
}

sub frag {            # "#_id" -> "#{underscore}id": an unescaped "#_" opens italics when another "_" follows
  my $id = shift;
  return $id =~ /^_/ ? "#{underscore}" . substr($id, 1) : "#$id";
}

sub target {          # page path -> xref target relative to the referring module
  my ($page, $from_mod) = @_;
  my ($m, $rel) = $page =~ m{^modules/([^/]+)/pages/(.+)$};
  return ($m eq $from_mod ? "" : "$m:") . $rel;
}

# --- rewrite -------------------------------------------------------------------
my (%stat, %unresolved);
my @files = @pages;
push @files, sort keys %owner;
for my $f (@files) {
  my ($m) = $f =~ m{^modules/([^/]+)/};
  my @owners = $f =~ m{/pages/} ? ($f) : sort keys %{$owner{$f} || {}};
  next unless @owners == 1;            # partial on several pages: leave it
  my $here = $owners[0];
  my @lines = slurp($f); my $inblock = 0; my $changed = 0;
  for (@lines) {
    if (/^(-{4,}|\.{4,}|\+{4,}|`{3,})\s*\r?$/) { $inblock = !$inblock; next }
    next if $inblock;
    s{<<([^<>,\[\]]+?)(?:,\s*([^<>]*?))?>>}{
      my ($x, $text, $orig) = ($1, $2, $&);
      $x =~ s/^#//;
      my $out = $orig;
      if ($x =~ /^_.*_(?:class|enumeration|interface)$/ || $x =~ /[:]|\.adoc/) {
        # handled by steps 10/10b, or already a resource reference
      } elsif (my $ids = $id_page{$x}) {
        my @p = pick($m, sort keys %$ids);
        if ($ids->{$here}) { }                        # same page: fine as is
        elsif (@p == 1) {
          my $frag = ($page_anchor{$x} || ($x eq auto_id($id_title{$x} // "") && $page_title{norm($id_title{$x} // "")})) ? "" : "#$x";
          $out = $frag eq "" ? "xref:" . target($p[0], $m) . "\[" . ($text // $id_title{$x} // $x) . "]"
                             : "<<" . target($p[0], $m) . frag($x) . "," . ($text // $id_title{$x} // $x) . ">>";
          $stat{id}++;
        }
        else { $unresolved{"ambiguous id $x"}++ }
      } elsif (my $tp = $title{norm($x)}) {
        my @t = pick($m, sort keys %$tp);
        my ($pg, $id) = split /#/, $t[0], 2;
        if (@t == 1 && $pg ne $here) { $out = "<<" . target($pg, $m) . frag($id) . "," . ($text // $x) . ">>"; $stat{section}++ }
        elsif (@t == 1) { $out = "<<$id," . ($text // $x) . ">>"; $stat{section_same_page}++ }
        else { $unresolved{"ambiguous title $x"}++ }
      } elsif (my $pt = $page_title{norm($x)}) {
        my @t = pick($m, sort keys %$pt);
        if (@t == 1) { $out = "xref:" . target($t[0], $m) . "\[" . ($text // $x) . "]"; $stat{chapter}++ }
        else { $unresolved{"ambiguous chapter $x"}++ }
      } elsif ($bib{$x}) {
        $out = "cite:[$x]"; $stat{citation}++;
      } else {
        $unresolved{$x}++;
      }
      $changed = 1 if $out ne $orig;
      $out;
    }ge;
  }
  if ($changed) { open my $h, ">", $f or die "$f: $!"; print $h @lines; close $h; $stat{files}++ }
}

printf "  • rewritten: %d to ids, %d to sections (%d same page), %d to chapters, %d citations in %d file(s)\n",
  $stat{id} // 0, $stat{section} // 0, $stat{section_same_page} // 0, $stat{chapter} // 0, $stat{citation} // 0, $stat{files} // 0;
my $n = 0; $n += $_ for values %unresolved;
if ($n) {
  printf "  • left unchanged (same page, unknown or ambiguous): %d distinct, e.g.\n", scalar keys %unresolved;
  my $i = 0;
  for my $k (sort { $unresolved{$b} <=> $unresolved{$a} || $a cmp $b } keys %unresolved) {
    last if $i++ >= 10; printf "      %3d  %s\n", $unresolved{$k}, $k;
  }
}
'

echo "✓ Cross references resolved"
echo ""
