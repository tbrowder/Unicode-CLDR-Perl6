#!/usr/bin/env perl6

use lib <../lib>;
use Unicode::Perlcldr;

# There are two optional parameters to this script -v which turns on
# verbose logging and a file name which should be the last
# successfully processed file should you wish to restart the script
# after a crash or some other stoppage

if !@*ARGS {
    say "Usage: $*PROGRAM <...options...>
    HERE
    exit;
}


=begin comment
use FindBin;
use File::Spec;
use File::Path qw(make-path);
use File::Copy qw(copy);
use Archive::Extract;
use DateTime;
use Text::ParseWords;
use List::MoreUtils qw( any );
use List::Util qw( min max );
use Unicode::Regex::Set();
use lib $FindBin::Bin;
use XML::XPath::Node::Text;
use LWP::UserAgent;
=end comment

use XML::Parser;
use XML::XPath;
use LWP::Simple;

my $start-time = DateTime.now();

our $verbose = 0;
$verbose = 1 if grep /'-v'/, @*ARGS;
@*ARGS = grep !/'-v'/, @*ARGS;

use version;
my $API-VERSION    = 0;    # This will get bumped if a release is not backwards compatible with the previous release
my $CLDR-VERSION   = '34'; # This needs to match the revision number of the CLDR revision being generated against
my $REVISION       = 0;    # This is the build number against the CLDR revision
my $TRIAL-REVISION = '';   # This is the trial revision for unstable releases. Set to '' for the first 
                           # trial release after that start counting from 1;

$CLDR-VERSION ~~ s/^ ([^.]+).*/$0/; #r;
our $VERSION  = join '.', $API-VERSION, $CLDR-VERSION, $REVISION;
my $CLDR-PATH = $CLDR-VERSION;

# $RELEASE-STATUS relates to the CPAN status it can be one of
# 'stable', for a full release or 'unstable' for a developer release

my $RELEASE-STATUS = 'stable';

# Set up the names for the directory structure for the build. Using
# File::Spec here to maximise portability

chdir $FindBin::Bin;
my $data-directory            = File::Spec->catdir($FindBin::Bin, 'Data');
my $core-filename             = File::Spec->catfile($data-directory, 'core.zip');
my $base-directory            = File::Spec->catdir($data-directory, 'common');
my $transform-directory       = File::Spec->catdir($base-directory, 'transforms');
my $build-directory           = File::Spec->catdir($FindBin::Bin, 'lib');
my $lib-directory             = File::Spec->catdir($build-directory, 'Locale', 'CLDR');
my $locales-directory         = File::Spec->catdir($lib-directory, 'Locales');
my $bundles-directory         = File::Spec->catdir($build-directory, 'Bundle', 'Locale', 'CLDR');
my $transformations-directory = File::Spec->catdir($lib-directory, 'Transformations');
my $distributions-directory   = File::Spec->catdir($FindBin::Bin, 'Distributions');
my $tests-directory           = File::Spec->catdir($FindBin::Bin, 't');

if ($TRIAL-REVISION && $RELEASE-STATUS eq 'stable') {
	warn "\$TRIAL-REVISION is set to $TRIAL-REVISION and this is a stable release resetting \$TRIAL-REVISION to ''";
	$TRIAL-REVISION = '';
}

my $dist-suffix = '';
if ($TRIAL-REVISION && $RELEASE-STATUS eq 'unstable') {
	$dist-suffix = "\n    dist-suffix         => 'TRIAL$TRIAL-REVISION',\n";
}

# Check if we have a Data directory
if (! -d $data-directory ) {
    mkdir $data-directory
        or die "Can not create $data-directory: $!";
}

# Check the lib directory
if (! -d $lib-directory) {
    make-path($lib-directory);
}

# Get the data file from the Unicode Consortium
if (! -e $core-filename ) {
    say "Getting data file from the Unicode Consortium"
        if $verbose;

    my $ua = LWP::UserAgent->new(
        agent => "perl Locale::CLDR/$VERSION (Written by john.imrie1\@gmail.com)",
    );
    my $response = $ua->get("http://unicode.org/Public/cldr/$CLDR-PATH/core.zip",
        ':content-file' => $core-filename
    );

    if (! $response->is-success) {
        die "Can not access http://unicode.org/Public/cldr/$CLDR-PATH/core.zip' "
             . $response->status-line;
    }
}

# Now uncompress the file
if (! -d $base-directory) {
    say "Extracting Data" if $verbose;
    my $zip = Archive::Extract->new(archive => $core-filename);
    $zip->extract(to => $data-directory)
        or die $zip->error;
}

# Now check that we have a 'common' directory
die <<EOM
I successfully unzipped the core.zip file but don't have a 'common'
directory. Is this version $CLDR-VERSION of the Unicode core.zip file?
EOM

    unless -d File::Spec->catdir($base-directory);

# We look at the root.xml data file to get the cldr version number

my $vf = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($base-directory,
    'main',
    'root.xml'),
);

say "Checking CLDR version" if $verbose;
my $cldrVersion = $vf->findnodes('/ldml/identity/version')
    ->get-node(1)
    ->getAttribute('cldrVersion');

die "Incorrect CLDR Version found $cldrVersion. It should be $CLDR-VERSION"
    unless version->parse("$cldrVersion") == $CLDR-VERSION;

say "Processing files"
    if $verbose;

my $file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'likelySubtags.xml'
);

my $xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($file-name)
);

# Note that the Number Formatter code comes before the collator in the data section
# so this needs to be done first
# Number Formatter
open my $file, '>', File::Spec->catfile($lib-directory, 'NumberFormatter.pm');
write-out-number-formatter($file);
close $file;

{# Collator
	open my $file, '>', File::Spec->catfile($lib-directory, 'Collator.pm');
	write-out-collator($file);
	close $file;
}

# Likely sub-tags
open $file, '>', File::Spec->catfile($lib-directory, 'LikelySubtags.pm');

say "Processing file $file-name" if $verbose;

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::LikelySubtags', $CLDR-VERSION, $xml, $file-name, 1);
process-likely-subtags($file, $xml);
process-footer($file, 1);
close $file;

# Numbering Systems
$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'numberingSystems.xml'
);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($file-name));

open $file, '>', File::Spec->catfile($lib-directory, 'NumberingSystems.pm');

say "Processing file $file-name" if $verbose;

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::NumberingSystems', $CLDR-VERSION, $xml, $file-name, 1);
process-numbering-systems($file, $xml);
process-footer($file, 1);
close $file;

# Plural rules
$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'plurals.xml'
);

my $plural-xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($file-name)
);

$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'ordinals.xml'
);

my $ordanal-xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($file-name)
);

open $file, '>', File::Spec->catfile($lib-directory, 'Plurals.pm');

say "Processing file $file-name" if $verbose;

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::Plurals', $CLDR-VERSION, $xml, $file-name, 1);
process-plurals($file, $plural-xml, $ordanal-xml);

$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'pluralRanges.xml'
);

my $plural-ranges-xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
    filename => File::Spec->catfile($file-name)
);

process-plural-ranges($file, $plural-ranges-xml);
process-footer($file, 1);
close $file;

open $file, '>', File::Spec->catfile($lib-directory, 'ValidCodes.pm');

$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'supplementalMetadata.xml'
);

say "Processing file $file-name" if $verbose;

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::ValidCodes', $CLDR-VERSION, $xml, $file-name, 1);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'language.xml',
    )
);

process-valid-languages($file, $xml);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'script.xml',
    )
);

process-valid-scripts($file, $xml);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'region.xml',
    )
);

process-valid-regions($file, $xml);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'variant.xml',
    )
);

process-valid-variants($file, $xml);


$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'currency.xml',
    )
);

process-valid-currencies($file, $xml);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'subdivision.xml',
    )
);

process-valid-subdivisions($file, $xml);

$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'validity',
        'unit.xml',
    )
);

process-valid-units($file, $xml);

# The supplemental/supplementalMetaData.xml file contains a list of all valid
# aliases and keys


$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'supplemental',
        'supplementalMetadata.xml',
    )
);

process-valid-keys($file, $base-directory);
process-valid-language-aliases($file,$xml);
process-valid-region-aliases($file,$xml);
process-valid-variant-aliases($file,$xml);
process-footer($file, 1);
close $file;

# File for era boundaries
$xml = XML::XPath->new(
	parser => XML::Parser->new(
		NoLWP => 1,
		ErrorContext => 2,
		ParseParamEnt => 1,
	),
	filename => File::Spec->catfile($base-directory,
        'supplemental',
        'supplementalData.xml',
    )
);

open $file, '>', File::Spec->catfile($lib-directory, 'EraBoundries.pm');

$file-name = File::Spec->catfile($base-directory,
    'supplemental',
    'supplementalData.xml'
);

say "Processing file $file-name" if $verbose;

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::EraBoundries', $CLDR-VERSION, $xml, $file-name, 1);
process-era-boundries($file, $xml);
process-footer($file, 1);
close $file;

# Currency defaults
open $file, '>', File::Spec->catfile($lib-directory, 'Currencies.pm');
process-header($file, 'Locale::CLDR::Currencies', $CLDR-VERSION, $xml, $file-name, 1);
process-currency-data($file, $xml);
process-footer($file, 1);
close $file;

# region Containment
open $file, '>', File::Spec->catfile($lib-directory, 'RegionContainment.pm');
process-header($file, 'Locale::CLDR::RegionContainment', $CLDR-VERSION, $xml, $file-name, 1);
process-region-containment-data($file, $xml);
process-footer($file, 1);
close $file;

# Calendar Preferences
open $file, '>', File::Spec->catfile($lib-directory, 'CalendarPreferences.pm');

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::CalendarPreferences', $CLDR-VERSION, $xml, $file-name, 1);
process-calendar-preferences($file, $xml);
process-footer($file, 1);
close $file;

# Week data
open $file, '>', File::Spec->catfile($lib-directory, 'WeekData.pm');

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::WeekData', $CLDR-VERSION, $xml, $file-name, 1);
process-week-data($file, $xml);
process-footer($file, 1);
close $file;

# Measurement System Data
open $file, '>', File::Spec->catfile($lib-directory, 'MeasurementSystem.pm');

# Note: The order of these calls is important
process-header($file, 'Locale::CLDR::MeasurementSystem', $CLDR-VERSION, $xml, $file-name, 1);
process-measurement-system-data($file, $xml);
process-footer($file, 1);
close $file;

# Parent data
my %parent-locales = get-parent-locales($xml);

# Transformations
make-path($transformations-directory) unless -d $transformations-directory;
opendir (my $dir, $transform-directory);
my $num-files = grep { -f File::Spec->catfile($transform-directory,$-)} readdir $dir;
my $count-files = 0;
rewinddir $dir;
my @transformation-list;

foreach my $file-name ( sort grep /^[^.]/, readdir($dir) ) {
    my $percent = ++$count-files / $num-files * 100;
    my $full-file-name = File::Spec->catfile($transform-directory, $file-name);
    say sprintf("Processing Transformation File %s: $count-files of $num-files, %.2f%% done", $full-file-name, $percent) if $verbose;
	$xml = XML::XPath->new(
		parser => XML::Parser->new(
			NoLWP => 1,
			ErrorContext => 2,
			ParseParamEnt => 1,
		),
		filename => $full-file-name
	);

    process-transforms($transformations-directory, $xml, $full-file-name);
}

# Write out a dummy transformation module to keep CPAN happy
{
	open my $file, '>', File::Spec->catfile($lib-directory, 'Transformations.pm');
	print $file <<EOT;
package Locale::CLDR::Transformations;

=head1 Locale::CLDR::Transformations - Dummy base class to keep CPAN happy

=cut

use version;

our VERSION = version->declare('v$VERSION');

1;
EOT
}

push @transformation-list, 'Locale::CLDR::Transformations';

#Collation

# Perl older than 5.16 can't handle all the utf8 encoded code points, so we need a version of Locale::CLDR::CollatorBase
# that does not have the characters as raw utf8

say "Copying base collation file" if $verbose;
open (my $Allkeys-in, '<', File::Spec->catfile($base-directory, 'uca', 'allkeys-CLDR.txt'));
open (my $Fractional-in, '<', File::Spec->catfile($base-directory, 'uca', 'FractionalUCA-SHORT.txt'));
open (my $Allkeys-out, '>', File::Spec->catfile($lib-directory, 'CollatorBase.pm'));
process-header($Allkeys-out, 'Locale::CLDR::CollatorBase', $CLDR-VERSION, undef, File::Spec->catfile($base-directory, 'uca', 'FractionalUCA-SHORT.txt'), 1);
process-collation-base($Fractional-in, $Allkeys-in, $Allkeys-out);
process-footer($Allkeys-out,1);
close $Allkeys-in;
close $Fractional-in;
close $Allkeys-out;

# Main directory
my $main-directory = File::Spec->catdir($base-directory, 'main');
opendir ( $dir, $main-directory);

# Count the number of files
$num-files = grep { -f File::Spec->catfile($main-directory,$-)} readdir $dir;
$num-files += 3; # We do root.xml, en.xml and en-US.xml twice
$count-files = 0;
rewinddir $dir;

my $segmentation-directory = File::Spec->catdir($base-directory, 'segments');
my $rbnf-directory = File::Spec->catdir($base-directory, 'rbnf');

my %region-to-package;
# Sort files ASCIIbetically
my $en;
my $languages;
my $regions;

# We are going to process the root en and en-US locales twice the first time as the first three
# locales so we can then use the data in the processed files to create names and other labels in
# the local files
foreach my $file-name ( 'root.xml', 'en.xml', 'en-US.xml', sort grep /^[^.]/, readdir($dir) ) {
    if (@ARGV) { # Allow us to supply the last processed file for a restart after a crash
        next unless grep {$file-name eq $-} @ARGV;
    }

	$xml = XML::XPath->new(
		parser => XML::Parser->new(
			NoLWP => 1,
			ErrorContext => 2,
			ParseParamEnt => 1,
		),
		filename => File::Spec->catfile($main-directory, $file-name)
    );

    my $segment-xml = undef;
    if (-f File::Spec->catfile($segmentation-directory, $file-name)) {
        $segment-xml = XML::XPath->new(
			parser => XML::Parser->new(
				NoLWP => 1,
				ErrorContext => 2,
				ParseParamEnt => 1,
			),
			filename => File::Spec->catfile($segmentation-directory, $file-name)
        );
    }

	my $rbnf-xml = undef;
	if (-f File::Spec->catfile($rbnf-directory, $file-name)) {
        $rbnf-xml = XML::XPath->new(
            parser => XML::Parser->new(
				NoLWP => 1,
				ErrorContext => 2,
				ParseParamEnt => 1,
			),
			filename => File::Spec->catfile($rbnf-directory, $file-name)
        );
    }

    my @output-file-parts = output-file-name($xml);
    my $current-locale = lc $output-file-parts[0];

    my $package = join '::', @output-file-parts;

    $output-file-parts[-1] .= '.pm';

    my $out-directory = File::Spec->catdir(
        $locales-directory,
        @output-file-parts[0 .. $#output-file-parts - 1]
    );

    make-path($out-directory) unless -d $out-directory;

	if (defined( my $t = $output-file-parts[2])) {
		$t =~ s/\.pm$//;
		push @{$region-to-package{lc $t}}, join('::','Locale::CLDR::Locales',@output-file-parts[0,1],$t);
	}

	# If we have already created the US English module we can use it to produce the correct local
	# names in each modules documentation
	my $has-en = -e File::Spec->catfile($locales-directory, 'En', 'Any', 'Us.pm');
	if ($has-en && ! $en) {
		require lib;
		lib::import(undef,File::Spec->catdir($FindBin::Bin, 'lib'));
		require Locale::CLDR;
		$en = Locale::CLDR->new('en');
		$languages = $en->all-languages;
		$regions = $en->all-regions;
	}

    open $file, '>', File::Spec->catfile($locales-directory, @output-file-parts);

    my $full-file-name = File::Spec->catfile($base-directory, 'main', $file-name);
    my $percent = ++$count-files / $num-files * 100;
    say sprintf("Processing File %s: $count-files of $num-files, %.2f%% done", $full-file-name, $percent) if $verbose;

    # Note: The order of these calls is important
    process-class-any($locales-directory, @output-file-parts[0 .. $#output-file-parts -1]);

    process-header($file, "Locale::CLDR::Locales::$package", $CLDR-VERSION, $xml, $full-file-name, 0, $languages->{$current-locale});
    process-segments($file, $segment-xml) if $segment-xml;
	process-rbnf($file, $rbnf-xml) if $rbnf-xml;
    process-display-pattern($file, $xml);
    process-display-language($file, $xml);
    process-display-script($file, $xml);
    process-display-region($file, $xml);
    process-display-variant($file, $xml);
    process-display-key($file, $xml);
    process-display-type($file,$xml);
    process-display-measurement-system-name($file, $xml);
    process-display-transform-name($file,$xml);
    process-code-patterns($file, $xml);
    process-orientation($file, $xml);
    process-exemplar-characters($file, $xml);
    process-ellipsis($file, $xml);
    process-more-information($file, $xml);
    process-delimiters($file, $xml);
	process-units($file, $xml);
    process-posix($file, $xml);
	process-list-patterns($file, $xml);
	process-context-transforms($file, $xml);
	process-numbers($file, $xml);
    process-calendars($file, $xml, $current-locale);
    process-time-zone-names($file, $xml);
    process-footer($file);

    close $file;
}

# Build Bundles and Distributions
my $out-directory = File::Spec->catdir($lib-directory, '..', '..', 'Bundle', 'Locale','CLDR');
make-path($out-directory) unless -d $out-directory;

# region bundles
my $region-contains = $en->region-contains();
my $region-names = $en->all-regions();

foreach my $region (keys %$region-names) {
	$region-names->{$region} = ucfirst( lc $region ) . '.pm' unless exists $region-contains->{$region};
}

foreach my $region (sort keys %$region-contains) {
	my $name = lc ( $region-names->{$region} // '' );
	$name=~tr/a-z0-9//cs;
	build-bundle($out-directory, $region-contains->{$region}, $name, $region-names);
}

# Language bundles
#foreach my $language (sort keys %$languages) {
for %languages.keys.sort -> $language {
	next if $language ~~ /<[@-]>/;
	my @files = get-language-bundle-data(tc $language);
	next unless @files;
	push @files, get-language-bundle-data(tc "{$language}.pm");
	my @packages = convert-files-to-packages(@files);
	build-bundle($out-directory, @packages, $language);
}

sub convert-files-to-packages(@files) {
	#my $files = shift;
	my @packages;

	#foreach my $file-name (@$files) {
	for @files -> $filename {
		#open my $file, $file-name or die "Bang $file-name: $!";
                my $fh = 
		my $package;
		($package) = (<$file> =~ /^package (.+);$/)
			until $package;

		close $file;
		push @packages, $package;
	}

	return @packages;
}

sub get-language-bundle-data {
	my ($language, $directory-name) = @-;

	$directory-name //= $locales-directory;

	my @packages;
	if ( -d (my $new-dir = File::Spec->catdir($directory-name, $language)) ) {
		opendir $dir, $new-dir;
		my @files = grep { ! /^\./ } readdir $dir;
		foreach my $file (@files) {
			push @packages, get-language-bundle-data($file, $new-dir);
		}
	}
	else {
		push @packages, File::Spec->catfile($directory-name, $language)

	if -f File::Spec->catfile($directory-name, $language);
	}
	return @packages;
}

# Transformation bundle
build-bundle($out-directory, \@transformation-list, 'Transformations');

# Base bundle
my @base-bundle = (
	'Locale::CLDR',
	'Locale::CLDR::CalendarPreferences',
	'Locale::CLDR::Collator',
	'Locale::CLDR::CollatorBase',
	'Locale::CLDR::Currencies',
	'Locale::CLDR::EraBoundries',
	'Locale::CLDR::LikelySubtags',
	'Locale::CLDR::MeasurementSystem',
	'Locale::CLDR::NumberFormatter',
	'Locale::CLDR::NumberingSystems',
	'Locale::CLDR::Plurals',
	'Locale::CLDR::RegionContainment',
	'Locale::CLDR::ValidCodes',
	'Locale::CLDR::WeekData',
	'Locale::CLDR::Locales::En',
	'Locale::CLDR::Locales::En::Any',
	'Locale::CLDR::Locales::En::Any::Us',
	'Locale::CLDR::Locales::Root',
);

build-bundle($out-directory, \@base-bundle, 'Base');

# All Bundle
my @all-bundle = (
	'Bundle::Locale::CLDR::World',
	'Locale::CLDR::Transformations',
);

build-bundle($out-directory, \@all-bundle, 'Everything');

# Now split everything into distributions
build-distributions();

my $duration = time() - $start-time;
my @duration;
$duration[2] = $duration % 60;
$duration = int($duration/60);
$duration[1] = $duration % 60;
$duration[0] = int($duration/60);

say "Duration: ", sprintf "%02i:%02i:%02i", @duration if $verbose;

# This sub looks for nodes along an xpath.
sub findnodes {
    my ($xpath, $path ) = @-;
    my $nodes = $xpath->findnodes($path);

    return $nodes;
}

# Calculate the output file name
sub output-file-name {
    my $xpath = shift;
    my @nodes;
    foreach my $name (qw( language script territory variant )) {
        my $nodes = findnodes($xpath, "/ldml/identity/$name");
        if ($nodes->size) {;
            push @nodes, $nodes->get-node(1)->getAttribute('type');
        }
        else {
            push @nodes, 'Any';
        }
    };

    # Strip off Any's from end of list
    pop @nodes while $nodes[-1] eq 'Any';

    return map {ucfirst lc} @nodes;
}

# Fill in any missing script or region with the pseudo class Any
sub process-class-any {
    my ($lib-path, @path-parts) = @-;

    my $package = 'Locale::CLDR::Locales';
    foreach my $path (@path-parts) {
        my $parent = $package;
        $parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
        $package .= "::$path";
        $lib-path = File::Spec->catfile($lib-path, $path);

        next unless $path eq 'Any';

        my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');
        open my $file, '>:utf8', "$lib-path.pm";
        print $file <<EOT;
package $package;

# This file auto generated
#\ton $now GMT

use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use if \$^V ge v5.12.0, feature => 'unicode-strings';

use Moo;

extends('$parent');

no Moo;

1;
EOT
        close $file;
    }
}

# Process the elements of the file note
sub process-header {
    my ($file, $class, $version, $xpath, $xml-name, $isRole, $language) = @-;
    say "Processing Header" if $verbose;

    $isRole = $isRole ? '::Role' : '';

    $xml-name =~s/^.*(Data.*)$/$1/;
    my $now = DateTime->now->strftime('%a %e %b %l:%M:%S %P');

	my $header = '';
	if ($language) {
		print $file <<EOT;
=encoding utf8

=head1

$class - Package for language $language

=cut

EOT
	}

	print $file <<EOT;
package $class;
# This file auto generated from $xml-name
#\ton $now GMT

use strict;
use warnings;
use version;

our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use utf8;
use if \$^V ge v5.12.0, feature => 'unicode-strings';
use Types::Standard qw( Str Int HashRef ArrayRef CodeRef RegexpRef );
use Moo$isRole;

EOT
    print $file $header;
	if (!$isRole && $class =~ /^Locale::CLDR::Locales::...?(?:::|$)/) {
		my ($parent) = $class =~ /^(.+)::/;
		$parent = 'Locale::CLDR::Locales::Root' if $parent eq 'Locale::CLDR::Locales';
		$parent = $parent-locales{$class} // $parent;
		say $file "extends('$parent');";
	}
}

sub process-collation-base {
	my ($Fractional-in, $Allkeys-in, $Allkeys-out) = @-;
	my %characters;
	my @multi;

	while (my $line = <$Allkeys-in>) {
		next if $line =~ /^\s*$/; # Empty lines
		next if $line =~ /^#/; # Comments

		next if $line =~ /^\@version /; # Version line

		# Characters
		if (my ($character, $collation-element) = $line =~ /^(\p{hex}{4,6}(?: \p{hex}{4,6})*) *; ((?:\[[.*]\p{hex}{4}\.\p{hex}{4}\.\p{hex}{4}\])+) #.*$/) {
			$character = join '', map {chr hex $-} split / /, $character;
			if (length $character > 1) {
				push(@multi,$character);
			}
			$characters{$character} = process-collation-element($collation-element);
		}
	}

    # Get block ranges
    my %block;
    my $old-name;
    my $fractional = join '', <$Fractional-in>;
    while ($fractional =~ /(\p{hex}{4,6});[^;]+?(?:\nFDD0 \p{hex}{4,6};[^;]+?)?\nFDD1.*?# (.+?) first.*?\n(\p{hex}{4,6});/gs ) {
		my ($end, $name, $start ) = ($1, $2, $3);
        if ($old-name) {
            $block{$old-name}{end} = $characters{chr hex $end} // generate-ce(chr hex $end);
			$block{Meroitic-Hieroglyphs}{end} = $characters{chr hex $end}
				if $old-name eq 'HIRAGANA';
			$block{KATAKANA}{end} = $characters{chr hex $end}
				if $old-name eq 'Meroitic-Cursive';
        }
        $old-name = $name;
        $block{$name}{start} = $characters{chr hex $start} // generate-ce(chr hex $start);
		$block{KATAKANA}{start} = $characters{chr hex $start}
				if $old-name eq 'HIRAGANA';
		$block{Meroitic-Hieroglyphs}{start} = $characters{chr hex $start}
				if $old-name eq 'Meroitic-Cursive';
    }

	print $Allkeys-out <<EOT;
has multi-class => (
	is => 'ro',
	isa => ArrayRef,
	init-arg => undef,
	default => sub {
		return [
EOT
	foreach ( @multi ) {
		my $multi = $-; # Make sure that $multi is not a reference into @multi
		no warnings 'utf8';
		$multi =~ s/'/\\'/g;
		print $Allkeys-out "\t\t\t'$multi',\n";
	}

	print $Allkeys-out <<EOT;
		]
	}
);

has multi-rx => (
	is => 'ro',
	isa => ArrayRef,
	init-arg => undef,
	default => sub {
		return [
EOT
	foreach my $multi ( @multi ) {
		no warnings 'utf8';
		$multi =~ s/(.)/$1\\P{ccc=0}/g;
		$multi =~ s/'/\\'/g;
		print $Allkeys-out "\t\t\t'$multi',\n";
	}

	print $Allkeys-out <<EOT;
		]
	}
);
EOT

	print $Allkeys-out <<EOT;
has collation-elements => (
	is => 'ro',
	isa => HashRef,
	init-arg => undef,
	default => sub {
		return {
EOT
	no warnings 'utf8';
	foreach my $character (sort (keys %characters)) {
		my $character-out = $character;
		$character-out = sprintf '"\\x{%0.4X}"', ord $character-out;
		print $Allkeys-out "\t\t\t$character-out => '";
		my @ce = @{$characters{$character}};
		foreach my $ce (@ce) {
			$ce = join '', map { defined $- ? $- : '' } @$ce;
		}
		my $ce = join("\x{0001}", @ce) =~ s/([\\'])/\\$1/r;
		print $Allkeys-out $ce, "',\n";
	}

	print $Allkeys-out <<EOT;
		}
	}
);

has collation-sections => (
	is => 'ro',
	isa => HashRef,
	init-arg => undef,
	default => sub {
		return {
EOT
	foreach my $block (sort keys %block) {
		my $end = defined $block{$block}{end}
			? 'q(' . (
				ref $block{$block}{end}
				? join("\x{0001}", map { join '', @$-} @{$block{$block}{end}})
				: $block{$block}{end}) . ')'
			: 'undef';

		my $start = defined $block{$block}{start}
			? 'q(' . (
				ref $block{$block}{start}
				? join("\x{0001}", map { join '', @$-} @{$block{$block}{start}})
				: $block{$block}{start}) . ')'
			: 'undef';

		$block = lc $block;
		$block =~ tr/ -/-/;
		print $Allkeys-out "\t\t\t$block => [ $start, $end ],\n";
	}
	print $Allkeys-out <<EOT;
		}
	}
);
EOT
}

sub generate-ce {
	my ($character) = @-;
	my $LEVEL-SEPARATOR = "\x{0001}";
	my $aaaa;
	my $bbbb;

	if ($^V ge v5.26 && eval q($character =~ /(?!\p{Cn})(?:\p{Block=Tangut}|\p{Block=Tangut-Components})/)) {
		$aaaa = 0xFB00;
		$bbbb = (ord($character) - 0x17000) | 0x8000;
	}
	# Block Nushu was added in Perl 5.28
	elsif ($^V ge v5.28 && eval q($character =~ /(?!\p{Cn})\p{Block=Nushu}/)) {
		$aaaa = 0xFB01;
		$bbbb = (ord($character) - 0x1B170) | 0x8000;
	}
	elsif ($character =~ /(?=\p{Unified-Ideograph=True})(?:\p{Block=CJK-Unified-Ideographs}|\p{Block=CJK-Compatibility-Ideographs})/) {
		$aaaa = 0xFB40 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	elsif ($character =~ /(?=\p{Unified-Ideograph=True})(?!\p{Block=CJK-Unified-Ideographs})(?!\p{Block=CJK-Compatibility-Ideographs})/) {
		$aaaa = 0xFB80 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	else {
		$aaaa = 0xFBC0 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	return join '', map {chr($-)} $aaaa, 0x0020, 0x0002, ord ($LEVEL-SEPARATOR), $bbbb, 0, 0;
}

sub process-collation-element {
	my ($collation-string) = @-;
	my @collation-elements = $collation-string =~ /\[(.*?)\]/g;
	foreach my $element (@collation-elements) {
		my (undef, $primary, $secondary, $tertiary) = split(/[.*]/, $element);
		foreach my $level ($primary, $secondary, $tertiary) {
			$level //= 0;
			$level = chr hex $level;
		}
		$element = [$primary, $secondary, $tertiary];
	}

	return \@collation-elements;
}

sub expand-text {
	my $string = shift;

	my @elements = grep {length} split /\s+/, $string;
	foreach my $element (@elements) {
		next unless $element =~ /~/;
		my ($base, $start, $end) = $element =~ /^(.*)(.)~(.)$/;
		$element = [ map { "$base$-" } ($start .. $end) ];
	}

	return map { ref $- ? @$- : $- } @elements;
}

sub process-valid-languages {
    my ($file, $xpath) = @-;
    say "Processing Valid Languages"
        if $verbose;

    my $languages = findnodes($xpath,'/supplementalData/idValidity/id[@type="language"][@idStatus!="deprecated"]');

    my @languages =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$languages->get-nodelist;

    print $file <<EOT
has 'valid-languages' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @languages \t)]},
);

around valid-languages => sub {
	my (\$orig, \$self) = \@-;

	my \$languages = \$self->\$orig;
	return \@{\$languages};
};

EOT
}

sub process-valid-scripts {
    my ($file, $xpath) = @-;

    say "Processing Valid Scripts"
        if $verbose;

    my $scripts = findnodes($xpath,'/supplementalData/idValidity/id[@type="script"][@idStatus!="deprecated"]');

    my @scripts =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$scripts->get-nodelist;

    print $file <<EOT
has 'valid-scripts' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @scripts \t)]},
);

around valid-scripts => sub {
	my (\$orig, \$self) = \@-;

	my \$scripts = \$self->\$orig;
	return \@{\$scripts};
};

EOT
}

sub process-valid-regions {
    my ($file, $xpath) = @-;

    say "Processing Valid regions"
        if $verbose;

    my $regions = findnodes($xpath, '/supplementalData/idValidity/id[@type="region"][@idStatus!="deprecated"]');

    my @regions =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$regions->get-nodelist;

    print $file <<EOT
has 'valid-regions' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @regions \t)]},
);

around valid-regions => sub {
	my (\$orig, \$self) = \@-;

	my \$regions = \$self->\$orig;
	return \@{\$regions};
};

EOT
}

sub process-valid-variants {
    my ($file, $xpath) = @-;

    say "Processing Valid Variants"
        if $verbose;

    my $variants = findnodes($xpath, '/supplementalData/idValidity/id[@type="variant"][@idStatus!="deprecated"]');

    my @variants =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$variants->get-nodelist;

    print $file <<EOT
has 'valid-variants' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @variants \t)]},
);

around valid-variants => sub {
	my (\$orig, \$self) = \@-;
	my \$variants = \$self->\$orig;

	return \@{\$variants};
};

EOT
}

sub process-valid-currencies {
    my ($file, $xpath) = @-;

    say "Processing Valid Currencies"
        if $verbose;

    my $currencies = findnodes($xpath, '/supplementalData/idValidity/id[@type="currency"][@idStatus!="deprecated"]');

    my @currencies =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$currencies->get-nodelist;

    print $file <<EOT
has 'valid-currencies' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @currencies \t)]},
);

around valid-currencies => sub {
	my (\$orig, \$self) = \@-;
	my \$currencies = \$self->\$orig;

	return \@{\$currencies};
};

EOT
}

sub process-valid-subdivisions {
    my ($file, $xpath) = @-;

    say "Processing Valid Subdivisions"
        if $verbose;

    my $sub-divisions = findnodes($xpath, '/supplementalData/idValidity/id[@type="subdivision"][@idStatus!="deprecated"]');

    my @sub-divisions =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$sub-divisions->get-nodelist;

    print $file <<EOT
has 'valid-subdivisions' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @sub-divisions \t)]},
);

around valid-subdivisions => sub {
	my (\$orig, \$self) = \@-;
	my \$subdevisions = \$self->\$orig;

	return \@{\$subdevisions};
};

EOT
}

sub process-valid-units {
    my ($file, $xpath) = @-;

    say "Processing Valid Units"
        if $verbose;

    my $units = findnodes($xpath, '/supplementalData/idValidity/id[@type="unit"][@idStatus!="deprecated"]');

    my @units =
		map {"$-\n"}
		map { expand-text($-) }
		map {$-->string-value }
		$units->get-nodelist;

    print $file <<EOT
has 'valid-units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> ArrayRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub {[qw( @units \t)]},
);

around valid-units => sub {
	my (\$orig, \$self) = \@-;
	my \$units = \$self->\$orig;

	return \@{\$units};
};

EOT
}

sub process-valid-keys {
    my ($file, $base-directory) = @-;

    say "Processing Valid Keys"
        if $verbose;

    opendir (my $dir, File::Spec->catdir($base-directory, 'bcp47'))
        || die "Can't open directory: $!";

    my @files = map {File::Spec->catfile($base-directory, 'bcp47', $-)}
        grep /\.xml \z/xms, readdir $dir;

    closedir $dir;
    my %keys;
    foreach my $file-name (@files) {
        my $xml = XML::XPath->new(
			parser => XML::Parser->new(
				NoLWP => 1,
				ErrorContext => 2,
				ParseParamEnt => 1,
			),
            filename => $file-name
        );

        my @keys = findnodes($xml, '/ldmlBCP47/keyword/key')->get-nodelist;
        foreach my $key (@keys) {
            my ($name, $alias) = ($key->getAttribute('name'), $key->getAttribute('alias'));
            $keys{$name}{alias} = $alias;
            my @types = findnodes($xml,qq(/ldmlBCP47/keyword/key[\@name="$name"]/type))->get-nodelist;
            foreach my $type (@types) {
                push @{$keys{$name}{type}}, $type->getAttribute('name');
                push @{$keys{$name}{type}}, $type->getAttribute('alias')
                    if length $type->getAttribute('alias');
            }
        }
    }

    print $file <<EOT;
has 'key-aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $key (sort keys %keys) {
        my $alias = lc ($keys{$key}{alias} // '');
        next unless $alias;
        say $file "\t\t'$key' => '$alias',";
    }
    print $file <<EOT;
\t}},
);

around key-aliases => sub {
	my (\$orig, \$self) = \@-;
	my \$aliases = \$self->\$orig;

	return %{\$aliases};
};

has 'key-names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tlazy\t\t=> 1,
\tdefault\t=> sub { return { reverse shift()->key-aliases }; },
);

around key-names => sub {
	my (\$orig, \$self) = \@-;
	my \$names = \$self->\$orig;

	return %{\$names};
};

has 'valid-keys' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT

    foreach my $key (sort keys %keys) {
        my @types = @{$keys{$key}{type} // []};
        say $file "\t\t$key\t=> [";
        print $file map {"\t\t\t'$-',\n"} @types;
        say $file "\t\t],";
    }

    print $file <<EOT;
\t}},
);

around valid-keys => sub {
	my (\$orig, \$self) = \@-;

	my \$keys = \$self->\$orig;
	return %{\$keys};
};

EOT
}

sub process-valid-language-aliases {
    my ($file, $xpath) = @-;

    say "Processing Valid Language Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/languageAlias');
    print $file <<EOT;
has 'language-aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $node ($aliases->get-nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => '$to',";
    }
    print $file <<EOT;
\t}},
);
EOT
}

sub process-valid-region-aliases {
    my ($file, $xpath) = @-;

    say "Processing Valid region Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/territoryAlias');
    print $file <<EOT;
has 'region-aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT
    foreach my $node ($aliases->get-nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => [qw($to)],";
    }
    print $file <<EOT;
\t}},
);
EOT

}

sub process-valid-variant-aliases {
    my ($file, $xpath) = @-;

    say "Processing Valid Variant Aliases"
        if $verbose;

    print $file <<EOT;
has 'variant-aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
\t\tbokmal\t\t=> { language\t=> 'nb' },
\t\tnynorsk\t\t=> { language\t=> 'nn' },
\t\taaland\t\t=> { region\t=> 'AX' },
\t\tpolytoni\t=> { variant\t=> 'POLYTON' },
\t\tsaaho\t\t=> { language\t=> 'ssy' },
\t}},
);
EOT
}

sub process-likely-subtags {
	my ($file, $xpath) = @-;

	my $subtags = findnodes($xpath,
        q(/supplementalData/likelySubtags/likelySubtag));

	print $file <<EOT;
has 'likely-subtags' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT

foreach my $subtag ($subtags->get-nodelist) {
	my $from = $subtag->getAttribute('from');
	my $to = $subtag->getAttribute('to');

	print $file "\t\t'$from'\t=> '$to',\n";
}

print $file <<EOT;
\t}},
);

EOT
}

sub process-numbering-systems {
	my ($file, $xpath) = @-;

	my $systems = findnodes($xpath,
        q(/supplementalData/numberingSystems/numberingSystem));

	print $file <<EOT;
has 'numbering-system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { return {
EOT

foreach my $system ($systems->get-nodelist) {
	my $id = $system->getAttribute('id');
	my $type = $system->getAttribute('type');
	my $data;
	if ($type eq 'numeric') {
		$data = '[qw(' . join(' ', split //, $system->getAttribute('digits')) . ')]';
	}
	else {
		$data = "'" . $system->getAttribute('rules') . "'";
	}

	print $file <<EOT;
\t\t'$id'\t=> {
\t\t\ttype\t=> '$type',
\t\t\tdata\t=> $data,
\t\t},
EOT
}

print $file <<EOT;
\t}},
);

has '-default-numbering-system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit-arg\t=> undef,
\tdefault\t=> '',
\tclearer\t=> '-clear-default-nu',
\twriter\t=> '-set-default-numbering-system',
);

sub -set-default-nu {
	my (\$self, \$system) = \@-;
	my \$default = \$self->-default-numbering-system // '';
	\$self->-set-default-numbering-system("\$default\$system");
}

sub -test-default-nu {
	my \$self = shift;
	return length \$self->-default-numbering-system ? 1 : 0;
}

sub default-numbering-system {
	my \$self = shift;

	if(\$self->-test-default-nu) {
		return \$self->-default-numbering-system;
	}
	else {
		my \$numbering-system = \$self->-find-bundle('default-numbering-system')->default-numbering-system;
		\$self->-set-default-nu(\$numbering-system);
		return \$numbering-system
	}
}

EOT
}

sub process-era-boundries {
    my ($file, $xpath) = @-;

    say "Processing Era Boundries"
        if $verbose;

    my $calendars = findnodes($xpath,
        q(/supplementalData/calendarData/calendar));

    print $file <<EOT;

sub era-boundry {
	my (\$self, \$type, \$date) = \@-;
	my \$era = \$self->-era-boundry;
	return \$era->(\$self, \$type, \$date);
}

has '-era-boundry' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { sub {
\t\tmy (\$self, \$type, \$date) = \@-;
\t\t# \$date in yyyymmdd format
\t\tmy \$return = -1;
\t\tSWITCH:
\t\tfor (\$type) {
EOT
    foreach my $calendar ($calendars->get-nodelist) {
        my $type = $calendar->getAttribute('type');
        say $file "\t\t\tif (\$- eq '$type') {";
        my $eras = findnodes($xpath,
            qq(/supplementalData/calendarData/calendar[\@type="$type"]/eras/era)
        );
        foreach my $era ($eras->get-nodelist) {
            my ($type, $start, $end) = (
                $era->getAttribute('type'),
                $era->getAttribute('start'),
                $era->getAttribute('end'),
            );
            if (length $start) {
                my ($y, $m, $d) = split /-/, $start;
				die $start unless length "$y$m$d";
                $m ||= 0;
                $d ||= 0;
				$y ||= 0;
                $start = sprintf('%d%0.2d%0.2d',$y,$m,$d);
				$start =~ s/^0+//;
                say $file "\t\t\t\t\$return = $type if \$date >= $start;";
            }
            if (length $end) {
                my ($y, $m, $d) = split /-/, $end;
                $m ||= 0;
                $d ||= 0;
				$y ||= 0;
                $end = sprintf('%d%0.2d%0.2d',$y,$m,$d);
				$end =~ s/^0+//;
                say $file "\t\t\t\t\$return = $type if \$date <= $end;";
            }
        }
        say $file "\t\t\tlast SWITCH";
        say $file "\t\t\t}";
    }
    print $file <<EOT;
\t\t} return \$return; }
\t}
);

EOT
}

sub process-week-data {
    my ($file, $xpath) = @-;

    say "Processing Week Data"
        if $verbose;

    my $week-data-min-days = findnodes($xpath,
        q(/supplementalData/weekData/minDays));

    print $file <<EOT;
has '-week-data-min-days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week-data-min-days->get-nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
		shift @regions if $regions[0] eq '';
        my $count = $node->getAttribute('count');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => $count,";
        }
    }
    print $file <<EOT;
\t}},
);

EOT

    my $week-data-first-day = findnodes($xpath,
        q(/supplementalData/weekData/firstDay));

    print $file <<EOT;
has '-week-data-first-day' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week-data-first-day->get-nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
		shift @regions if $regions[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT

    my $week-data-weekend-start= findnodes($xpath,
        q(/supplementalData/weekData/weekendStart));

    print $file <<EOT;
has '-week-data-weekend-start' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week-data-weekend-start->get-nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
		shift @regions if $regions[0] eq '';
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT

    my $week-data-weekend-end = findnodes($xpath,
        q(/supplementalData/weekData/weekendEnd));

    print $file <<EOT;
has '-week-data-weekend-end' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($week-data-weekend-end->get-nodelist) {
        my @regions = split /\s+/,$node->getAttribute('territories');
        my $day = $node->getAttribute('day');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => '$day',";
        }
    }
    print $file <<EOT;
\t}},
);

EOT

}

sub process-calendar-preferences {
    my ($file, $xpath) = @-;

    say "Processing Calendar Preferences"
        if $verbose;

    my $calendar-preferences = findnodes($xpath,
        q(/supplementalData/calendarPreferenceData/calendarPreference));

    print $file <<EOT;
has 'calendar-preferences' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($calendar-preferences->get-nodelist) {
        my @regions = split / /,$node->getAttribute('territories');
        my @ordering = split / /, $node->getAttribute('ordering');
        foreach my $region (@regions) {
            say $file "\t\t'$region' => ['", join("','", @ordering), "'],";
        }
    }
    print $file <<EOT;
\t}},
);

EOT
}

sub process-valid-timezone-aliases {
    my ($file, $xpath) = @-;

    say "Processing Valid Time Zone Aliases"
        if $verbose;

    my $aliases = findnodes($xpath, '/supplementalData/metadata/alias/zoneAlias');
    print $file <<EOT;
has 'zone-aliases' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    foreach my $node ($aliases->get-nodelist) {
        my $from = $node->getAttribute('type');
        my $to = $node->getAttribute('replacement');
        say $file "\t'$from' => '$to',";
    }
    print $file <<EOT;
\t}},
);
EOT

}

sub process-display-pattern {
    my ($file, $xpath) = @-;

    say "Processing Display Pattern"
        if $verbose;

    my $display-pattern =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localePattern');
    return unless $display-pattern->size;
    $display-pattern = $display-pattern->get-node(1)->string-value;

    my $display-seperator =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeSeparator');
    $display-seperator = $display-seperator->size ? $display-seperator->get-node(1)->string-value : '';

    my $display-key-type =
        findnodes($xpath, '/ldml/localeDisplayNames/localeDisplayPattern/localeKeyTypePattern');
    $display-key-type = $display-key-type->size ? $display-key-type->get-node(1)->string-value : '';

    return unless defined $display-pattern;
    foreach ($display-pattern, $display-seperator, $display-key-type) {
        s/\//\/\//g;
        s/'/\\'/g;
    }

    print $file <<EOT;
# Need to add code for Key type pattern
sub display-name-pattern {
\tmy (\$self, \$name, \$region, \$script, \$variant) = \@-;

\tmy \$display-pattern = '$display-pattern';
\t\$display-pattern =~s/\\\{0\\\}/\$name/g;
\tmy \$subtags = join '$display-seperator', grep {\$-} (
\t\t\$region,
\t\t\$script,
\t\t\$variant,
\t);

\t\$display-pattern =~s/\\\{1\\\}/\$subtags/g;
\treturn \$display-pattern;
}

EOT
}

sub process-display-language {
    my ($file, $xpath) = @-;
    say "Processing Display Language"
        if $verbose;

    my $languages = findnodes($xpath,'/ldml/localeDisplayNames/languages/language');

    return unless $languages->size;
    my @languages = $languages->get-nodelist;
    foreach my $language (@languages) {
        my $type = $language->getAttribute('type');
        my $variant = $language->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }
        my $name = $language->getChildNode(1);
        next unless $name;
        $name = $name->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $language = "\t\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display-name-language' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t sub {
\t\t\t my %languages = (
@languages
\t\t\t);
\t\t\tif (\@-) {
\t\t\t\treturn \$languages{\$-[0]};
\t\t\t}
\t\t\treturn \\%languages;
\t\t}
\t},
);

EOT
}

sub process-display-script {
    my ($file, $xpath) = @-;

    say "Processing Display Script"
        if $verbose;

    my $scripts = findnodes($xpath, '/ldml/localeDisplayNames/scripts/script');

    return unless $scripts->size;
    my @scripts = $scripts->get-nodelist;
    foreach my $script (@scripts) {
        my $type = $script->getAttribute('type');
        my $variant = $script->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }
        my $name = $script->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $script = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display-name-script' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\tsub {
\t\t\tmy %scripts = (
@scripts
\t\t\t);
\t\t\tif ( \@- ) {
\t\t\t\treturn \$scripts{\$-[0]};
\t\t\t}
\t\t\treturn \\%scripts;
\t\t}
\t}
);

EOT
}

sub process-display-region {
    my ($file, $xpath) = @-;

    say "Processing Display region"
        if $verbose;

    my $regions = findnodes($xpath, '/ldml/localeDisplayNames/territories/territory');

    return unless $regions->size;
    my @regions = $regions->get-nodelist;
    foreach my $region (@regions) {
        my $type = $region->getAttribute('type');
        my $variant = $region->getAttribute('alt');
        if ($variant) {
            $type .= "\@alt=$variant";
        }

        my $node = $region->getChildNode(1);
        my $name = $node ? $node->getValue : '';
        $name =~s/\\/\/\\/g;
        $name =~s/'/\\'/g;
        $region = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display-name-region' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@regions
\t\t}
\t},
);

EOT
}

sub process-display-variant {
    my ($file, $xpath) = @-;

    say "Processing Display Variant"
        if $verbose;

    my $variants= findnodes($xpath, '/ldml/localeDisplayNames/variants/variant');

    return unless $variants->size;
    my @variants = $variants->get-nodelist;
    foreach my $variant (@variants) {
        my $type = $variant->getAttribute('type');
        my $variant-attr = $variant->getAttribute('alt');
        if ($variant-attr) {
            $type .= "\@alt=$variant-attr";
        }
        my $name = $variant->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $variant = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display-name-variant' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@variants
\t\t}
\t},
);

EOT
}

sub process-display-key {
    my ($file, $xpath) = @-;

    say "Processing Display Key"
        if $verbose;

    my $keys= findnodes($xpath, '/ldml/localeDisplayNames/keys/key');

    return unless $keys->size;
    my @keys = $keys->get-nodelist;
    foreach my $key (@keys) {
        my $type = lc $key->getAttribute('type');
        my $name = $key->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $key = "\t\t\t'$type' => '$name',\n";
    }

    print $file <<EOT;
has 'display-name-key' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@keys
\t\t}
\t},
);

EOT
}

sub process-display-type {
    my ($file, $xpath) = @-;

    say "Processing Display Type"
        if $verbose;

    my $types = findnodes($xpath, '/ldml/localeDisplayNames/types/type');
    return unless $types->size;

    my @types = $types->get-nodelist;
    my %values;
    foreach my $type-node (@types) {
        my $type = lc $type-node->getAttribute('type');
        my $key  = lc $type-node->getAttribute('key');
        my $value = $type-node->getChildNode(1)->getValue;
        $type //= 'default';
        $values{$key}{$type} = $value;
    }
    @types = ();
    foreach my $key (sort keys %values) {
        push @types, "\t\t\t'$key' => {\n";
        foreach my $type (sort keys %{$values{$key}}) {
            push @types, "\t\t\t\t'$type' => q{$values{$key}{$type}},\n";
        }
        push @types, "\t\t\t},\n";
    }

    print $file <<EOT;
has 'display-name-type' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[HashRef[Str]],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@types
\t\t}
\t},
);

EOT
}

sub process-display-measurement-system-name {
    my ($file, $xpath) = @-;

    say "Processing Display Mesurement System"
        if $verbose;

    my $names = findnodes($xpath, '/ldml/localeDisplayNames/measurementSystemNames/measurementSystemName');
    return unless $names->size;

    my @names = $names->get-nodelist;
    foreach my $name (@names) {
        my $type = $name->getAttribute('type');
        my $value = $name->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $name = "\t\t\t'$type' => q{$value},\n";
    }

    print $file <<EOT;
has 'display-name-measurement-system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@names
\t\t}
\t},
);

EOT
}

sub process-display-transform-name {
    my ($file, $xpath) = @-;

    say "Processing Display Transform Names"
        if $verbose;

    my $names = findnodes($xpath, '/ldml/localeDisplayNames/transformNames/transformName');
    return unless $names->size;

    my @names = $names->get-nodelist;
    foreach my $name (@names) {
        my $type = lc $name->getAttribute('type');
        my $value = $name->getChildNode(1)->getValue;
        $name =~s/\\/\\\\/g;
        $name =~s/'/\\'/g;
        $name = "\t\t\t'$type' => '$value',\n";
    }

    print $file <<EOT;
has 'display-name-transform-name' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@names
\t\t}
\t},
);

EOT
}

sub process-code-patterns {
    my ($file, $xpath) = @-;
    say "Processing Code Patterns"
        if $verbose;

    my $patterns = findnodes($xpath, '/ldml/localeDisplayNames/codePatterns/codePattern');
    return unless $patterns->size;

    my @patterns = $patterns->get-nodelist;
    foreach my $pattern (@patterns) {
        my $type = $pattern->getAttribute('type');
		$type = 'region' if $type eq 'territory';
        my $value = $pattern->getChildNode(1)->getValue;
        $pattern =~s/\\/\\\\/g;
        $pattern =~s/'/\\'/g;
        $pattern = "\t\t\t'$type' => '$value',\n";
    }

    print $file <<EOT;
has 'display-name-code-patterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\t{
@patterns
\t\t}
\t},
);

EOT
}

sub process-orientation {
    my ($file, $xpath) = @-;

    say "Processing Orientation" if $verbose;
    my $character-orientation = findnodes($xpath, '/ldml/layout/orientation/characterOrder');
    my $line-orientation = findnodes($xpath, '/ldml/layout/orientation/lineOrder');
    return unless $character-orientation->size
        || $line-orientation->size;

    my ($lines) = $line-orientation->get-nodelist;
        $lines = ($lines && $lines->getChildNode(1)->getValue) || '';
    my ($characters) = $character-orientation->get-nodelist;
        $characters = ($characters && $characters->getChildNode(1)->getValue) || '';

    print $file <<EOT;
has 'text-orientation' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { return {
\t\t\tlines => '$lines',
\t\t\tcharacters => '$characters',
\t\t}}
);

EOT
}

sub process-exemplar-characters {
    my ($file, $xpath) = @-;

    say "Processing Exemplar Characters" if $verbose;
    my $characters = findnodes($xpath, '/ldml/characters/exemplarCharacters');
    return unless $characters->size;

    my @characters = $characters->get-nodelist;
    my %data;
    foreach my $node (@characters) {
        my $regex = $node->getChildNode(1)->getValue;
		next if $regex =~ /^\[\s*\]/;
        my $type = $node->getAttribute('type');
        $type ||= 'main';
        if ($type eq 'index') {
            my ($entries) = $regex =~ m{\A \s* \[ (.*) \] \s* \z}msx;
            $entries = join "', '", split( /\s+/, $entries);
            $entries =~ s{\{\}}{}g;
            $data{index} = "['$entries'],";
        }
        else {
		    $regex = unicode-to-perl($regex);
            $data{$type} = "qr{$regex},";
        }
    }
    print $file <<EOT;
has 'characters' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> \$^V ge v5.18.0
\t? eval <<'EOT'
\tsub {
\t\tno warnings 'experimental::regex-sets';
\t\treturn {
EOT
    foreach my $type (sort keys %data) {
        say $file "\t\t\t$type => $data{$type}";
    }
    print $file <<EOFILE;
\t\t};
\t},
EOT
: sub {
EOFILE
if ($data{index}) {
	say $file "\t\treturn { index => $data{index} };"
}
else {
	say $file "\t\treturn {};";
}

say $file <<EOFILE
},
);

EOFILE
}

sub process-ellipsis {
    my ($file, $xpath) = @-;

    say "Processing Ellipsis" if $verbose;
    my $ellipsis = findnodes($xpath, '/ldml/characters/ellipsis');
    return unless $ellipsis->size;
    my @ellipsis = $ellipsis->get-nodelist;
    my %data;
    foreach my $node (@ellipsis) {
        my $pattern = $node->getChildNode(1)->getValue;
        my $type = $node->getAttribute('type');
        $data{$type} = $pattern;
    }
    print $file <<EOT;
has 'ellipsis' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub {
\t\treturn {
EOT
    foreach my $type (sort keys %data) {
        say $file "\t\t\t'$type' => '$data{$type}',";
    }
    print $file <<EOT;
\t\t};
\t},
);

EOT
}

sub process-more-information {
    my ($file, $xpath) = @-;

    say 'Processing More Information' if $verbose;
    my $info = findnodes($xpath, '/ldml/characters/moreInformation');
    return unless $info->size;
    my @info = $info->get-nodelist;
    $info = $info[0]->getChildNode(1)->getValue;

    print $file <<EOT;
has 'more-information' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit-arg\t=> undef,
\tdefault\t\t=> qq{$info},
);

EOT
}

sub process-delimiters {
    my ($file, $xpath) = @-;

    say 'Processing Delimiters' if $verbose;
    my %quote;
    $quote{quote-start}             = findnodes($xpath, '/ldml/delimiters/quotationStart');
    $quote{quote-end}               = findnodes($xpath, '/ldml/delimiters/quotationEnd');
    $quote{alternate-quote-start}   = findnodes($xpath, '/ldml/delimiters/alternateQuotationStart');
    $quote{alternate-quote-end}     = findnodes($xpath, '/ldml/delimiters/alternateQuotationEnd');

    return unless $quote{quote-start}->size
        || $quote{quote-end}->size
        || $quote{alternate-quote-start}->size
        || $quote{alternate-quote-end}->size;

    foreach my $quote (qw(quote-start quote-end alternate-quote-start alternate-quote-end)) {
        next unless ($quote{$quote}->size);

        my @quote = $quote{$quote}->get-nodelist;
        my $value = $quote[0]->getChildNode(1)->getValue;

        print $file <<EOT;
has '$quote' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit-arg\t=> undef,
\tdefault\t\t=> qq{$value},
);

EOT
    }
}

sub process-measurement-system-data {
	my ($file, $xpath) = @-;

	say 'Processing Measurement System Data' if $verbose;
	my $measurementData = findnodes($xpath, '/supplementalData/measurementData/*');
	return unless $measurementData->size;

	my @measurementSystem;
	my @paperSize;

	foreach my $measurement ($measurementData->get-nodelist) {
		my $what = $measurement->getLocalName;
		my $type = $measurement->getAttribute('type');
		my $regions = $measurement->getAttribute('territories');

		push @{$what eq 'measurementSystem' ? \@measurementSystem : \@paperSize },
			[$type, $regions ];
	}

	print $file <<EOT;
has 'measurement-system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $measurement ( @measurementSystem ) {
		foreach my $region (split /\s+/, $measurement->[1]) {
			say $file "\t\t\t\t'$region'\t=> '$measurement->[0]',";
		}
	}

	print $file <<EOT;
\t\t\t} },
);

EOT

	print $file <<EOT;
has 'paper-size' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $paper-size ( @paperSize) {
		foreach my $region (split /\s+/, $paper-size->[1]) {
			say $file "\t\t\t\t'$region'\t=> '$paper-size->[0]',";
		}
	}

	print $file <<EOT;
\t\t\t} },
);

EOT
}

sub get-parent-locales {
	my $xpath = shift;
	my $parentData = findnodes($xpath, '/supplementalData/parentLocales/*');
	my %parents;
	foreach my $parent-node ($parentData->get-nodelist) {
		my $parent = $parent-node->getAttribute('parent');
		my @locales = split / /, $parent-node->getAttribute('locales');
		foreach my $locale (@locales, $parent) {
			my @path = split /-/, $locale;
			@path = ($path[0], 'Any', $path[1])
				if ( @path == 2 );
			$locale = join '::', 'Locale::CLDR::Locales', map { ucfirst lc } @path;
		}
		@parents{@locales} = ($parent) x @locales;
	}

	return %parents;
}

sub process-units {
    my ($file, $xpath) = @-;

    say 'Processing Units' if $verbose;
	my $units = findnodes($xpath, '/ldml/units/*');
    return unless $units->size;

    my (%units, %aliases, %duration-units);
    foreach my $length-node ($units->get-nodelist) {
		my $length = $length-node->getAttribute('type');
		my $units = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/*));
		my $duration-units = findnodes($xpath, qq(/ldml/units/durationUnit[\@type="$length"]/durationUnitPattern));

		foreach my $duration-unit ($duration-units->get-nodelist) {
			my $patten = $duration-unit->getChildNode(1)->getValue;
			$duration-units{$length} = $patten;
		}

		my $unit-alias = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/alias));
		if ($unit-alias->size) {
			my ($node) = $unit-alias->get-nodelist;
			my $path = $node->getAttribute('path');
			my ($type) = $path =~ /\[\@type=['"](.*)['"]\]/;
			$aliases{$length} = $type;
		}

		foreach my $unit-type ($units->get-nodelist) {
			my $unit-type-name = $unit-type->getAttribute('type') // '';
			my $unit-type-alias = findnodes($xpath, qq(/ldml/units/unitLength[\@type="$length"]/unit[\@type="$unit-type-name"]/alias));
			if ($unit-type-alias->size) {
				my ($node) = $unit-type-alias->get-nodelist;
				my $path = $node->getAttribute('path');
				my ($type) = $path =~ /\[\@type=['"](.*)['"]\]/;
				$aliases{$length}{$unit-type-name} = $type;
				next;
			}
			$unit-type-name =~ s/^[^\-]+-//;
			foreach my $unit-pattern ($unit-type->getChildNodes) {
				next if $unit-pattern->isTextNode;

				my $count = $unit-pattern->getAttribute('count') || 1;
				$count = 'name' if $unit-pattern->getLocalName eq 'displayName';
				$count = 'per' if $unit-pattern->getLocalName eq 'perUnitPattern';
				if ($unit-pattern->getLocalName eq 'coordinateUnitPattern') {
					$unit-type-name = 'coordinate';
					$count = $unit-pattern->getAttribute('type');
				}
				my $pattern = $unit-pattern->getChildNode(1)->getValue;
				$units{$length}{$unit-type-name}{$count} = $pattern;
			}
		}
    }

	if (keys %duration-units) {
		print $file <<EOT;
has 'duration-units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[Str],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $type (sort keys %duration-units) {
			my $units = $duration-units{$type};
			$units =~ s/'/\\'/g; # Escape a ' in unit name
			say $file "\t\t\t\t$type => '$units',";
		}

		print $file <<EOT;
\t\t\t} }
);

EOT
	}

	if (keys %aliases) {
		print $file <<EOT;
has 'unit-alias' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $from (sort keys %aliases) {
			if (ref $aliases{$from}) {
				say $file "\t\t\t\t$from => {";
				foreach my $old-unit (sort keys %{$aliases{$from}}) {
					say $file "\t\t\t\t\t'$old-unit' => '$aliases{$from}{$old-unit}',";
				}
				say $file "\t\t\t\t},";
			}
			else {
				say $file "\t\t\t\t$from => '$aliases{$from}',";
			}
		}

		print $file <<EOT;
\t\t\t} }
);

EOT
	}

    print $file <<EOT;
has 'units' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef[HashRef[HashRef[Str]]],
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
    foreach my $length (sort keys %units) {
        say $file "\t\t\t\t'",$length,"' => {";
        foreach my $type (sort keys %{$units{$length}}) {
            say $file "\t\t\t\t\t'$type' => {";
                foreach my $count (sort keys %{$units{$length}{$type}}) {
                    say $file "\t\t\t\t\t\t'$count' => q(",
                        $units{$length}{$type}{$count},
                        "),";
                }
            say $file "\t\t\t\t\t},";
        }
        say $file "\t\t\t\t},";
    }
    print $file <<EOT;
\t\t\t} }
);

EOT
}

sub process-posix {
    my ($file, $xpath) = @-;

    say 'Processing Posix' if $verbose;
    my $yes = findnodes($xpath, '/ldml/posix/messages/yesstr/text()');
    my $no  = findnodes($xpath, '/ldml/posix/messages/nostr/text()');
    return unless $yes->size || $no->size;
    $yes = $yes->size
      ? ($yes->get-nodelist)[0]->getValue()
      : '';

    $no = $no->size
      ? ($no->get-nodelist)[0]->getValue()
      : '';

    $yes .= ':yes:y' unless (grep /^y/i, split /:/, "$yes:$no");
    $no  .= ':no:n'  unless (grep /^n/i, split /:/, "$yes:$no");

    s/:/|/g foreach ($yes, $no);
	s/'/\\'/g foreach ($yes, $no);

    print $file <<EOT if defined $yes;
has 'yesstr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> RegexpRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$yes)\$' }
);

EOT

    print $file <<EOT if defined $no;
has 'nostr' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> RegexpRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { qr'^(?i:$no)\$' }
);

EOT
}

# List patterns
#/ldml/listPatterns/
sub process-list-patterns {
	my ($file, $xpath) = @-;

	say "Processing List Patterns" if $verbose;

	my $patterns = findnodes($xpath, '/ldml/listPatterns/listPattern/listPatternPart');

	return unless $patterns->size;

	my %patterns;
	foreach my $pattern ($patterns->get-nodelist) {
		my $type = $pattern->getAttribute('type');
		my $text = $pattern->getChildNode(1)->getValue;
		$patterns{$type} = $text;
	}

	print $file <<EOT;
has 'listPatterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
	my %sort-lookup = (start => 0, middle => 1, end => 2, 2 => 3, 3 => 4);
	no warnings;
	foreach my $type ( sort {
		(($a + 0) <=> ($b + 0))
		|| ( $sort-lookup{$a} <=> $sort-lookup{$b})
	} keys %patterns ) {
		say $file "\t\t\t\t$type => q($patterns{$type}),"
	}

	print $file <<EOT;
\t\t} }
);

EOT

}

#/ldml/contextTransforms
sub process-context-transforms {
	my ($file, $xpath) = @-;
	# TODO fix this up
}

#/ldml/numbers
sub process-numbers {
	my ($file, $xpath) = @-;

	say "Processing Numbers" if $verbose;

	my $default-numbering-system = '';
	my $nodes = findnodes($xpath, '/ldml/numbers/defaultNumberingSystem/text()');
	if ($nodes->size) {
		$default-numbering-system = ($nodes->get-nodelist)[0]->getValue;
	}

	# Other Numbering systems
	my %other-numbering-systems;
	$other-numbering-systems{native} = '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/native/text()');
	if ($nodes->size) {
		$other-numbering-systems{native} = ($nodes->get-nodelist)[0]->getValue;
	}

	$other-numbering-systems{traditional} =  '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/traditional/text()');
	if ($nodes->size) {
		$other-numbering-systems{traditional} =  ($nodes->get-nodelist)[0]->getValue;
	}

	$other-numbering-systems{finance} =  '';
	$nodes = findnodes($xpath, '/ldml/numbers/otherNumberingSystems/finance/text()');
	if ($nodes->size) {
		$other-numbering-systems{finance} = ($nodes->get-nodelist)[0]->getValue;
	}

	# minimum grouping digits
	my $minimum-grouping-digits-nodes = findnodes($xpath, '/ldml/numbers/minimumGroupingDigits/text()');
	my $minimum-grouping-digits = 0;
	if ($minimum-grouping-digits-nodes->size) {
		$minimum-grouping-digits = ($minimum-grouping-digits-nodes->get-nodelist)[0]->getValue;
		# Fix for invalid data in Nepalise language data
		$minimum-grouping-digits = $minimum-grouping-digits =~ /^[0-9]+$/ ? $minimum-grouping-digits : 1;
	}

	# Symbols
	my %symbols;
	my $symbols-nodes = findnodes($xpath, '/ldml/numbers/symbols');
	foreach my $symbols ($symbols-nodes->get-nodelist) {
		my $type = $symbols->getAttribute('numberSystem') // '';
		foreach my $symbol ( qw( alias decimal group list percentSign minusSign plusSign exponential superscriptingExponent perMille infinity nan currencyDecimal currencyGroup timeSeparator) ) {
			if ($symbol eq 'alias') {
				my $nodes = findnodes($xpath, qq(/ldml/numbers/symbols[\@numberSystem="$type"]/$symbol/\@path));
				next unless $nodes->size;
				my ($alias) = ($nodes->get-nodelist)[0]->getValue =~ /\[\@numberSystem='(.*?)'\]/;
				$symbols{$type}{alias} = $alias;
			}
			else {
				my $nodes = findnodes($xpath, qq(/ldml/numbers/symbols[\@numberSystem="$type"]/$symbol/text()));
				next unless $nodes->size;
				$symbols{$type}{$symbol} = ($nodes->get-nodelist)[0]->getValue;
			}
		}
	}

	# Formats
	my %formats;
	foreach my $format-type ( qw( decimalFormat percentFormat scientificFormat ) ) {
		my $format-nodes = findnodes($xpath, qq(/ldml/numbers/${format-type}s));
		foreach my $format-node ($format-nodes->get-nodelist) {
			my $number-system = $format-node->getAttribute('numberSystem') // '';
			my $format-xpath = qq(/ldml/numbers/${format-type}s[\@numberSystem="$number-system"]);
			$format-xpath = qq(/ldml/numbers/${format-type}s[not(\@numberSystem)]) unless $number-system;
			my $format-alias-nodes = findnodes($xpath, "$format-xpath/alias");
			if ($format-alias-nodes->size) {
				my ($alias) = ($format-alias-nodes->get-nodelist)[0]->getAttribute('path') =~ /\[\@numberSystem='(.*?)'\]/;
				$formats{$number-system || 'default'}{alias} = $alias;
			}
			else {
				my $format-nodes-length = findnodes($xpath, "/ldml/numbers/${format-type}s/${format-type}Length");
				foreach my $format-node ( $format-nodes-length->get-nodelist ) {
					my $length-type = $format-node->getAttribute('type');
					my $attribute = $length-type ? qq([\@type="$length-type"]) : '';
					my $nodes = findnodes($xpath, "/ldml/numbers/${format-type}s/${format-type}Length$attribute/$format-type/alias/\@path");
					if ($nodes->size) {
						my $alias = ($nodes->get-nodelist)[0]->getValue =~ /${format-type}Length\[\@type='(.*?)'\]/;
						$formats{$format-type}{$length-type || 'default'}{alias} = $alias;
					}
					else {
						my $pattern-nodes = findnodes($xpath, "/ldml/numbers/${format-type}s/${format-type}Length$attribute/$format-type/pattern");
						foreach my $pattern ($pattern-nodes->get-nodelist) {
							my $pattern-type = $pattern->getAttribute('type') || 0;
							my $pattern-count = $pattern->getAttribute('count') // 'default';
							my $pattern-text = $pattern->getChildNode(1)->getValue();
							$formats{$format-type}{$length-type || 'default'}{$pattern-type}{$pattern-count} = $pattern-text;
						}
					}
				}
			}
		}
	}

	# Currency Formats
	my %currency-formats;
	my $currency-format-nodes = findnodes($xpath, "/ldml/numbers/currencyFormats");
	foreach my $currency-format-node ($currency-format-nodes->get-nodelist) {
		my $number-system = $currency-format-node->getAttribute('numberSystem') // 'latn';

		# Check for alias
		my $alias-nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number-system"]/alias));
		if ($alias-nodes->size) {
			my $alias-node = ($alias-nodes->get-nodelist)[0];
			my ($alias) = $alias-node->getAttribute('path') =~ /currencyFormats\[\@numberSystem='(.*?)'\]/;
			$currency-formats{$number-system}{alias} = $alias;
		}
		else {
			foreach my $location (qw( beforeCurrency afterCurrency )) {
				foreach my $data (qw( currencyMatch surroundingMatch insertBetween ) ) {
					my $nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number-system"]/currencySpacing/$location/$data/text()));
					next unless $nodes->size;
					my $text = ($nodes->get-nodelist)[0]->getValue;
					$currency-formats{$number-system}{position}{$location}{$data} = $text;
				}
			}

			foreach my $currency-format-type (qw( standard accounting )) {
				my $length-nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number-system"]/currencyFormatLength));
				foreach my $length-node ($length-nodes->get-nodelist) {
					my $length-node-type = $length-node->getAttribute('type') // '';
					my $length-node-type-text = $length-node-type ? qq([type="$length-node-type"]) : '';

					foreach my $currency-type (qw( standard accounting )) {
						# Check for aliases
						my $alias-nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number-system"]/currencyFormatLength$length-node-type-text/currencyFormat[\@type="$currency-type"]/alias));
						if ($alias-nodes->size) {
							my ($alias) = ($alias-nodes->get-nodelist)[0]->getAttribute('path') =~ /currencyFormat\[\@type='(.*?)'\]/;
							$currency-formats{$number-system}{pattern}{$length-node-type || 'default'}{$currency-type}{alias} = $alias;
						}
						else {
							my $pattern-nodes = findnodes($xpath, qq(/ldml/numbers/currencyFormats[\@numberSystem="$number-system"]/currencyFormatLength$length-node-type-text/currencyFormat[\@type="$currency-type"]/pattern/text()));
							next unless $pattern-nodes->size;
							my $pattern = ($pattern-nodes->get-nodelist)[0]->getValue;
							my ($positive, $negative) = split /;/, $pattern;
							$currency-formats{$number-system}{pattern}{$length-node-type || 'default'}{$currency-type}{positive} = $positive;
							$currency-formats{$number-system}{pattern}{$length-node-type || 'default'}{$currency-type}{negative} = $negative
								if defined $negative;
						}
					}
				}
			}
		}
	}

	# Currencies
	my %currencies;
	my $currency-nodes = findnodes($xpath, "/ldml/numbers/currencies/currency");
	foreach my $currency-node ($currency-nodes->get-nodelist) {
		my $currency-code = $currency-node->getAttribute('type');
		my $currency-symbol-nodes = findnodes($xpath, "/ldml/numbers/currencies/currency[\@type='$currency-code']/symbol/text()");
		if ($currency-symbol-nodes->size) {
			$currencies{$currency-code}{currency-symbol} = ($currency-symbol-nodes->get-nodelist)[0]->getValue;
		}
		my $display-name-nodes = findnodes($xpath, "/ldml/numbers/currencies/currency[\@type='$currency-code']/displayName");
		foreach my $display-name-node ($display-name-nodes->get-nodelist) {
			my $count = $display-name-node->getAttribute('count') || 'currency';
			my $name = $display-name-node->getChildNode(1)->getValue();
			$currencies{$currency-code}{display-name}{$count} = $name;
		}
	}

	# Write out data
	print $file <<EOT if $default-numbering-system;
has 'default-numbering-system' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit-arg\t=> undef,
\tdefault\t\t=> '$default-numbering-system',
);

EOT

	foreach my $numbering-system (qw( native traditional finance )) {
		if ($other-numbering-systems{$numbering-system}) {
			print $file <<EOT;
has ${numbering-system}-numbering-system => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> Str,
\tinit-arg\t=> undef,
\tdefault\t\t=> '$other-numbering-systems{$numbering-system}',
);

EOT
		}
	}

	# Minimum grouping digits
	print $file <<EOT if $minimum-grouping-digits;
has 'minimum-grouping-digits' => (
\tis\t\t\t=>'ro',
\tisa\t\t\t=> Int,
\tinit-arg\t=> undef,
\tdefault\t\t=> $minimum-grouping-digits,
);

EOT
	if (keys %symbols) {
		print $file <<EOT;
has 'number-symbols' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number-system (sort keys %symbols) {
			if (exists $symbols{$number-system}{alias}) {
				say $file "\t\t'$number-system' => { 'alias' => '$symbols{$number-system}{alias}' },"
			}
			else {
				say $file "\t\t'$number-system' => {";
				foreach my $symbol (sort keys %{$symbols{$number-system}}) {
					say $file "\t\t\t'$symbol' => q($symbols{$number-system}{$symbol}),";
				}
				say $file "\t\t},";
			}
		}
		print $file <<EOT;
\t} }
);

EOT
	}

	if (keys %formats) {
		print $file <<EOT;
has 'number-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number-system (sort keys %formats) {
			say $file "\t\t$number-system => {";
			foreach my $length ( sort keys %{$formats{$number-system}} ) {
				if ($length eq 'alias') {
					say $file "\t\t\t'alias' => '$formats{$number-system}{alias}',";
				}
				else {
					say $file "\t\t\t'$length' => {";
					foreach my $pattern-type (sort keys %{$formats{$number-system}{$length}}) {
						if ($pattern-type eq 'alias') {
							say $file "\t\t\t\t'alias' => '$formats{$number-system}{$length}{alias}',";
						}
						else {
							say $file "\t\t\t\t'$pattern-type' => {";
							foreach my $count (sort keys %{$formats{$number-system}{$length}{$pattern-type}}) {
								say $file "\t\t\t\t\t'$count' => '$formats{$number-system}{$length}{$pattern-type}{$count}',";
							}
							say $file "\t\t\t\t},";
						}
					}
					say $file "\t\t\t},";
				}
			}
			say $file "\t\t},";
		}
		print  $file <<EOT;
} },
);

EOT
	}

	if (keys %currency-formats) {
		print $file <<EOT;
has 'number-currency-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $number-system (sort keys %currency-formats ) {
			say $file "\t\t'$number-system' => {";
			foreach my $type (sort keys %{$currency-formats{$number-system}}) {
				if ($type eq 'alias') {
					say $file "\t\t\t'alias' => '$currency-formats{$number-system}{alias}',";
				}
				elsif ($type eq 'position') {
					say $file "\t\t\t'possion' => {";
					foreach my $location (sort keys %{$currency-formats{$number-system}{position}}) {
						say $file "\t\t\t\t'$location' => {";
						foreach my $data (sort keys %{$currency-formats{$number-system}{position}{$location}}) {
							say $file "\t\t\t\t\t'$data' => '$currency-formats{$number-system}{position}{$location}{$data}',";
						}
						say $file "\t\t\t\t},";
					}
					say $file "\t\t\t},";
				}
				else {
					say $file "\t\t\t'pattern' => {";
					foreach my $length (sort keys %{$currency-formats{$number-system}{pattern}}) {
						say $file "\t\t\t\t'$length' => {";
						foreach my $currency-type (sort keys %{$currency-formats{$number-system}{pattern}{$length}} ) {
							say $file "\t\t\t\t\t'$currency-type' => {";
							foreach my $p-n-a (sort keys %{$currency-formats{$number-system}{pattern}{$length}{$currency-type}}) {
								say $file "\t\t\t\t\t\t'$p-n-a' => '$currency-formats{$number-system}{pattern}{$length}{$currency-type}{$p-n-a}',";
							}
							say $file "\t\t\t\t\t},";
						}
						say $file "\t\t\t\t},";
					}
					say $file "\t\t\t},";
				}
			}
			say $file "\t\t},";
		}
		print  $file <<EOT;
} },
);

EOT
	}

	if (keys %currencies) {
		print $file <<EOT;
has 'currencies' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
		foreach my $currency (sort keys %currencies) {
			say $file "\t\t'$currency' => {";
			say $file "\t\t\tsymbol => '$currencies{$currency}{currency-symbol}',"
				if exists $currencies{$currency}{currency-symbol};

			if ( exists $currencies{$currency}{display-name} ) {
				say $file "\t\t\tdisplay-name => {";
				foreach my $count (sort keys %{$currencies{$currency}{display-name}}) {
					my $display-name = $currencies{$currency}{display-name}{$count};
					$display-name = $display-name =~ s/\(/\\(/gr =~ s/\)/\\)/gr;
					say $file "\t\t\t\t'$count' => q($display-name),";
				}
				say $file "\t\t\t},";
			}
			say $file "\t\t},";
		}

		say $file <<EOT;
\t} },
);

EOT
	}
}

# Default currency data
sub process-currency-data {
	my ($file, $xml) = @-;

	say "Processing currency data" if $verbose;

	# Do fraction data
	my $fractions = findnodes($xml, '/supplementalData/currencyData/fractions/info');
	my %fractions;
	foreach my $node ($fractions->get-nodelist) {
		$fractions{$node->getAttribute('iso4217')} = {
			digits			=> $node->getAttribute('digits'),
			rounding		=> $node->getAttribute('rounding'),
			cashrounding	=> $node->getAttribute('cashRounding') 	|| $node->getAttribute('rounding'),
			cashdigits		=> $node->getAttribute('cashDigits') 	|| $node->getAttribute('digits'),
		};
	}

	# Do default Currency data
	# The data set provides historical data which I'm ignoring for now
	my %default-currency;
	my $default-currencies = findnodes($xml, '/supplementalData/currencyData/region');
	foreach my $node ( $default-currencies->get-nodelist ) {
		my $region = $node->getAttribute('iso3166');

		my $currencies = findnodes($xml, qq(/supplementalData/currencyData/region[\@iso3166="$region"]/currency[not(\@to)]));

		next unless $currencies->size;

		my ($currency) = $currencies->get-nodelist;
		$currency = $currency->getAttribute('iso4217');
		$default-currency{$region} = $currency;
	}

	say $file <<EOT;
has '-currency-fractions' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $fraction (sort keys %fractions) {
		say $file "\t\t$fraction => {";
		foreach my $type ( qw(digits rounding cashdigits cashrounding ) ) {
			say $file "\t\t\t'$type' => '$fractions{$fraction}{$type}',";
		}
		say $file "\t\t},";
	}

	say $file <<'EOT';
	} },
);

sub currency-fractions {
	my ($self, $currency) = @-;

	my $currency-data = $self->-currency-fractions()->{$currency};

	$currency-data = {
		digits 			=> 2,
		cashdigits 		=> 2,
		rounding 		=> 0,
		cashrounding	=> 0,
	} unless $currency-data;

	return $currency-data;
}

has '-default-currency' => (
	is			=> 'ro',
	isa			=> HashRef,
	init-arg	=> undef,
	default		=> sub { {
EOT

	foreach my $region (sort keys %default-currency) {
		say $file "\t\t\t\t'$region' => '$default-currency{$region}',";
	}

	say $file <<EOT;
\t } },
);

EOT
}


# region Containment data
sub process-region-containment-data {
	my ($file, $xpath) = @-;

	my $data = findnodes($xpath, q(/supplementalData/territoryContainment/group[not(@status) or @status!='deprecated']));

	my %contains;
	my %contained-by;
	foreach my $node ($data->get-nodelist) {
		my $base = $node->getAttribute('type');
		my @contains = split /\s+/, $node->getAttribute('contains');
		push @{$contains{$base}}, @contains;
        # Ignore UN, EU and EZ political regions, use the gographical region only
        next if grep { $base eq $- } qw(UN EU EZ);
		@contained-by{@contains} = ($base) x @contains;
	}

	say $file <<EOT;
has 'region-contains' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $region ( sort { ($a =~ /^\d$/a && $b =~ /^\d$/a && $a <=> $b ) || $a cmp $b } keys %contains ) {
		say $file "\t\t'$region' => [ qw( @{$contains{$region}} ) ], ";
	}

	say $file <<EOT;
\t} }
);

has 'region-contained-by' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

	foreach my $region ( sort { ($a =~ /^\d$/a && $b =~ /^\d$/a && $a <=> $b )  || $a cmp $b } keys %contained-by ) {
		say $file "\t\t'$region' => '$contained-by{$region}', ";
	}

	say $file <<EOT;
\t} }
);

EOT
}

# Dates
#/ldml/dates/calendars/
sub process-calendars {
    my ($file, $xpath, $local) = @-;

    say "Processing Calendars" if $verbose;

    my $calendars = findnodes($xpath, '/ldml/dates/calendars/calendar');

    return unless $calendars->size;

    my %calendars;
    foreach my $calendar ($calendars->get-nodelist) {
        my $type = $calendar->getAttribute('type');
        my ($months) = process-months($xpath, $type);
        $calendars{months}{$type} = $months if $months;
        my ($days) = process-days($xpath, $type);
        $calendars{days}{$type} = $days if $days;
        my $quarters = process-quarters($xpath, $type);
        $calendars{quarters}{$type} = $quarters if $quarters;
        my $day-periods = process-day-periods($xpath, $type);
        $calendars{day-periods}{$type} = $day-periods if $day-periods;
        my $eras = process-eras($xpath, $type);
        $calendars{eras}{$type} = $eras if $eras;
        my $day-period-data = process-day-period-data($local);
        $calendars{day-period-data}{$type} = $day-period-data if $day-period-data;
        my $date-formats = process-date-formats($xpath, $type);
        $calendars{date-formats}{$type} = $date-formats if $date-formats;
        my $time-formats = process-time-formats($xpath, $type);
        $calendars{time-formats}{$type} = $time-formats if $time-formats;
        my $datetime-formats = process-datetime-formats($xpath, $type);
        $calendars{datetime-formats}{$type} = $datetime-formats if $datetime-formats;
        my $month-patterns = process-month-patterns($xpath, $type);
        $calendars{month-patterns}{$type} = $month-patterns if $month-patterns;
        my $cyclic-name-sets = process-cyclic-name-sets($xpath, $type);
        $calendars{cyclic-name-sets}{$type} = $cyclic-name-sets if $cyclic-name-sets;
    }

    # Got all the data now write it out to the file;
    if (keys %{$calendars{months}}) {
        print $file <<EOT;
has 'calendar-months' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{months}}) {

            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{months}{$type}} ) {
                if ($context eq 'alias') {
					say $file "\t\t\t\t'alias' => '$calendars{months}{$type}{alias}',";
					next;
				}

                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{months}{$type}{$context}}) {
                    if (exists $calendars{months}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{months}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{months}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }

                    print $file "\t\t\t\t\t$width => {\n\t\t\t\t\t\tnonleap => [\n\t\t\t\t\t\t\t";

                    say $file join ",\n\t\t\t\t\t\t\t",
                        map {
                            my $month = $- // '';
                            $month =~ s/'/\\'/g;
                            $month = "'$month'";
                        } @{$calendars{months}{$type}{$context}{$width}{nonleap}};
                    print $file "\t\t\t\t\t\t],\n\t\t\t\t\t\tleap => [\n\t\t\t\t\t\t\t";

                    say $file join ",\n\t\t\t\t\t\t\t",
                        map {
                            my $month = $- // '';
                            $month =~ s/'/\\'/g;
                            $month = "'$month'";
                        } @{$calendars{months}{$type}{$context}{$width}{leap}};
                    say $file "\t\t\t\t\t\t],";
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

   my %days = (
        mon => 0,
        tue => 1,
        wed => 2,
        thu => 3,
        fri => 4,
        sat => 5,
        sun => 6,
    );

    if (keys %{$calendars{days}}) {
        print $file <<EOT;
has 'calendar-days' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{days}}) {
            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{days}{$type}} ) {
                if ($context eq 'alias') {
                    say $file "\t\t\t\t'alias' => q{$calendars{days}{$type}{alias}},";
                    next;
                }

                say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{days}{$type}{$context}}) {
                    if (exists $calendars{days}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{days}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{days}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }

                    say $file "\t\t\t\t\t$width => {";
                    print $file "\t\t\t\t\t\t";
                    my @days  = sort {$days{$a} <=> $days{$b}}
                        keys %{$calendars{days}{$type}{$context}{$width}};

                    say $file join ",\n\t\t\t\t\t\t",
                        map {
                            my $day = $calendars{days}{$type}{$context}{$width}{$-};
                            my $key = $-;
                            $day =~ s/'/\\'/;
                            $day = "'$day'";
                            "$key => $day";
                        } @days;
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{quarters}}) {
        print $file <<EOT;
has 'calendar-quarters' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $type (sort keys %{$calendars{quarters}}) {
            say $file "\t\t\t'$type' => {";
            foreach my $context ( sort keys %{$calendars{quarters}{$type}} ) {
                if ($context eq 'alias') {
                    say $file "\t\t\t\t'alias' => q{$calendars{quarters}{$type}{alias}},";
                    next;
                }

				say $file "\t\t\t\t'$context' => {";
                foreach my $width (sort keys %{$calendars{quarters}{$type}{$context}}) {
					if (exists $calendars{quarters}{$type}{$context}{$width}{alias}) {
						say $file "\t\t\t\t\t'$width' => {";
                        say $file "\t\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t\tcontext\t=> q{$calendars{quarters}{$type}{$context}{$width}{alias}{context}},";
						say $file "\t\t\t\t\t\t\ttype\t=> q{$calendars{quarters}{$type}{$context}{$width}{alias}{type}},";
						say $file "\t\t\t\t\t\t},";
						say $file "\t\t\t\t\t},";
                        next;
                    }

                    print $file "\t\t\t\t\t$width => {";
                    say $file join ",\n\t\t\t\t\t\t",
                        map {
                            my $quarter = $calendars{quarters}{$type}{$context}{$width}{$-};
                            $quarter =~ s/'/\\'/;
                            $quarter = "'$quarter'";
							"$- => $quarter";
                        } sort { $a <=> $b } keys %{$calendars{quarters}{$type}{$context}{$width}};
                    say $file "\t\t\t\t\t},";
                }
                say $file "\t\t\t\t},";
            }
            say $file "\t\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT

    }

    if (keys %{$calendars{day-period-data}}) {
        print $file <<EOT;
has 'day-period-data' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> CodeRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { sub {
\t\t# Time in hhmm format
\t\tmy (\$self, \$type, \$time, \$day-period-type) = \@-;
\t\t\$day-period-type //= 'default';
\t\tSWITCH:
\t\tfor (\$type) {
EOT
        foreach my $ctype (keys  %{$calendars{day-period-data}}) {
            say $file "\t\t\tif (\$- eq '$ctype') {";
			foreach my $day-period-type (keys  %{$calendars{day-period-data}{$ctype}}) {
				say $file "\t\t\t\tif(\$day-period-type eq '$day-period-type') {";
				foreach my $type (sort
					{
						my $return = 0;
						$return = -1 if $a eq 'noon' || $a eq 'midnight';
						$return = 1 if $b eq 'noon' || $b eq 'midnight';
						return $return;
					} keys  %{$calendars{day-period-data}{$ctype}{$day-period-type}}) {
					# Sort 'at' periods to the top of the list so they are printed first
					my %boundries = map {@$-} @{$calendars{day-period-data}{$ctype}{$day-period-type}{$type}};
					if (exists $boundries{at}) {
						my ($hm) = $boundries{at};
						$hm =~ s/://;
						$hm = $hm + 0;
						say $file "\t\t\t\t\treturn '$type' if \$time == $hm;";
						next;
					}

					my $stime = $boundries{from};
					my $etime = $boundries{before};

					foreach ($stime, $etime) {
						s/://;
						$- = $- + 0;
					}

					if ($etime < $stime) {
						# Time crosses midnight
						say $file "\t\t\t\t\treturn '$type' if \$time >= $stime;";
						say $file "\t\t\t\t\treturn '$type' if \$time < $etime;";
					}
					else {
						say $file "\t\t\t\t\treturn '$type' if \$time >= $stime";
						say $file "\t\t\t\t\t\t&& \$time < $etime;";
					}
				}
				say $file "\t\t\t\t}";
			}
			say $file "\t\t\t\tlast SWITCH;";
			say $file "\t\t\t\t}"
		}
        print $file <<EOT;
\t\t}
\t} },
);

around day-period-data => sub {
	my (\$orig, \$self) = \@-;
	return \$self->\$orig;
};

EOT
    }

    if (keys %{$calendars{day-periods}}) {
        print $file <<EOT;
has 'day-periods' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

		foreach my $ctype (sort keys %{$calendars{day-periods}}) {
            say $file "\t\t'$ctype' => {";
			if (exists $calendars{day-periods}{$ctype}{alias}) {
				say $file "\t\t\t'alias' => '$calendars{day-periods}{$ctype}{alias}',";
				say $file "\t\t},";
				next;
			}

            foreach my $type (sort keys %{$calendars{day-periods}{$ctype}}) {
				say $file "\t\t\t'$type' => {";
				if (exists $calendars{day-periods}{$ctype}{$type}{alias}) {
					say $file "\t\t\t\t'alias' => '$calendars{day-periods}{$ctype}{$type}{alias}',";
					say $file "\t\t\t},";
					next;
				}

                foreach my $width (keys %{$calendars{day-periods}{$ctype}{$type}}) {
                    say $file "\t\t\t\t'$width' => {";
					if (exists $calendars{day-periods}{$ctype}{$type}{$width}{alias}) {
						say $file "\t\t\t\t\t'alias' => {";
						say $file "\t\t\t\t\t\t'context' => '$calendars{day-periods}{$ctype}{$type}{$width}{alias}{context}',";
						say $file "\t\t\t\t\t\t'width' => '$calendars{day-periods}{$ctype}{$type}{$width}{alias}{width}',";
						say $file "\t\t\t\t\t},";
						say $file "\t\t\t\t},";
						next;
					}

                    foreach my $period (keys %{$calendars{day-periods}{$ctype}{$type}{$width}}) {
                        say $file "\t\t\t\t\t'$period' => q{$calendars{day-periods}{$ctype}{$type}{$width}{$period}},"
                    }
                    say $file "\t\t\t\t},";
                }
                say $file "\t\t\t},";
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{eras}}) {
        print $file <<EOT;
has 'eras' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{eras}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $type (sort keys %{$calendars{eras}{$ctype}}) {
				if ($type eq 'alias') {
					say $file "\t\t\t'alias' => '$calendars{eras}{$ctype}{alias}',";
					next;
				}

				say $file "\t\t\t$type => {";
                print $file "\t\t\t\t";
                print $file join ",\n\t\t\t\t", map {
                    my $name = $calendars{eras}{$ctype}{$type}{$-};
                    $name =~ s/'/\\'/;
                    "'$-' => '$name'";
                } sort { ($a =~ /^\d+$/a ? $a : 0) <=> ($b =~ /^\d+$/a ? $b : 0) } keys %{$calendars{eras}{$ctype}{$type}};
                say $file "\n\t\t\t},";
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{date-formats}}) {
        print $file <<EOT;
has 'date-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{date-formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $width (sort keys %{$calendars{date-formats}{$ctype}}) {
                say $file "\t\t\t'$width' => q{$calendars{date-formats}{$ctype}{$width}},";
            }
            say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{time-formats}}) {
        print $file <<EOT;
has 'time-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{time-formats}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $width (sort keys %{$calendars{time-formats}{$ctype}}) {
                say $file "\t\t\t'$width' => q{$calendars{time-formats}{$ctype}{$width}},";
            }
            say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{datetime-formats}}) {
        print $file <<EOT;
has 'datetime-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{datetime-formats}}) {
            say $file "\t\t'$ctype' => {";
			if (exists $calendars{datetime-formats}{$ctype}{alias}) {
			    say $file "\t\t\t'alias' => q{$calendars{datetime-formats}{$ctype}{alias}},";
			}
			else {
				foreach my $length (sort keys %{$calendars{datetime-formats}{$ctype}{formats}}) {
					say $file "\t\t\t'$length' => q{$calendars{datetime-formats}{$ctype}{formats}{$length}},";
				}
			}
			say $file "\t\t},";
        }

        print $file <<EOT;
\t} },
);

has 'datetime-formats-available-formats' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (keys %{$calendars{datetime-formats}}) {
			if (exists $calendars{datetime-formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime-formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime-formats}{$ctype}{available-formats}) {
					say $file "\t\t'$ctype' => {";
					foreach my $type (sort keys %{$calendars{datetime-formats}{$ctype}{available-formats}}) {
						say $file "\t\t\t$type => q{$calendars{datetime-formats}{$ctype}{available-formats}{$type}},";
					}
					say $file "\t\t},";
				}
            }
        }
        print $file <<EOT;
\t} },
);

has 'datetime-formats-append-item' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (keys %{$calendars{datetime-formats}}) {
			if (exists $calendars{datetime-formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime-formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime-formats}{$ctype}{appendItem}) {
					say $file "\t\t'$ctype' => {";
					foreach my $type (sort keys %{$calendars{datetime-formats}{$ctype}{appendItem}}) {
						say $file "\t\t\t'$type' => '$calendars{datetime-formats}{$ctype}{appendItem}{$type}',";
					}
					say $file "\t\t},";
				}
			}
        }
        print $file <<EOT;
\t} },
);

has 'datetime-formats-interval' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT

        foreach my $ctype (keys %{$calendars{datetime-formats}}) {
			if (exists $calendars{datetime-formats}{$ctype}{alias}) {
				say $file "\t\t'$ctype' => {";
				say $file "\t\t\t'alias' => q{$calendars{datetime-formats}{$ctype}{alias}},";
				say $file "\t\t},";
			}
			else {
				if (exists $calendars{datetime-formats}{$ctype}{interval}) {
					say $file "\t\t'$ctype' => {";
					foreach my $format-id ( sort keys %{$calendars{datetime-formats}{$ctype}{interval}}) {
						if ($format-id eq 'fallback') {
							say $file "\t\t\tfallback => '$calendars{datetime-formats}{$ctype}{interval}{fallback}',";
							next;
						}
						say $file "\t\t\t$format-id => {";
						foreach my $greatest-difference (sort keys %{$calendars{datetime-formats}{$ctype}{interval}{$format-id}}) {
							say $file "\t\t\t\t$greatest-difference => q{$calendars{datetime-formats}{$ctype}{interval}{$format-id}{$greatest-difference}},";
						}
						say $file "\t\t\t},";
					}
					say $file "\t\t},";
				}
			}
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{month-patterns}}) {
        print $file <<EOT;
has 'month-patterns' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{month-patterns}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $context (sort keys %{$calendars{month-patterns}{$ctype}}) {
				if ($context eq 'alias' ) {
					say $file "\t\t\talias => '$calendars{month-patterns}{$ctype}{alias}'",
				}
				else {
					say $file "\t\t\t'$context' => {";
					foreach my $width (sort keys %{$calendars{month-patterns}{$ctype}{$context}}) {
						say $file "\t\t\t\t'$width' => {";
						foreach my $type ( sort keys %{$calendars{month-patterns}{$ctype}{$context}{$width}}) {
							# Check for aliases
							if ($type eq 'alias') {
								say $file <<EOT;
					alias => {
						context => '$calendars{month-patterns}{$ctype}{$context}{$width}{alias}{context}',
						width	=> '$calendars{month-patterns}{$ctype}{$context}{$width}{alias}{width}',
					},
EOT
							}
							else {
								say $file "\t\t\t\t\t'$type' => q{$calendars{month-patterns}{$ctype}{$context}{$width}{$type}},";
							}
						}
						say $file "\t\t\t\t},";
					}
					say $file "\t\t\t},";
				}
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }

    if (keys %{$calendars{cyclic-name-sets}}) {
        print $file <<EOT;
has 'cyclic-name-sets' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t\t=> sub { {
EOT
        foreach my $ctype (sort keys %{$calendars{cyclic-name-sets}}) {
            say $file "\t\t'$ctype' => {";
            foreach my $context (sort keys %{$calendars{cyclic-name-sets}{$ctype}}) {
				if ($context eq 'alias' ) {
					say $file "\t\t\talias => '$calendars{cyclic-name-sets}{$ctype}{alias}',",
				}
				else {
					say $file "\t\t\t'$context' => {";
					foreach my $width (sort keys %{$calendars{cyclic-name-sets}{$ctype}{$context}}) {
						if ($width eq 'alias') {
							say $file "\t\t\t\talias => q($calendars{cyclic-name-sets}{$ctype}{$context}{alias}),"
						}
						else {
							say $file "\t\t\t\t'$width' => {";
								foreach my $type ( sort keys %{$calendars{cyclic-name-sets}{$ctype}{$context}{$width}}) {
								say $file "\t\t\t\t\t'$type' => {";
								foreach my $id (sort { ($a =~ /^\d+$/a ? $a : 0) <=> ($b =~ /^\d+$/a ? $b : 0) } keys %{$calendars{cyclic-name-sets}{$ctype}{$context}{$width}{$type}} ) {
									if ($id eq 'alias') {
										print $file <<EOT;
\t\t\t\t\t\talias => {
\t\t\t\t\t\t\tcontext\t=> q{$calendars{cyclic-name-sets}{$ctype}{$context}{$width}{$type}{alias}{context}},
\t\t\t\t\t\t\tname-set\t=> q{$calendars{cyclic-name-sets}{$ctype}{$context}{$width}{$type}{alias}{name-set}},
\t\t\t\t\t\t\ttype\t=> q{$calendars{cyclic-name-sets}{$ctype}{$context}{$width}{$type}{alias}{type}},
\t\t\t\t\t\t},
EOT
									}
									else {
										say $file "\t\t\t\t\t\t$id => q($calendars{cyclic-name-sets}{$ctype}{$context}{$width}{$type}{$id}),";
									}
								}
								say $file "\t\t\t\t\t},";
							}
							say $file "\t\t\t\t},";
						}
					}
					say $file "\t\t\t},";
				}
            }
            say $file "\t\t},";
        }
        print $file <<EOT;
\t} },
);

EOT
    }
}

#/ldml/dates/calendars/calendar/months/
sub process-months {
    my ($xpath, $type) = @-;

    say "Processing Months ($type)" if $verbose;

    my (%months);
    my $months-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/alias));
    if ($months-alias->size) {
        my $path = ($months-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$months{alias} = $alias;
    }
    else {
        my $months-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext));

        return 0 unless $months-nodes->size;

        foreach my $context-node ($months-nodes->get-nodelist) {
            my $context-type = $context-node->getAttribute('type');

            my $width = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context-type"]/monthWidth));

            foreach my $width-node ($width->get-nodelist) {
                my $width-type = $width-node->getAttribute('type');

				my $width-alias-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context-type"]/monthWidth[\@type="$width-type"]/alias)
				);

				if ($width-alias-nodes->size) {
                    my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
                    my ($new-width-context) = $path =~ /monthContext\[\@type='([^']+)'\]/;
                    $new-width-context //= $context-type;
                    my ($new-width-type) = $path =~ /monthWidth\[\@type='([^']+)'\]/;
					$months{$context-type}{$width-type}{alias} = {
						context	=> $new-width-context,
						type	=> $new-width-type,
					};
					next;
                }
                my $month-nodes = findnodes($xpath,
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/months/monthContext[\@type="$context-type"]/monthWidth[\@type="$width-type"]/month));
                foreach my $month ($month-nodes->get-nodelist) {
                    my $month-type = $month->getAttribute('type') -1;
                    my $year-type = $month->getAttribute('yeartype') || 'nonleap';
                    $months{$context-type}{$width-type}{$year-type}[$month-type] =
                        $month->getChildNode(1)->getValue();
                }
            }
        }
    }
    return \%months;
}

#/ldml/dates/calendars/calendar/days/
sub process-days {
    my ($xpath, $type) = @-;

    say "Processing Days ($type)" if $verbose;

    my (%days);
    my $days-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/alias));
    if ($days-alias->size) {
        my $path = ($days-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$days{alias} = $alias;
    }
	else {
		my $days-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext));
		return 0 unless $days-nodes->size;

		foreach my $context-node ($days-nodes->get-nodelist) {
			my $context-type = $context-node->getAttribute('type');

			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context-type"]/dayWidth));

			foreach my $width-node ($width->get-nodelist) {
				my $width-type = $width-node->getAttribute('type');

				my $width-alias-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context-type"]/dayWidth[\@type="$width-type"]/alias)
				);

				if ($width-alias-nodes->size) {
                    my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
                    my ($new-width-context) = $path =~ /dayContext\[\@type='([^']+)'\]/;
                    $new-width-context //= $context-type;
                    my ($new-width-type) = $path =~ /dayWidth\[\@type='([^']+)'\]/;
					$days{$context-type}{$width-type}{alias} = {
						context	=> $new-width-context,
						type	=> $new-width-type,
					};
					next;
                }

                my $day-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/days/dayContext[\@type="$context-type"]/dayWidth[\@type="$width-type"]/day));

				foreach my $day ($day-nodes->get-nodelist) {
					my $day-type = $day->getAttribute('type');
					$days{$context-type}{$width-type}{$day-type} =
						$day->getChildNode(1)->getValue();
				}
            }
		}
    }
    return \%days;
}

#/ldml/dates/calendars/calendar/quarters/
sub process-quarters {
    my ($xpath, $type) = @-;

    say "Processing Quarters ($type)" if $verbose;

    my %quarters;
    my $quarters-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/alias));
    if ($quarters-alias->size) {
        my $path = ($quarters-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$quarters{alias} = $alias;
    }
	else {
		my $quarters-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext));
		return 0 unless $quarters-nodes->size;

		foreach my $context-node ($quarters-nodes->get-nodelist) {
			my $context-type = $context-node->getAttribute('type');

			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context-type"]/quarterWidth));

			foreach my $width-node ($width->get-nodelist) {
				my $width-type = $width-node->getAttribute('type');

				my $width-alias-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context-type"]/quarterWidth[\@type="$width-type"]/alias)
				);

				if ($width-alias-nodes->size) {
                    my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
                    my ($new-width-context) = $path =~ /quarterContext\[\@type='([^']+)'\]/;
                    $new-width-context //= $context-type;
                    my ($new-width-type) = $path =~ /quarterWidth\[\@type='([^']+)'\]/;
					$quarters{$context-type}{$width-type}{alias} = {
						context	=> $new-width-context,
						type	=> $new-width-type,
					};
					next;
                }

				my $quarter-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/quarters/quarterContext[\@type="$context-type"]/quarterWidth[\@type="$width-type"]/quarter));

				foreach my $quarter ($quarter-nodes->get-nodelist) {
					my $quarter-type = $quarter->getAttribute('type') -1;
					$quarters{$context-type}{$width-type}{$quarter-type} =
						$quarter->getChildNode(1)->getValue();
				}
			}
		}
	}

	return \%quarters;
}

sub process-day-period-data {
    my $locale = shift;

	use feature 'state';
	state %day-period-data;

    unless (keys %day-period-data) {

	# The supplemental/dayPeriods.xml file contains a list of all valid
	# day periods
        my $xml = XML::XPath->new(
			parser => XML::Parser->new(
				NoLWP => 1,
				ErrorContext => 2,
				ParseParamEnt => 1,
			),
            filename => File::Spec->catfile(
				$base-directory,
				'supplemental',
				'dayPeriods.xml',
			)
        );

		my $dayPeriodRuleSets = findnodes($xml,
            q(/supplementalData/dayPeriodRuleSet)
        );

		foreach my $dayPeriodRuleSet ($dayPeriodRuleSets->get-nodelist) {
			my $day-period-type = $dayPeriodRuleSet->getAttribute('type');

			my $dayPeriodRules = findnodes($xml,
				$day-period-type
				? qq(/supplementalData/dayPeriodRuleSet[\@type="$day-period-type"]/dayPeriodRules)
				: qq(/supplementalData/dayPeriodRuleSet[not(\@type)]/dayPeriodRules)
			);

			foreach my $day-period-rule ($dayPeriodRules->get-nodelist) {
				my $locales = $day-period-rule->getAttribute('locales');
				my %data;
				my $day-periods = findnodes($xml,
					$day-period-type
					? qq(/supplementalData/dayPeriodRuleSet[\@type="$day-period-type"]/dayPeriodRules[\@locales="$locales"]/dayPeriodRule)
					: qq(/supplementalData/dayPeriodRuleSet[not(\@type)]/dayPeriodRules[\@locales="$locales"]/dayPeriodRule)
				);

				foreach my $day-period ($day-periods->get-nodelist) {
					my $type;
					my @data;
					foreach my $attribute-node ($day-period->getAttributes) {
						if ($attribute-node->getLocalName() eq 'type') {
							$type = $attribute-node->getData;
						}
						else {
							push @data, [
								$attribute-node->getLocalName,
								$attribute-node->getData
							]
						}
					}
					$data{$type} = \@data;
				}
				my @locales = split / /, $locales;
				foreach my $locale (@locales) {
					$day-period-data{$locale}{$day-period-type // 'default'} = \%data;
				}
			}
		}
	}

    return $day-period-data{$locale};
}

#/ldml/dates/calendars/calendar/dayPeriods/
sub process-day-periods {
    my ($xpath, $type) = @-;

    say "Processing Day Periods ($type)" if $verbose;

    my %dayPeriods;
    my $dayPeriods-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/alias));
    if ($dayPeriods-alias->size) {
        my $path = ($dayPeriods-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dayPeriods{alias} = $alias;
    }
	else {
		my $dayPeriods-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext));
		return 0 unless $dayPeriods-nodes->size;

		foreach my $context-node ($dayPeriods-nodes->get-nodelist) {
			my $context-type = $context-node->getAttribute('type');

			my $context-alias-nodes = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context-type"]/alias)
			);

			if ($context-alias-nodes->size) {
                my $path = ($context-alias-nodes->get-nodelist)[0]->getAttribute('path');
                my ($new-context) = $path =~ /dayPeriodContext\[\@type='([^']+)'\]/;
                $dayPeriods{$context-type}{alias} = $new-context;
				next;
            }

			my $width = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context-type"]/dayPeriodWidth)
			);

			foreach my $width-node ($width->get-nodelist) {
				my $width-type = $width-node->getAttribute('type');

				my $width-alias-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context-type"]/dayPeriodWidth[\@type="$width-type"]/alias)
				);

				if ($width-alias-nodes->size) {
                    my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
                    my ($new-width-type) = $path =~ /dayPeriodWidth\[\@type='([^']+)'\]/;
					my ($new-context-type) = $path =~ /dayPeriodContext\[\@type='([^']+)'\]/;
					$dayPeriods{$context-type}{$width-type}{alias}{width} = $new-width-type;
					$dayPeriods{$context-type}{$width-type}{alias}{context} = $new-context-type || $context-type;
					next;
                }

				my $dayPeriod-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/dayPeriods/dayPeriodContext[\@type="$context-type"]/dayPeriodWidth[\@type="$width-type"]/dayPeriod)
				);

				foreach my $dayPeriod ($dayPeriod-nodes->get-nodelist) {
					my $dayPeriod-type = $dayPeriod->getAttribute('type');
					$dayPeriods{$context-type}{$width-type}{$dayPeriod-type} =
						$dayPeriod->getChildNode(1)->getValue();
				}
			}
		}
    }

	return \%dayPeriods;
}

#/ldml/dates/calendars/calendar/eras/
sub process-eras {
    my ($xpath, $type) = @-;

    say "Processing Eras ($type)" if $verbose;

    my %eras;
	my %alias-size = (
		eraNames 	=> 'wide',
		eraAbbr		=> 'abbreviated',
		eraNarrow	=> 'narrow',
	);

    my $eras-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/alias));
	if ($eras-alias->size) {
        my $path = ($eras-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$eras{alias} = $alias;
    }
	else {
		my $eras-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras));
		return {} unless $eras-nodes->size;

		my $eraNames-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/alias));
		if ($eraNames-alias->size) {
			my $path = ($eraNames-alias->get-nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{wide}{alias} = $alias-size{$alias};
		}
		else {
			my $eraNames = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNames/era[not(\@alt)]));
			if ($eraNames->size) {
				foreach my $eraName ($eraNames->get-nodelist) {
					my $era-type = $eraName->getAttribute('type');
					$eras{wide}{$era-type} = $eraName->getChildNode(1)->getValue();
				}
			}
        }

		my $eraAbbrs-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/alias));
		if ($eraAbbrs-alias->size) {
			my $path = ($eraAbbrs-alias->get-nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{abbreviated}{alias} = $alias-size{$alias};
		}
		else {
			my $eraAbbrs = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraAbbr/era[not(\@alt)]));
			if ($eraAbbrs->size) {
				foreach my $eraAbbr ($eraAbbrs->get-nodelist) {
					my $era-type = $eraAbbr->getAttribute('type');
					$eras{abbreviated}{$era-type} = $eraAbbr->getChildNode(1)->getValue();
				}
			}
		}

		my $eraNarrow-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/alias));
		if ($eraNarrow-alias->size) {
			my $path = ($eraNarrow-alias->get-nodelist)[0]->getAttribute('path');
			my ($alias) = $path=~/\.\.\/(.*)/;
			$eras{narrow}{alias} = $alias-size{$alias};
		}
		else {
			my $eraNarrows = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/eras/eraNarrow/era[not(\@alt)]));
			if ($eraNarrows->size) {
				foreach my $eraNarrow ($eraNarrows->get-nodelist) {
					my $era-type = $eraNarrow->getAttribute('type');
					$eras{narrow}{$era-type} = $eraNarrow->getChildNode(1)->getValue();
				}
			}
		}
    }

    return \%eras;
}

#/ldml/dates/calendars/calendar/dateFormats/
sub process-date-formats {
    my ($xpath, $type) = @-;

    say "Processing Date Formats ($type)" if $verbose;

    my %dateFormats;
	my $dateFormats-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/alias));
	if ($dateFormats-alias->size) {
		my $path = ($dateFormats-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dateFormats{alias} = $alias;
    }
	else {
		my $dateFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats));

		return {} unless $dateFormats->size;

		my $dateFormatLength-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength)
        );

		foreach my $dateFormatLength ($dateFormatLength-nodes->get-nodelist) {
			my $date-format-width = $dateFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateFormats/dateFormatLength[\@type="$date-format-width"]/dateFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$dateFormats{$date-format-width} = $pattern;
		}
    }

	return \%dateFormats;
}

#/ldml/dates/calendars/calendar/timeFormats/
sub process-time-formats {
    my ($xpath, $type) = @-;

    say "Processing Time Formats ($type)" if $verbose;

    my %timeFormats;
	my $timeFormats-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/alias));
	if ($timeFormats-alias->size) {
		my $path = ($timeFormats-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$timeFormats{alias} = $alias;
    }
	else {
		my $timeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats));

		return {} unless $timeFormats->size;

		my $timeFormatLength-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength)
        );

		foreach my $timeFormatLength ($timeFormatLength-nodes->get-nodelist) {
			my $time-format-width = $timeFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/timeFormats/timeFormatLength[\@type="$time-format-width"]/timeFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$timeFormats{$time-format-width} = $pattern;
		}
    }

	return \%timeFormats;
}

#/ldml/dates/calendars/calendar/dateTimeFormats/
sub process-datetime-formats {
    my ($xpath, $type) = @-;

    say "Processing Date Time Formats ($type)" if $verbose;

    my %dateTimeFormats;
    my $dateTimeFormats-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/alias));

    if ($dateTimeFormats-alias->size) {
		my $path = ($dateTimeFormats-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$dateTimeFormats{alias} = $alias;
    }
	else {
		my $dateTimeFormats = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats));

		return {} unless $dateTimeFormats->size;

		my $dateTimeFormatLength-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/dateTimeFormatLength)
        );

		foreach my $dateTimeFormatLength ($dateTimeFormatLength-nodes->get-nodelist) {
			my $dateTime-format-type = $dateTimeFormatLength->getAttribute('type');

			my $patterns = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/dateTimeFormatLength[\@type="$dateTime-format-type"]/dateTimeFormat/pattern)
			);

			my $pattern = $patterns->[0]->getChildNode(1)->getValue;
			$dateTimeFormats{formats}{$dateTime-format-type} = $pattern;
		}

		# Available Formats
		my $availableFormats-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/availableFormats/dateFormatItem)
		);

		foreach my $dateFormatItem ($availableFormats-nodes->get-nodelist) {
			my $id = $dateFormatItem->getAttribute('id');

			my $pattern = $dateFormatItem->getChildNode(1)->getValue;
			$dateTimeFormats{available-formats}{$id} = $pattern;
		}

		# Append items
		my $appendItems-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/appendItems/appendItem)
        );

		foreach my $appendItem ($appendItems-nodes->get-nodelist) {
			my $request = $appendItem->getAttribute('request');

			my $pattern = $appendItem->getChildNode(1)->getValue;
			$dateTimeFormats{appendItem}{$request} = $pattern;
		}

		# Interval formats
		my $intervalFormats-nodes = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatItem)
        );

		my $fallback-node = findnodes($xpath,
			qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatFallback)
        );

		if ($fallback-node->size) {
			$dateTimeFormats{interval}{fallback} = ($fallback-node->get-nodelist)[0]->getChildNode(1)->getValue;
		}

		foreach my $intervalFormatItem ($intervalFormats-nodes->get-nodelist) {
			my $id = $intervalFormatItem->getAttribute('id');

			my $greatestDifference-nodes = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/dateTimeFormats/intervalFormats/intervalFormatItem[\@id="$id"]/greatestDifference)
            );

            foreach my $greatestDifference ($greatestDifference-nodes->get-nodelist) {
                my $pattern = $greatestDifference->getChildNode(1)->getValue;
                my $gd-id = $greatestDifference->getAttribute('id');
                $dateTimeFormats{interval}{$id}{$gd-id} = $pattern;
            }
		}
    }

    return \%dateTimeFormats;
}

#/ldml/dates/calendars/calendar/monthPatterns/
sub process-month-patterns {
    my ($xpath, $type) = @-;

    say "Processing Month Patterns ($type)" if $verbose;
    my (%month-patterns);
    my $month-patterns-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/alias));
    if ($month-patterns-alias->size) {
        my $path = ($month-patterns-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$month-patterns{alias} = $alias;
    }
    else {
        my $month-patterns-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext));

        return 0 unless $month-patterns-nodes->size;

        foreach my $context-node ($month-patterns-nodes->get-nodelist) {
            my $context-type = $context-node->getAttribute('type');

            my $width = findnodes($xpath,
                qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context-type"]/monthPatternWidth));

            foreach my $width-node ($width->get-nodelist) {
                my $width-type = $width-node->getAttribute('type');

				my $width-alias-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context-type"]/monthPatternWidth[\@type="$width-type"]/alias)
				);

				if ($width-alias-nodes->size) {
                    my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
                    my ($new-width-context) = $path =~ /monthPatternContext\[\@type='([^']+)'\]/;
                    $new-width-context //= $context-type;
                    my ($new-width-type) = $path =~ /monthPatternWidth\[\@type='([^']+)'\]/;
					$month-patterns{$context-type}{$width-type}{alias} = {
						context	=> $new-width-context,
						width	=> $new-width-type,
					};
					next;
                }
                my $month-pattern-nodes = findnodes($xpath,
                    qq(/ldml/dates/calendars/calendar[\@type="$type"]/monthPatterns/monthPatternContext[\@type="$context-type"]/monthPatternWidth[\@type="$width-type"]/monthPattern));
                foreach my $month-pattern ($month-pattern-nodes->get-nodelist) {
                    my $month-pattern-type = $month-pattern->getAttribute('type');
                    $month-patterns{$context-type}{$width-type}{$month-pattern-type} =
                        $month-pattern->getChildNode(1)->getValue();
                }
            }
        }
    }
    return \%month-patterns;
}

#/ldml/dates/calendars/calendar/cyclicNameSets/
sub process-cyclic-name-sets {
    my ($xpath, $type) = @-;

	say "Processing Cyclic Name Sets ($type)" if $verbose;

	my (%cyclic-name-sets);
    my $cyclic-name-sets-alias = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/alias));
    if ($cyclic-name-sets-alias->size) {
        my $path = ($cyclic-name-sets-alias->get-nodelist)[0]->getAttribute('path');
        my ($alias) = $path=~/\[\@type='(.*?)']/;
		$cyclic-name-sets{alias} = $alias;
    }
    else {
        my $cyclic-name-sets-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet));

        return 0 unless $cyclic-name-sets-nodes->size;

		foreach my $name-set-node ($cyclic-name-sets-nodes->get-nodelist) {
			my $name-set-type = $name-set-node->getAttribute('type');
			my $cyclic-name-set-alias = findnodes($xpath,
				qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name-set-type"]/alias)
			);

			if ($cyclic-name-set-alias->size) {
				my $path = ($cyclic-name-set-alias->get-nodelist)[0]->getAttribute('path');
				my ($alias) = $path=~/\[\@type='(.*?)']/;
				$cyclic-name-sets{$name-set-type}{alias} = $alias;
				next;
			}
			else {
				my $context-nodes = findnodes($xpath,
					qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name-set-type"]/cyclicNameContext)
				);

				foreach my $context-node ($context-nodes->get-nodelist) {
					my $context-type = $context-node->getAttribute('type');

					my $width = findnodes($xpath,
						qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name-set-type"]/cyclicNameContext[\@type="$context-type"]/cyclicNameWidth));

					foreach my $width-node ($width->get-nodelist) {
						my $width-type = $width-node->getAttribute('type');

						my $width-alias-nodes = findnodes($xpath,
							qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name-set-type"]/cyclicNameContext[\@type="$context-type"]/cyclicNameWidth[\@type="$width-type"]/alias)
						);

						if ($width-alias-nodes->size) {
							my $path = ($width-alias-nodes->get-nodelist)[0]->getAttribute('path');
							my ($new-width-type) = $path =~ /cyclicNameWidth\[\@type='([^']+)'\]/;
							my ($new-context-type) = $path =~ /cyclicNameContext\[\@type='([^']+)'\]/;
							my ($new-name-type) = $path =~ /cyclicNameSet\[\@type='([^']+)'\]/;
							$cyclic-name-sets{$name-set-type}{$context-type}{$width-type}{alias} = {
								name-set => ($new-name-type // $name-set-type),
								context => ($new-context-type // $context-type),
								type	=> $new-width-type,
							};
							next;
						}

						my $cyclic-name-set-nodes = findnodes($xpath,
							qq(/ldml/dates/calendars/calendar[\@type="$type"]/cyclicNameSets/cyclicNameSet[\@type="$name-set-type"]/cyclicNameContext[\@type="$context-type"]/cyclicNameWidth[\@type="$width-type"]/cyclicName));
						foreach my $cyclic-name-set ($cyclic-name-set-nodes->get-nodelist) {
							my $cyclic-name-set-type = $cyclic-name-set->getAttribute('type') -1;
							$cyclic-name-sets{$name-set-type}{$context-type}{$width-type}{$cyclic-name-set-type} =
								$cyclic-name-set->getChildNode(1)->getValue();
						}
					}
				}
			}
		}
	}
    return \%cyclic-name-sets;
}

#/ldml/dates/calendars/calendar/fields/field
sub process-fields {
    my ($xpath, $type) = @-;

    say "Processing Fields ($type)" if $verbose;

    my %fields;
    my $fields-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field));

    return 0 unless $fields-nodes->size;

    foreach my $field ($fields-nodes->get-nodelist) {
        my $ftype = $field->getAttribute('type');
        my $displayName-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field[\@type="$ftype"]/displayName));

        if ($displayName-nodes->size) {
            my $text-node = ($displayName-nodes->get-nodelist)[0]->getChildNode(1);
            $fields{$ftype}{name} = $text-node->getValue
                if $text-node;
        }

        my $relative-nodes = findnodes($xpath, qq(/ldml/dates/calendars/calendar[\@type="$type"]/fields/field[\@type="$ftype"]/relative));
        next unless $relative-nodes->size;

        foreach my $relative ($relative-nodes->get-nodelist) {
            my $rtype = $relative->getAttribute('type');
            $fields{$ftype}{relative}{$rtype} = $relative->getChildNode(1)->getValue;
        }
    }

    return \%fields;
}

#/ldml/dates/timeZoneNames/
sub process-time-zone-names {
    my ($file, $xpath) = @-;

    say "Processing Time Zone Names"
		if $verbose;

    my $time-zone-names = findnodes($xpath,
        q(/ldml/dates/timeZoneNames/*));

    return unless $time-zone-names->size;

    print $file <<EOT;
has 'time-zone-names' => (
\tis\t\t\t=> 'ro',
\tisa\t\t\t=> HashRef,
\tinit-arg\t=> undef,
\tdefault\t=> sub { {
EOT
    my (%zone, %metazone);
    foreach my $node($time-zone-names->get-nodelist) {
        SWITCH:
        foreach ($node->getLocalName) {
            if (/^(?:
                hourFormat
                |gmtFormat
                |gmtZeroFormat
                |regionFormat
                |fallbackFormat
                |fallbackRegionFormat
            )$/x) {
                my $value = $node->string-value;
                say $file "\t\t$- => q($value),";
                last SWITCH;
            }
            if ($- eq 'singleCountries') {
                my $value = $node->getAttribute('list');
                my @value = split / /, $value;
                say $file "\t\tsingleCountries => [ ",
                    join (', ',
                    map {"q($-)"}
                    @value),
                    ' ]';
                last SWITCH;
            }
            if (/(?:meta)*zone/) {
                my $name = $node->getAttribute('type');
                $zone{$name} //= {};
                my $length-nodes = findnodes($xpath,
                    qq(/ldml/dates/timeZoneNames/$-) . qq([\@type="$name"]/*));
                foreach my $length-node ($length-nodes->get-nodelist) {
                    my $length = $length-node->getLocalName;
                    if ($length eq 'exemplarCity') {
                        $zone{$name}{exemplarCity} = $length-node->string-value;
                        next;
                    }

                    $zone{$name}{$length} //= {};
                    my $tz-type-nodes = findnodes(
						$xpath,
                        qq(/ldml/dates/timeZoneNames/$-) . qq([\@type="$name"]/$length/*)
					);

                    foreach my $tz-type-node ($tz-type-nodes->get-nodelist) {
                        my $type = $tz-type-node->getLocalName;
                        my $value = $tz-type-node->string-value;
                        $zone{$name}{$length}{$type} = $value;
                    }
                }
                last SWITCH;
            }
        }
    }

    foreach my $name (sort keys %zone) {
        say $file "\t\t'$name' => {";
        foreach my $length (sort keys %{$zone{$name}}) {
            if ($length eq 'exemplarCity') {
                say $file "\t\t\texemplarCity => q#$zone{$name}{exemplarCity}#,";
                next;
            }
            say $file "\t\t\t$length => {";
            foreach my $type (sort keys %{$zone{$name}{$length}}) {
                say $file "\t\t\t\t'$type' => q#$zone{$name}{$length}{$type}#,";
            }
            say $file "\t\t\t},";
        }
        say $file "\t\t},";
    }

    say $file "\t } }";
    say $file ");";
}

sub process-plurals {
	my ($file, $cardanal-xml, $ordinal-xml) = @-;

	my %plurals;
	foreach my $xml ($cardanal-xml, $ordinal-xml) {
		my $plurals = findnodes($xml,
			q(/supplementalData/plurals));

		foreach my $plural ($plurals->get-nodelist) {
			my $type = $plural->getAttribute('type');
			my $pluralRules = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules));
			foreach my $pluralRules-node ($pluralRules->get-nodelist) {
				my $regions = $pluralRules-node->getAttribute('locales');
				my @regions = split /\s+/, $regions;
				my $pluralRule-nodes = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules[\@locales="$regions"]/pluralRule));
				foreach my $pluralRule ($pluralRule-nodes->get-nodelist) {
					my $count = $pluralRule->getAttribute('count');
					next if $count eq 'other';
					my $rule = findnodes($xml, qq(/supplementalData/plurals[\@type='$type']/pluralRules[\@locales="$regions"]/pluralRule[\@count="$count"]/text()));
					foreach my $region (@regions) {
						$plurals{$type}{$region}{$count} = $rule;
					}
				}
			}
		}
	}

	say  $file "my %-plurals = (";

	foreach my $type (sort keys %plurals) {
		say $file "\t$type => {";
		foreach my $region (sort keys %{$plurals{$type}}) {
			say $file "\t\t$region => {";
			foreach my $count ( sort keys %{$plurals{$type}{$region}} ) {
				say $file "\t\t\t$count => sub {";
				print $file <<'EOT';

				my $number = shift;
				my $n = abs($number);
				my $i = int($n);
				my ($f) = $number =~ /\.(.*)$/;
				$f //= '';
				my $t = length $f ? $f + 0 : '';
				my $v = length $f;
				my $w = length $t;
				$t ||= 0;

EOT
				say $file "\t\t\t\t", get-format-rule( $plurals{$type}{$region}{$count});
				say $file "\t\t\t},";
			}
			say $file "\t\t},";
		}
		say $file "\t},";
	}
	print $file <<'EOT';
);

sub plural {
	my ($self, $number, $type) = @-;
	$type //= 'cardinal';
	my $language-id = $self->language-id || $self->likely-subtag->language-id;

	foreach my $count (qw( zero one two few many )) {
		next unless exists $-plurals{$type}{$language-id}{$count};
		return $count if $-plurals{$type}{$language-id}{$count}->($number);
	}
	return 'other';
}

EOT
}

sub process-plural-ranges {
	my ($file, $xml) = @-;

	my %range;
	my $plurals = findnodes($xml,
		q(/supplementalData/plurals/pluralRanges)
	);

	foreach my $plural-node ($plurals->get-nodelist) {
		my $locales = $plural-node->getAttribute('locales');
		my @locales = split /\s+/, $locales;
		my $range-nodes = findnodes($xml,
			qq(/supplementalData/plurals/pluralRanges[\@locales='$locales']/pluralRange)
		);

		foreach my $range-node ($range-nodes->get-nodelist) {
			my ($start, $end, $result) = ($range-node->getAttribute('start'), $range-node->getAttribute('end'), $range-node->getAttribute('result'));
			foreach my $locale (@locales) {
				$range{$locale}{$start}{$end} = $result;
			}
		}
	}

	say $file "my %-plural-ranges = (";
	foreach my $locale (sort keys %range) {
		say $file "\t$locale => {";
		foreach my $start (sort keys %{$range{$locale}}) {
			say $file "\t\t$start => {";
			foreach my $end (sort keys %{$range{$locale}{$start}}) {
				say $file "\t\t\t$end => '$range{$locale}{$start}{$end}',";
			}
			say $file "\t\t},";
		}
		say $file "\t},";
	}
	say $file <<'EOT';
);

sub plural-range {
	my ($self, $start, $end) = @-;
	my $language-id = $self->language-id || $self->likely-subtag->language-id;

	$start = $self->plural($start) if $start =~ /^-?(?:[0-9]+\.)?[0-9]+$/;
	$end   = $self->plural($end)   if $end   =~ /^-?(?:[0-9]+\.)?[0-9]+$/;

	return $-plural-ranges{$language-id}{$start}{$end} // 'other';
}

EOT
}

sub get-format-rule {
	my $rule = shift;

	$rule =~ s/\@.*$//;

	return 1 unless $rule =~ /\S/;

	# Basic substitutions
	$rule =~ s/\b([niftvw])\b/\$$1/g;

	my $digit = qr/[0123456789]/;
	my $value = qr/$digit+/;
	my $decimal-value = qr/$value(?:\.$value)?/;
	my $range = qr/$decimal-value\.\.$decimal-value/;
	my $range-list = qr/(\$.*?)\s(!?)=\s((?:$range|$decimal-value)(?:,(?:$range|$decimal-value))*)/;

	$rule =~ s/$range-list/$2 scalar (grep {$1 == \$-} ($3))/g;
	#$rule =~ s/\s=/ ==/g;

	$rule =~ s/\band\b/&&/g;
	$rule =~ s/\bor\b/||/g;

	return "return $rule;";
}

sub process-footer {
    my $file = shift;
    my $isRole = shift;
    $isRole = $isRole ? '::Role' : '';

    say "Processing Footer"
        if $verbose;

    say $file "no Moo$isRole;";
    say $file '';
    say $file '1;';
    say $file '';
    say $file '# vim: tabstop=4';
}

# Segmentation
sub process-segments {
    my ($file, $xpath) = @-;
    say "Processing Segments" if $verbose;

    foreach my $type (qw( GraphemeClusterBreak WordBreak SentenceBreak LineBreak )) {
        my $variables = findnodes($xpath, qq(/ldml/segmentations/segmentation[\@type="$type"]/variables/variable));
        next unless $variables->size;

        print $file <<EOT;
has '${type}-variables' => (
\tis => 'ro',
\tisa => ArrayRef,
\tinit-arg => undef,
\tdefault => sub {[
EOT
        foreach my $variable ($variables->get-nodelist) {
            # Check for deleting variables
            my $value = $variable->getChildNode(1);
            if (defined $value) {
				$value = "'" . $value->getValue . "'";

				# Fix \U escapes
				$value =~ s/ \\ u ( \p{ASCII-Hex-Digit}{4} ) /chr hex $1/egx;
				$value =~ s/ \\ U ( \p{ASCII-Hex-Digit}{8} ) /chr hex $1/egx;
            }
            else {
                $value = 'undef()';
            }

            say $file "\t\t'", $variable->getAttribute('id'), "' => ", $value, ",";
        }

        say $file "\t]}\n);";

        my $rules = findnodes($xpath, qq(/ldml/segmentations/segmentation[\@type="$type"]/segmentRules/rule));
        next unless $rules->size;

        print $file <<EOT;

has '${type}-rules' => (
\tis => 'ro',
\tisa => HashRef,
\tinit-arg => undef,
\tdefault => sub { {
EOT
        foreach my $rule ($rules->get-nodelist) {
            # Check for deleting rules
            my $value = $rule->getChildNode(1);
            if (defined $value) {
                $value = "'" . $value->getValue . "'";
            }
            else {
                $value = 'undef()';
            }
            say $file "\t\t'", $rule->getAttribute('id'), "' => ", $value, ",";
        }

        say $file "\t}}\n);";
    }
}

sub process-transforms {
    my ($dir, $xpath, $xml-file-name) = @-;

    my $transform-nodes = findnodes($xpath, q(/supplementalData/transforms/transform));
    foreach my $transform-node ($transform-nodes->get-nodelist) {
        my $variant   = ucfirst lc ($transform-node->getAttribute('variant') || 'Any');
        my $source    = ucfirst lc ($transform-node->getAttribute('source')  || 'Any');
        my $target    = ucfirst lc ($transform-node->getAttribute('target')  || 'Any');
        my $direction = $transform-node->getAttribute('direction') || 'both';

        my @directions = $direction eq 'both'
           ? qw(forward backward)
            : $direction;

        foreach my $direction (@directions) {
            if ($direction eq 'backward') {
                ($source, $target) = ($target, $source);
            }

            my $package = "Locale::CLDR::Transformations::${variant}::${source}::$target";
			push @transformation-list, $package;
            my $dir-name = File::Spec->catdir($dir, $variant, $source);

            make-path($dir-name) unless -d $dir-name;

            open my $file, '>', File::Spec->catfile($dir-name, "$target.pm");
            process-header($file, $package, $CLDR-VERSION, $xpath, $xml-file-name);
            process-transform-data(
				$file,
				$xpath,
				(
					$direction eq 'forward'
						? "\x{2192}"
						: "\x{2190}"
				)
			);

            process-footer($file);
            close $file;
        }
    }
}

sub process-transform-data {
    my ($file, $xpath, $direction) = @-;

    my $nodes = findnodes($xpath, q(/supplementalData/transforms/transform/*));
	my @nodes = $nodes->get-nodelist;

    my @transforms;
    my %vars;
    foreach my $node (@nodes) {
        next if $node->getLocalName() eq 'comment';
		next unless $node->getChildNode(1);
        my $rules = $node->getChildNode(1)->getValue;

		# Split into lines
		my @rules = split /\n/, $rules;
		foreach my $rule (@rules) {
			next if $rule =~ /^\s*#/; # Skip comments
			next if $rule =~ /^\s*$/; # Skip empty lines

			my @terms = grep { defined && /\S/ } parse-line(qr/\s+|[{};\x{2190}\x{2192}\x{2194}=\[\]]/, 'delimiters', $rule);

			# Escape transformation meta characters inside a set
			my $brackets = 0;
			my $count = 0;
			foreach my $term (@terms) {
				$count++;
				$brackets++ if $term eq '[';
				$brackets-- if $term eq ']';
				if ($brackets && $term =~ /[{};]/) {
					$term = "\\$term";
				}
				last if ! $brackets && $term =~ /;\s*(?:#.*)?$/;
			}
			@terms = @terms[ 0 .. $count - 2 ];


			# Check for conversion rules
			$terms[0] //= '';
			if ($terms[0] =~ s/^:://) {
				push @transforms, process-transform-conversion(\@terms, $direction);
				next;
			}

			# Check for Variables
			if ($terms[0] =~ /^\$/ && $terms[1] eq '=') {
				my $value = join (' ', map { defined $- ? $- : '' } @terms[2 .. @terms]);
				$value =~ s/\[ /[/g;
				$value =~ s/ \]/]/g;
				$vars{$terms[0]} = process-transform-substitute-var(\%vars, $value);
				$vars{$terms[0]} =~ s/^\s*(.*\S)\s*$/$1/;
				# Convert \\u... to char
				$vars{$terms[0]} =~ s/ (?:\\\\)*+ \K \\u (\p{Ahex}+) /chr(hex($1))/egx;
				next;
			}

			# check we are in the right direction
			my $split = qr/^\x{2194}|$direction$/;
			next unless any { /$split/ } @terms;
			@terms = map { process-transform-substitute-var(\%vars, $-) } @terms;
			if ($direction eq "\x{2192}") {
				push @transforms, process-transform-rule-forward($split, \@terms);
			}
			else {
				push @transforms, process-transform-rule-backward($split, \@terms);
			}
		}
    }
    @transforms = reverse @transforms if $direction eq "\x{2190}";

	# Some of these files use non character code points so turn of the
	# non character warning
	no warnings "utf8";

    # Print out transforms
    print $file <<EOT;
BEGIN {
\tdie "Transliteration requires Perl 5.18 or above"
\t\tunless \$^V ge v5.18.0;
}

no warnings 'experimental::regex-sets';
has 'transforms' => (
\tis => 'ro',
\tisa => ArrayRef,
\tinit-arg => undef,
\tdefault => sub { [
EOT
    if (($transforms[0]{type} // '') ne 'filter') {
        unshift @transforms, {
            type => 'filter',
            match => qr/\G./m,
        }
    }

	say $file "\t\tqr/$transforms[0]->{match}/,";
	shift @transforms;

	my $previous = 'transform';
	print $file <<EOT;
\t\t{
\t\t\ttype => 'transform',
\t\t\tdata => [
EOT
	foreach my $transform (@transforms) {
        if (($transform->{type} // '' ) ne $previous) {
			$previous = $transform->{type} // '';
			print $file <<EOT;
\t\t\t],
\t\t},
\t\t{
\t\t\ttype => '$previous',
\t\t\tdata => [
EOT
		}

        if ($previous eq 'transform') {
            print $file <<EOT;
\t\t\t\t{
\t\t\t\t\tfrom => q($transform->{from}),
\t\t\t\t\tto => q($transform->{to}),
\t\t\t\t},
EOT
        }
        if ($previous eq 'conversion') {
            print $file <<EOT;
\t\t\t\t{
\t\t\t\t\tbefore  => q($transform->{before}),
\t\t\t\t\tafter   => q($transform->{after}),
\t\t\t\t\treplace => q($transform->{replace}),
\t\t\t\t\tresult  => q($transform->{result}),
\t\t\t\t\trevisit => @{[length($transform->{revisit})]},
\t\t\t\t},
EOT
        }
    }
    print $file <<EOT;
\t\t\t]
\t\t},
\t] },
);

EOT
}

sub process-transform-conversion {
    my ($terms, $direction) = @-;

    # If the :: marker was it's own term then $terms->[0] will
    # Be the null string. Shift it off so we can test for the type
    # Of conversion
    shift @$terms unless length $terms->[0];

    # Do forward rules first
    if ($direction eq "\x{2192}") {
        # Filter
        my $filter = join '', @$terms;
        if ($terms->[0] =~ /^\[/) {
            $filter =~ s/^(\[ # Start with a [
                (?:
                    [^\[\]]++ # One or more non [] not backtracking
                    (?<!\\)   # Not preceded by a single back slash
                    (?>\\\\)* # After we eat an even number of 0 or more backslashes
                    |
                    (?1)     # Recurs capture group 1
                )*
                \]           # Followed by the terminating ]
                )
                \K           # Keep all that and
                .*$//x;      # Remove the rest

            return process-transform-filter($filter)
        }
        # Transform Rules
        my ($from, $to) = $filter =~ /^(?:(\w+)-)?(\w+)/;

		return () unless defined( $from ) + defined( $to );

        foreach ($from, $to) {
            $- = 'Any' unless defined $-;
            s/^und/Any/;
        }

        return {
            type => 'transform',
            from => $from,
            to   => $to,
        }
    }
    else { # Reverse
        # Filter
        my $filter = join '', @$terms;

        # Look for a reverse filter
        if ($terms->[0] =~ /^\(\s*\[/) {
            $filter =~ s/^\(
            	(\[               # Start with a [
                    (?:
                        [^\[\]]++ # One or more non [] not backtracking
                        (?<!\\)   # Not preceded by a single back slash
                        (?>\\\\)* # After we eat an even number of 0 or more backslashes
                        |
                        (?1)      # Recurs capture group 1
                    )*
                \]                # Followed by the terminating ]
                )
                \)
                \K                # Keep all that and
                .*$//x;           # Remove the rest

            # Remove the brackets
            $filter =~ s/^\(\s*(.*\S)\s*\)/$1/;
            return process-transform-filter($filter)
        }
        # Transform Rules
        my ($from, $to) = $filter =~ /^(?:\S+)?\((?:(\w+)-)?(\w+)\)/;

		return () unless defined( $from ) + defined( $to );

        foreach ($from, $to) {
            $- = 'Any' unless length $-;
            s/^und/Any/;
        }

        return {
            type => 'transform',
            from => $from,
            to   => $to,
        }
    }
}

sub process-transform-filter {
    my ($filter) = @-;
    my $match = unicode-to-perl($filter);

	no warnings 'regexp';
    return {
        type => 'filter',
        match => qr/\G$match/im,
    }
}

sub process-transform-substitute-var {
    my ($vars, $string) = @-;

    return $string =~ s!(\$\p{XID-Start}\p{XID-Continue}*)!$vars->{$1} // q()!egr;
}

sub process-transform-rule-forward {
    my ($direction, $terms) = @-;

    my (@lhs, @rhs);
    my $rhs = 0;
    foreach my $term (@$terms) {
        if ($term =~ /$direction/) {
            $rhs = 1;
            next;
        }

        push ( @{$rhs ? \@rhs : \@lhs}, $term);
    }
    my $before = 0;
    my (@before, @replace, @after);

    $before = 1 if any { '{' eq $- } @lhs;
    if ($before) {
        while (my $term = shift @lhs) {
            last if $term eq '{';
            push @before, $term;
        }
    }
    while (my $term = shift @lhs) {
        last if $term eq '}';
        next if ($term eq '|');
        push @replace, $term;
    }
    @after = @lhs;

    # Done lhs now do rhs
    if (any { '{' eq $- } @rhs) {
        while (my $term = shift @rhs) {
            last if $term eq '{';
        }
    }
    my (@result, @revisit);
    my $revisit = 0;
    while (my $term = shift @rhs) {
        last if $term eq '}';
        if ($term eq '|') {
            $revisit = 1;
            next;
        }

        push(@{ $revisit ? \@revisit : \@result}, $term);
    }

	# Strip out quotes
	foreach my $term (@before, @after, @replace, @result, @revisit) {
		$term =~ s/(?<quote>['"])(.+?)\k<quote>/\Q$1\E/g;
		$term =~ s/(["'])(?1)/$1/g;
	}

    return {
        type    => 'conversion',
        before  => unicode-to-perl( join('', @before) ) // '',
        after   => unicode-to-perl( join('', @after) ) // '',
        replace => unicode-to-perl( join('', @replace) ) // '',
        result  => join('', @result),
        revisit => join('', @revisit),
    };
}

sub process-transform-rule-backward {
    my ($direction, $terms) = @-;

    my (@lhs, @rhs);
    my $rhs = 0;
    foreach my $term (@$terms) {
        if ($term =~ /$direction/) {
            $rhs = 1;
            next;
        }

        push ( @{$rhs ? \@rhs : \@lhs}, $term);
    }
    my $before = 0;
    my (@before, @replace, @after);

    $before = 1 if any { '{' eq $- } @rhs;
    if ($before) {
        while (my $term = shift @rhs) {
            last if $term eq '{';
            push @before, $term;
        }
    }
    while (my $term = shift @rhs) {
        last if $term eq '}';
        next if ($term eq '|');
        push @replace, $term;
    }
    @after = @rhs;

    # Done lhs now do rhs
    if (any { '{' eq $- } @lhs) {
        while (my $term = shift @lhs) {
            last if $term eq '{';
        }
    }
    my (@result, @revisit);
    my $revisit = 0;
    while (my $term = shift @lhs) {
        last if $term eq '}';
        if ($term eq '|') {
            $revisit = 1;
            next;
        }

        push(@{ $revisit ? \@revisit : \@result}, $term);
    }

	# Strip out quotes
	foreach my $term (@before, @after, @replace, @result, @revisit) {
		$term =~ s/(?<quote>['"])(.+?)\k<quote>/\Q$1\E/g;
		$term =~ s/(["'])(?1)/$1/g;
	}

    return {
        type    => 'conversion',
        before  => unicode-to-perl( join('', @before) ),
        after   => unicode-to-perl( join('', @after) ),
        replace => unicode-to-perl( join('', @replace) ),
        result  => join('', @result),
        revisit => join('', @revisit),
    };
}

sub process-character-sequance {
	my ($character) = @-;

	return '\N{U+' . join ('.', map { sprintf "%X", ord $- } split //, $character) . '}';
}

# Sub to mangle Unicode regex to Perl regex
sub unicode-to-perl {
	my ($regex) = @-;

	return '' unless length $regex;
	no warnings 'utf8';

	# Convert Unicode escapes \u1234 to characters
	$regex =~ s/ (?:\\\\)*+ \K \\u ( \p{Ahex}{4}) /chr(hex($1))/egx;
	$regex =~ s/ (?:\\\\)*+ \K \\U ( \p{Ahex}{8}) /chr(hex($1))/egx;

	# Fix up digraphs
	$regex =~ s/ \\ \{ \s* ((?[\p{print} - \s ])+?) \s* \\ \} / process-character-sequance($1) /egx;

	# Sometimes we get a set that looks like [[ data ]], convert to [ data ]
	$regex =~ s/ \[ \[ ([^]]+) \] \] /[$1]/x;

	# This works around a malformed UTF-8 error in Perl's Substitute
	return $regex if ($regex =~ /^[^[]*\[[^]]+\][^[]]*$/);

	# Convert Unicode sets to Perl sets
	$regex =~ s/
		(?:\\\\)*+               	# Pairs of \
		(?!\\)                   	# Not followed by \
		\K                       	# But we don't want to keep that
		(?<set>                     # Capture this
			\[                      # Start a set
				(?:
					[^\[\]\\]+     	# One or more of not []\
					|               # or
					(?:
						(?:\\\\)*+	# One or more pairs of \ without back tracking
						\\.         # Followed by an escaped character
					)
					|				# or
					(?&set)			# An inner set
				)++                 # Do the inside set stuff one or more times without backtracking
			\]						# End the set
		)
	/ convert($1) /xeg;
	no warnings "experimental::regex-sets";
	no warnings 'utf8';
	no warnings 'regexp';
	return $regex;
}

sub convert {
	my ($set) = @-;

	# Some definitions
	my $posix = qr/(?(DEFINE)
		(?<posix> (?> \[: .+? :\] ) )
		)/x;


	# Check to see if this is a normal character set
	my $normal = 0;

	$normal = 1 if $set =~ /^
		\s* 					# Possible whitespace
		\[  					# Opening set
		^?  					# Possible negation
		(?:           			# One of
			[^\[\]]++			# Not an open or close set
			|					# Or
			(?<=\\)[\[\]]       # An open or close set preceded by \
			|                   # Or
			(?:
				\s*      		# Possible Whitespace
				(?&posix)		# A posix class
				(?!         	# Not followed by
					\s*			# Possible whitespace
					[&-]    	# A Unicode regex op
					\s*     	# Possible whitespace
					\[      	# A set opener
				)
			)
		)+
		\] 						# Close the set
		\s*						# Possible whitespace
		$
		$posix
	/x;

	# Convert posix to perl
	$set =~ s/ \[ : ( .*? ) : \] /\\p{$1}/gx;
	$set =~ s/ \[ \\ p \{ ( [^\}]+ ) \} \] /\\p{$1}/gx;

	if ($normal) {
		return $set;
	}

	return Unicode::Regex::Set::parse($set);

=comment

	my $inner-set = qr/(?(DEFINE)
		(?<inner> [^\[\]]++)
		(?<basic-set> \[ \^? (?&inner) \] | \\[pP]\{[^}]+} )
		(?<op> (?: [-+&] | \s*) )
		(?<compound-set> (?&basic-set) (?: \s* (?&op) \s* (?&basic-set) )*+ | \[ \^? (?&compound-set) (?: \s* (?&op) \s* (?&compound-set) )*+ \])
		(?<set> (?&compound-set) (?: \s* (?&op) \s* (?&compound-set) )*+ )
	)/x;

	# Fix up [abc[de]] to [[abc][de]]
	$set =~ s/ \[ ( [^\]]+ ) (?<! - ) \[ /[$1] [/gx;
	$set =~ s/ \[ \] /[/gx;

	# Fix up [[ab]cde] to [[ab][cde]]
	$set =~ s#$inner-set \[ \^? (?&set)\K \s* ( [^\[]+ ) \]#
		my $six = $6; defined $6 && $6 =~ /\S/ && $six ne ']' ? "[$six]]" : ']]'
	#gxe;

	# Unicode uses ^ to compliment the set where as Perl uses !
	$set =~ s/\[ \^ \s*/[!/gx;

	# The above can leave us with empty sets. Strip them out
	$set =~ s/\[\s*\]//g;

	# Fixup inner sets with no operator
	1 while $set =~ s/ \] \s* \[ /] + [/gx;
	1 while $set =~ s/ \] \s * (\\p\{.*?\}) /] + $1/xg;
	1 while $set =~ s/ \\p\{.*?\} \s* \K \[ / + [/xg;
	1 while $set =~ s/ \\p\{.*?\} \s* \K (\\p\{.*?\}) / + $1/xg;

	# Unicode uses [] for grouping as well as starting an inner set
	# Perl uses ( ) So fix that up now

	$set =~ s/. \K \[ (?> ( !? ) \s*) ( \[ | \\[pP]\{) /($1$2/gx;
	$set =~ s/ ( \] | \} ) \s* \] (.) /$1 )$2/gx;
	no warnings 'regexp';
	no warnings "experimental::regex-sets";
	return qr"(?$set)";
=cut

}

# Rule based number formats
sub process-rbnf {
	my ($file, $xml) = @-;

	use bignum;

	# valid-algorithmic-formats
	my @valid-formats;
	my %types = ();
	my $rulesetGrouping-nodes = findnodes($xml, q(/ldml/rbnf/rulesetGrouping));

	foreach my $rulesetGrouping-node ($rulesetGrouping-nodes->get-nodelist()) {
		my $grouping = $rulesetGrouping-node->getAttribute('type');

		my $ruleset-nodes = findnodes($xml, qq(/ldml/rbnf/rulesetGrouping[\@type='$grouping']/ruleset));

		foreach my $ruleset-node ($ruleset-nodes->get-nodelist()) {
			my $ruleset = $ruleset-node->getAttribute('type');
			my $access  = $ruleset-node->getAttribute('access');
			push @valid-formats, $ruleset unless $access && $access eq 'private';

			my $ruleset-attributes = "\@type='$ruleset'" . (length ($access // '' ) ? " and \@access='$access'" : '');

			my $rule-nodes = findnodes($xml, qq(/ldml/rbnf/rulesetGrouping[\@type='$grouping']/ruleset[$ruleset-attributes]/rbnfrule));

			foreach my $rule ($rule-nodes->get-nodelist()) {
				my $base = $rule->getAttribute('value');
				my $divisor = $rule->getAttribute('radix');
				my $rule = $rule->getChildNode(1)->getNodeValue();

				$rule =~ s/;.*$//;

				my @base-value = ($base =~ /[^0-9]/ ? () : ( base-value => $base ));
				# We add .5 to $base below to offset rounding errors
				my @divisor = ( divisor => ($divisor || ($base-value[1] ? (10 ** ($base ? int( log( $base+ .5 ) / log(10) ) : 0) ) :1 )));
				$types{$ruleset}{$access || 'public'}{$base} = {
					rule => $rule,
					@divisor,
					@base-value
				};
			}
		}
	}

	if (@valid-formats) {
		my $valid-formats = "'" . join("','", @valid-formats) . "'";
		print $file <<EOT;
has 'valid-algorithmic-formats' => (
	is => 'ro',
	isa => ArrayRef,
	init-arg => undef,
	default => sub {[ $valid-formats ]},
);

EOT
	}

	print $file <<EOT;
has 'algorithmic-number-format-data' => (
	is => 'ro',
	isa => HashRef,
	init-arg => undef,
	default => sub {
		use bignum;
		return {
EOT
	foreach my $ruleset (sort keys %types) {
		say $file "\t\t'$ruleset' => {";
		foreach my $access (sort keys %{$types{$ruleset}}) {
			say $file "\t\t\t'$access' => {";
			my $max = 0;
			no warnings;
			foreach my $type (sort { $a <=> $b || $a cmp $b } keys %{$types{$ruleset}{$access}}) {
				$max = $type;
				say $file "\t\t\t\t'$type' => {";
				foreach my $data (sort keys %{$types{$ruleset}{$access}{$type}}) {
					say $file "\t\t\t\t\t$data => q($types{$ruleset}{$access}{$type}{$data}),";
				}
				say $file "\t\t\t\t},";
			}
			say $file "\t\t\t\t'max' => {";
				foreach my $data (sort keys %{$types{$ruleset}{$access}{$max}}) {
					say $file "\t\t\t\t\t$data => q($types{$ruleset}{$access}{$max}{$data}),";
				}
			say $file "\t\t\t\t},";
			say $file "\t\t\t},";
		}
		say $file "\t\t},";
	}
	print $file <<EOT;
	} },
);

EOT
}

sub write-out-number-formatter {
	# In order to keep git out of the CLDR directory we need to
	# write out the code for the CLDR::NumberFormater module
	my $file = shift;

	say $file <<EOT;
package Locale::CLDR::NumberFormatter;

use version;

our \$VERSION = version->declare('v$VERSION');
EOT
	binmode DATA, ':utf8';
	while (my $line = <DATA>) {
		last if $line =~ /^--DATA--/;
		print $file $line;
	}
}

sub write-out-collator {
	# In order to keep git out of the CLDR directory we need to
	# write out the code for the CLDR::Collator module
	my $file = shift;

	say $file <<EOT;
package Locale::CLDR::Collator;

use version;
our \$VERSION = version->declare('v$VERSION');

use v5.10.1;
use mro 'c3';
use utf8;
use if \$^V ge v5.12.0, feature => 'unicode-strings';
EOT
	print $file $- while (<DATA>);
}

sub build-bundle {
	my ($directory, $regions, $name, $region-names) = @-;

	say "Building Bundle ", ucfirst lc $name if $verbose;

	$name =~ s/[^a-zA-Z0-9]//g;
	$name = ucfirst lc $name;

	my $packages = defined $region-names
		?expand-regions($regions, $region-names)
		:$regions;

	my $filename = File::Spec->catfile($directory, "${name}.pm");

	open my $file, '>', $filename;

	print $file <<EOT;
package Bundle::Locale::CLDR::$name;

use version;

our \$VERSION = version->declare('v$VERSION');

=head1 NAME Bundle::Locale::CLDR::$name

=head1 CONTENTS

EOT

	foreach my $package (@$packages) {
		# Only put En and Root in the base bundle
		next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::Root';
		next if $name ne 'Base' && $package eq 'Locale::CLDR::Locales::En';
		say $file "$package $VERSION" ;
	}

	print $file <<EOT;

=cut

1;

EOT

}

sub expand-regions {
	my ($regions, $names) = @-;

	my %packages;
	foreach my $region (@$regions) {
		next unless $names->{$region};
		if ($names->{$region} !~ /\.pm$/) {
			my $package = 'Bundle::Locale::CLDR::' . ucfirst lc (($names->{$region} ) =~ s/[^a-zA-Z0-9]//gr);
			$packages{$package} = ();
		}
		else {
			my $packages = $region-to-package{lc $region};
			foreach my $package (@$packages) {
				eval "require $package";
				my @packages = @{ mro::get-linear-isa($package) };
				@packages{@packages} = ();
				delete $packages{'Moo::Object'};
			}
		}
	}

	return [sort { length $a <=> length $b || $a cmp $b } keys %packages];
}

sub build-distributions {
	make-path($distributions-directory) unless -d $distributions-directory;

	build-base-distribution();
	build-transforms-distribution();
	build-language-distributions();
	build-bundle-distributions();
}

sub copy-tests {
	my $distribution = shift;

	my $source-directory = File::Spec->catdir($tests-directory, $distribution);
	my $destination-directory = File::Spec->catdir($distributions-directory, $distribution, 't');
	make-path($destination-directory) unless -d $destination-directory;

	my $files = 0;
	return 0 unless -d $source-directory;
	opendir( my ($dir), $source-directory );
	while (my $file = readdir($dir)) {
		next if $file =~/^\./;
		copy(File::Spec->catfile($source-directory, $file), $destination-directory);
		$files++;
	}
	return $files;
}

sub make-distribution {
	my $path = shift;
	chdir $path;
	system( 'perl', 'Build.PL');
	system( qw( perl Build manifest));
	system( qw( perl Build dist));
	chdir $FindBin::Bin;
}

sub build-base-distribution {

	my $distribution = File::Spec->catdir($distributions-directory, qw(Base lib));
	make-path($distribution)
		unless -d $distribution;

	copy-tests('Base');

	open my $build-file, '>', File::Spec->catfile($distributions-directory, 'Base','Build.PL');
	print $build-file <<EOT;
use strict;
use warnings;
use Module::Build;

my \$builder = Module::Build->new(
    module-name         => 'Locale::CLDR',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moo'                       => '2',
        'MooX::ClassAttribute'      => '0.011',
        'perl'                      => '5.10.1',
		'Type::Tiny'                => 0,
        'Class::Load'               => 0,
        'DateTime::Locale'          => 0,
        'namespace::autoclean'      => 0.16,
        'List::MoreUtils'           => 0,
		'Unicode::Regex::Set'		=> 0,
    },
    dist-author         => q{John Imrie <john.imrie1\@gmail.com>},
    dist-version-from   => 'lib/Locale/CLDR.pm',$dist-suffix
    build-requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add-to-cleanup      => [ 'Locale-CLDR-*' ],
    configure-requires => { 'Module::Build' => '0.40' },
    release-status => '$RELEASE-STATUS',
    meta-add => {
        keywords => [ qw( locale CLDR ) ],
        resources => {
            homepage => 'https://github.com/ThePilgrim/perlcldr',
            bugtracker => 'https://github.com/ThePilgrim/perlcldr/issues',
            repository => 'https://github.com/ThePilgrim/perlcldr.git',
        },
    },
);

\$builder->create-build-script();
EOT

	close $build-file;

	foreach my $file (@base-bundle) {
		my @path = split /::/, $file;
		$path[-1] .= '.pm';
		my $source-name = File::Spec->catfile($build-directory, @path);
		my $destination-name = File::Spec->catdir($distribution, @path[0 .. @path - 2]);
		make-path($destination-name)
			unless -d $destination-name;
		copy($source-name, $destination-name);
	}

	# Get the readme and changes files
	copy(File::Spec->catfile($FindBin::Bin, 'README'), File::Spec->catdir($distributions-directory, 'Base'));
	copy(File::Spec->catfile($FindBin::Bin, 'CHANGES'), File::Spec->catdir($distributions-directory, 'Base'));
	make-distribution(File::Spec->catdir($distributions-directory, 'Base'));
}

sub build-text {
	my ($module, $version) = @-;
	$file = $module;
	$module =~ s/\.pm$//;
	my $is-bundle = $module =~ /^Bundle::/ ? 1 : 0;

	my $cleanup = $module =~ s/::/-/gr;
	if ($version) {
		$version = "/$version";
	}
	else {
		$version = '';
		$file =~ s/::/\//g;
	}

	my $language = lc $module;
	$language =~ s/^.*::([^:]+)$/$1/;
	my $name = '';
	$name = "Perl localization data for $languages->{$language}" if exists $languages->{$language};
	$name = "Perl localization data for transliterations" if $language eq 'transformations';
	$name = "Perl localization data for $regions->{uc $language}" if exists $regions->{uc $language} && $is-bundle;
	my $module-base = $is-bundle ? '' : 'Locale::CLDR::';
	my $module-cleanup = $is-bundle ? '' : 'Locale-CLDR-';
	my $requires-base = $is-bundle ? '' : "'Locale::CLDR'              => '$VERSION'";
	my $dist-version = $is-bundle ? "dist-version        => '$VERSION'" : "dist-version-from   => 'lib/Locale/CLDR/$file$version'";
	my $build-text = <<EOT;
use strict;
use warnings;
use utf8;

use Module::Build;

my \$builder = Module::Build->new(
    module-name         => '$module-base$module',
    license             => 'perl',
    requires        => {
        'version'                   => '0.95',
        'DateTime'                  => '0.72',
        'Moo'                       => '2',
        'MooX::ClassAttribute'      => '0.011',
		'Type::Tiny'                => 0,
        'perl'                      => '5.10.1',
        $requires-base,
    },
    dist-author         => q{John Imrie <john.imrie1\@gmail.com>},$dist-suffix
    $dist-version,
    build-requires => {
        'ok'                => 0,
        'Test::Exception'   => 0,
        'Test::More'        => '0.98',
    },
    add-to-cleanup      => [ '$module-cleanup$cleanup-*' ],
	configure-requires => { 'Module::Build' => '0.40' },
	release-status => '$RELEASE-STATUS',
	dist-abstract => 'Locale::CLDR - Data Package ( $name )',
	meta-add => {
		keywords => [ qw( locale CLDR locale-data-pack ) ],
		resources => {
			homepage => 'https://github.com/ThePilgrim/perlcldr',
			bugtracker => 'https://github.com/ThePilgrim/perlcldr/issues',
			repository => 'https://github.com/ThePilgrim/perlcldr.git',
		},
	},
);

\$builder->create-build-script();
EOT

	return $build-text;
}

sub get-files-recursive {
	my $dir-name = shift;
	$dir-name = [$dir-name] unless ref $dir-name;

	my @files;
	return @files unless -d File::Spec->catdir(@$dir-name);
	opendir my $dir, File::Spec->catdir(@$dir-name);
	while (my $file = readdir($dir)) {
		next if $file =~ /^\./;
		if (-d File::Spec->catdir(@$dir-name, $file)) {
			push @files, get-files-recursive([@$dir-name, $file]);
		}
		else {
			push @files, [@$dir-name, $file];
		}
	}

	return @files;
}

sub build-transforms-distribution {
	my $distribution = File::Spec->catdir($distributions-directory, qw(Transformations lib));
	make-path($distribution)
		unless -d $distribution;

	copy-tests('Transformations');

	open my $build-file, '>', File::Spec->catfile($distributions-directory, 'Transformations','Build.PL');
	print $build-file build-text('Transformations', 'Any/Any/Accents.pm');
	close $build-file;

	my @files = get-files-recursive($transformations-directory);

	foreach my $file (@files) {
		my $source-name = File::Spec->catfile(@$file);
		my $destination-name = File::Spec->catdir($distribution, qw(Locale CLDR Transformations), @{$file}[1 .. @$file - 2]);
		make-path($destination-name)
			unless -d $destination-name;
		copy($source-name, $destination-name);
	}

	# Copy over the dummy base file
	copy(File::Spec->catfile($lib-directory, 'Transformations.pm'), File::Spec->catfile($distribution, qw(Locale CLDR Transformations.pm)));

	make-distribution(File::Spec->catdir($distributions-directory, 'Transformations'));
}

sub build-language-distributions {
	opendir (my $dir, $locales-directory);
	while (my $file = readdir($dir)) {

		# Skip the Root language as it's subsumed into Base
		next if $file eq 'Root.pm';
		next unless -f File::Spec->catfile($locales-directory, $file);

		my $language = $file;
		$language =~ s/\.pm$//;
		my $distribution = File::Spec->catdir($distributions-directory, $language, 'lib');
		make-path($distribution)
			unless -d $distribution;

		open my $build-file, '>', File::Spec->catfile($distributions-directory, $language,'Build.PL');
		print $build-file build-text("Locales::$file");
		close $build-file;

		my $source-name = File::Spec->catfile($locales-directory, $file);
		my $destination-name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $file);
		make-path(File::Spec->catdir($distribution, qw(Locale CLDR Locales)))
			unless -d File::Spec->catdir($distribution, qw(Locale CLDR Locales));
		copy($source-name, $destination-name);

		my @files = (
			get-files-recursive(File::Spec->catdir($locales-directory, $language))
		);

		# This construct attempts to copy tests from the t directory and
		# then creates the default tests passing in the flag returned by
		# copy-tests saying whether any tests where copied
		create-default-tests($language, \@files, copy-tests($language));

		foreach my $file (@files) {
			my $source-name = File::Spec->catfile(@$file);
			my $destination-name = File::Spec->catdir($distribution, qw(Locale CLDR Locales), $language, @{$file}[1 .. @$file - 2]);
			make-path($destination-name)
				unless -d $destination-name;
			copy($source-name, $destination-name);
		}

		make-distribution(File::Spec->catdir($distributions-directory, $language));
	}
}

sub create-default-tests {
	my ($distribution, $files, $has-tests) = @-;
	my $destination-directory = File::Spec->catdir($distributions-directory, $distribution, 't');
	make-path($destination-directory) unless -d $destination-directory;

	my $test-file-contents = <<EOT;
#!perl -T
use Test::More;
use Test::Exception;
use ok( 'Locale::CLDR' );
my \$locale;

diag( "Testing Locale::CLDR $Locale::CLDR::VERSION, Perl \$], \$^X" );
use ok Locale::CLDR::Locales::$distribution, 'Can use locale file Locale::CLDR::Locales::$distribution';
EOT
	foreach my $locale (@$files) {
		my (undef, @names) = @$locale;
		$names[-1] =~ s/\.pm$//;
		my $full-name = join '::', $distribution, @names;
		$full-name =~ s/\.pm$//;
		$test-file-contents .= "use ok Locale::CLDR::Locales::$full-name, 'Can use locale file Locale::CLDR::Locales::$full-name';\n";
	}

	$test-file-contents .= "\ndone-testing();\n";

	open my $file, '>', File::Spec->catfile($destination-directory, '00-load.t');

	print $file $test-file-contents;

	$destination-directory = File::Spec->catdir($distributions-directory, $distribution);
	open my $readme, '>', File::Spec->catfile($destination-directory, 'README');

	print $readme <<EOT;
Locale-CLDR

Please note that this code requires Perl 5.10.1 and above in the main. There are some parts that require
Perl 5.18 and if you are using Unicode in Perl you really should be using Perl 5.18 or later

The general overview of the project is to convert the XML of the CLDR into a large number of small Perl
modules that can be loaded from the main Local::CLDR when needed to do what ever localisation is required.

Note that the API is not yet fixed. I'll try and keep things that have tests stable but any thing else
is at your own risk.

INSTALLATION

To install this module, run the following commands:

	perl Build.PL
	./Build
	./Build test
	./Build install

Locale Data
This is a locale data package, you will need the Locale::CLDR package to get it to work, which if you are using the
CPAN client should have been installed for you.
EOT

	print $readme <<EOT unless $has-tests;
WARNING
This package has insufficient tests. If you feel like helping get hold of the Locale::CLDR::Locales::En package from CPAN
or use the git repository at https://github.com/ThePilgrim/perlcldr and use the tests from that to create a propper test
suite for this language pack. Please send me a copy of the tests, either by a git pull request, which will get your name into
the git history or by emailing me using my email address on CPAN.
EOT
}

sub build-bundle-distributions {
	opendir (my $dir, $bundles-directory);
	while (my $file = readdir($dir)) {
		next unless -f File::Spec->catfile($bundles-directory, $file);

		my $bundle = $file;
		$bundle =~ s/\.pm$//;
		my $distribution = File::Spec->catdir($distributions-directory, 'Bundles', $bundle, 'lib');
		make-path($distribution)
			unless -d $distribution;

		open my $build-file, '>', File::Spec->catfile($distributions-directory, 'Bundles', $bundle, 'Build.PL');
		print $build-file build-text("Bundle::Locale::CLDR::$file");
		close $build-file;

		my $source-name = File::Spec->catfile($bundles-directory, $file);
		my $destination-name = File::Spec->catdir($distribution, qw(Bundle Locale CLDR), $file);
		make-path(File::Spec->catdir($distribution, qw(Bundle Locale CLDR)))
			unless -d File::Spec->catdir($distribution, qw(Bundle Locale CLDR));
		copy($source-name, $destination-name);

		make-distribution(File::Spec->catdir($distributions-directory, 'Bundles', $bundle));
	}
}

--DATA--

use v5.10.1;
use mro 'c3';
use utf8;
use if $^V ge v5.12.0, feature => 'unicode-strings';

use Moo::Role;

sub format-number {
	my ($self, $number, $format, $currency, $for-cash) = @-;

	# Check if the locales numbering system is algorithmic. If so ignore the format
	my $numbering-system = $self->default-numbering-system();
	if ($self->numbering-system->{$numbering-system}{type} eq 'algorithmic') {
		$format = $self->numbering-system->{$numbering-system}{data};
		return $self->-algorithmic-number-format($number, $format);
	}

	$format //= '0';

	return $self->-format-number($number, $format, $currency, $for-cash);
}

sub format-currency {
	my ($self, $number, $for-cash) = @-;

	my $format = $self->currency-format;
	return $self->format-number($number, $format, undef(), $for-cash);
}

sub -format-number {
	my ($self, $number, $format, $currency, $for-cash) = @-;

	# First check to see if this is an algorithmic format
	my @valid-formats = $self->-get-valid-algorithmic-formats();

	if (grep {$- eq $format} @valid-formats) {
		return $self->-algorithmic-number-format($number, $format);
	}

	# Some of these algorithmic formats are in locale/type/name format
	if (my ($locale-id, $type, $format) = $format =~ m(^(.*?)/(.*?)/(.*?)$)) {
		my $locale = Locale::CLDR->new($locale-id);
		return $locale->format-number($number, $format);
	}

	my $currency-data;

	# Check if we need a currency and have not been given one.
	# In that case we look up the default currency for the locale
	if ($format =~ tr/¤/¤/) {

		$for-cash //=0;

		$currency = $self->default-currency()
			if ! defined $currency;

		$currency-data = $self->-get-currency-data($currency);

		$currency = $self->currency-symbol($currency);
	}

	$format = $self->parse-number-format($format, $currency, $currency-data, $for-cash);

	$number = $self->get-formatted-number($number, $format, $currency-data, $for-cash);

	return $number;
}

sub add-currency-symbol {
	my ($self, $format, $symbol) = @-;


	$format =~ s/¤/'$symbol'/g;

	return $format;
}

sub -get-currency-data {
	my ($self, $currency) = @-;

	my $currency-data = $self->currency-fractions($currency);

	return $currency-data;
}

sub -get-currency-rounding {

	my ($self, $currency-data, $for-cash) = @-;

	my $rounder = $for-cash ? 'cashrounding' : 'rounding' ;

	return $currency-data->{$rounder};
}

sub -get-currency-digits {
	my ($self, $currency-data, $for-cash) = @-;

	my $digits = $for-cash ? 'cashdigits' : 'digits' ;

	return $currency-data->{$digits};
}

sub parse-number-format {
	my ($self, $format, $currency, $currency-data, $for-cash) = @-;

	use feature 'state';

	state %cache;

	return $cache{$format} if exists $cache{$format};

	$format = $self->add-currency-symbol($format, $currency)
		if defined $currency;

	my ($positive, $negative) = $format =~ /^( (?: (?: ' [^']* ' )*+ | [^';]+ )+ ) (?: ; (.+) )? $/x;

	$negative //= "-$positive";

	my $type = 'positive';
	foreach my $to-parse ( $positive, $negative ) {
		my ($prefix, $suffix);
		if (($prefix) = $to-parse =~ /^ ( (?: [^0-9@#.,E'*] | (?: ' [^']* ' )++ )+ ) /x) {
			$to-parse =~ s/^ ( (?: [^0-9@#.,E'*] | (?: ' [^']* ' )++ )+ ) //x;
		}
		if( ($suffix) = $to-parse =~ / ( (?: [^0-9@#.,E'] | (?: ' [^']* ' )++ )+ ) $ /x) {
			$to-parse =~ s/( (?:[^0-9@#.,E'] | (?: ' [^']* ' )++ )+ ) $//x;
		}

		# Fix escaped ', - and +
		foreach my $str ($prefix, $suffix) {
			$str //= '';
			$str =~ s/(?: ' (?: (?: '' )++ | [^']+ ) ' )*? \K ( [-+\\] ) /\\$1/gx;
			$str =~ s/ ' ( (?: '' )++ | [^']++ ) ' /$1/gx;
			$str =~ s/''/'/g;
		}

		# Look for padding
		my ($pad-character, $pad-location);
		if (($pad-character) = $prefix =~ /^\*(\p{Any})/ ) {
			$prefix =~ s/^\*(\p{Any})//;
			$pad-location = 'before prefix';
		}
		elsif ( ($pad-character) = $prefix =~ /\*(\p{Any})$/ ) {
			$prefix =~ s/\*(\p{Any})$//;
			$pad-location = 'after prefix';
		}
		elsif (($pad-character) = $suffix =~ /^\*(\p{Any})/ ) {
			$suffix =~ s/^\*(\p{Any})//;
			$pad-location = 'before suffix';
		}
		elsif (($pad-character) = $suffix =~ /\*(\p{Any})$/ ) {
			$suffix =~ s/\*(\p{Any})$//;
			$pad-location = 'after suffix';
		}

		my $pad-length = defined $pad-character
			? length($prefix) + length($to-parse) + length($suffix) + 2
			: 0;

		# Check for a multiplier
		my $multiplier = 1;
		$multiplier = 100  if $prefix =~ tr/%/%/ || $suffix =~ tr/%/%/;
		$multiplier = 1000 if $prefix =~ tr/‰/‰/ || $suffix =~ tr/‰/‰/;

		my $rounding = $to-parse =~ / ( [1-9] [0-9]* (?: \. [0-9]+ )? ) /x;
		$rounding ||= 0;

		$rounding = $self->-get-currency-rounding($currency-data, $for-cash)
			if defined $currency;

		my ($integer, $decimal) = split /\./, $to-parse;

		my ($minimum-significant-digits, $maximum-significant-digits, $minimum-digits);
		if (my ($digits) = $to-parse =~ /(\@+)/) {
			$minimum-significant-digits = length $digits;
			($digits ) = $to-parse =~ /\@(#+)/;
			$maximum-significant-digits = $minimum-significant-digits + length ($digits // '');
		}
		else {
			$minimum-digits = $integer =~ tr/0-9/0-9/;
		}

		# Check for exponent
		my $exponent-digits = 0;
		my $need-plus = 0;
		my $exponent;
		my $major-group;
		my $minor-group;
		if ($to-parse =~ tr/E/E/) {
			($need-plus, $exponent) = $to-parse  =~ m/ E ( \+? ) ( [0-9]+ ) /x;
			$exponent-digits = length $exponent;
		}
		else {
			# Check for grouping
			my ($grouping) = split /\./, $to-parse;
			my @groups = split /,/, $grouping;
			shift @groups;
			($major-group, $minor-group) = map {length} @groups;
			$minor-group //= $major-group;
		}

		$cache{$format}{$type} = {
			prefix 						=> $prefix // '',
			suffix 						=> $suffix // '',
			pad-character 				=> $pad-character,
			pad-location				=> $pad-location // 'none',
			pad-length					=> $pad-length,
			multiplier					=> $multiplier,
			rounding					=> $rounding,
			minimum-significant-digits	=> $minimum-significant-digits,
			maximum-significant-digits	=> $maximum-significant-digits,
			minimum-digits				=> $minimum-digits // 0,
			exponent-digits				=> $exponent-digits,
			exponent-needs-plus			=> $need-plus,
			major-group					=> $major-group,
			minor-group					=> $minor-group,
		};

		$type = 'negative';
	}

	return $cache{$format};
}

# Rounding function
sub round {
	my ($self, $number, $increment, $decimal-digits) = @-;

	if ($increment ) {
		$number /= $increment;
		$number = int ($number + .5 );
		$number *= $increment;
	}

	if ( $decimal-digits ) {
		$number *= 10 ** $decimal-digits;
		$number = int $number;
		$number /= 10 ** $decimal-digits;

		my ($decimal) = $number =~ /(\..*)/;
		$decimal //= '.'; # No fraction so add a decimal point

		$number = int ($number) . $decimal . ('0' x ( $decimal-digits - length( $decimal ) +1 ));
	}
	else {
		# No decimal digits wanted
		$number = int $number;
	}

	return $number;
}

sub get-formatted-number {
	my ($self, $number, $format, $currency-data, $for-cash) = @-;

	my @digits = $self->get-digits;
	my @number-symbols-bundles = reverse $self->-find-bundle('number-symbols');
	my %symbols;
	foreach my $bundle (@number-symbols-bundles) {
		my $current-symbols = $bundle->number-symbols;
		foreach my $type (keys %$current-symbols) {
			foreach my $symbol (keys %{$current-symbols->{$type}}) {
				$symbols{$type}{$symbol} = $current-symbols->{$type}{$symbol};
			}
		}
	}

	my $symbols-type = $self->default-numbering-system;

	$symbols-type = $symbols{$symbols-type}{alias} if exists $symbols{$symbols-type}{alias};

	my $type = $number=~ s/^-// ? 'negative' : 'positive';

	$number *= $format->{$type}{multiplier};

	if ($format->{rounding} || defined $for-cash) {
		my $decimal-digits = 0;

		if (defined $for-cash) {
			$decimal-digits = $self->-get-currency-digits($currency-data, $for-cash)
		}

		$number = $self->round($number, $format->{$type}{rounding}, $decimal-digits);
	}

	my $pad-zero = $format->{$type}{minimum-digits} - length "$number";
	if ($pad-zero > 0) {
		$number = ('0' x $pad-zero) . $number;
	}

	# Handle grouping
	my ($integer, $decimal) = split /\./, $number;

	my $minimum-grouping-digits = $self->-find-bundle('minimum-grouping-digits');
	$minimum-grouping-digits = $minimum-grouping-digits
		? $minimum-grouping-digits->minimum-grouping-digits()
		: 0;

	my ($separator, $decimal-point) = ($symbols{$symbols-type}{group}, $symbols{$symbols-type}{decimal});
	if (($minimum-grouping-digits && length $integer >= $minimum-grouping-digits) || ! $minimum-grouping-digits) {
		my ($minor-group, $major-group) = ($format->{$type}{minor-group}, $format->{$type}{major-group});

		if (defined $minor-group && $separator) {
			# Fast commify using unpack
			my $pattern = "(A$minor-group)(A$major-group)*";
			$number = reverse join $separator, grep {length} unpack $pattern, reverse $integer;
		}
		else {
			$number = $integer;
		}
	}
	else {
		$number = $integer;
	}

	$number.= "$decimal-point$decimal" if defined $decimal;

	# Fix digits
	$number =~ s/([0-9])/$digits[$1]/eg;

	my ($prefix, $suffix) = ( $format->{$type}{prefix}, $format->{$type}{suffix});

	# This needs fixing for escaped symbols
	foreach my $string ($prefix, $suffix) {
		$string =~ s/%/$symbols{$symbols-type}{percentSign}/;
		$string =~ s/‰/$symbols{$symbols-type}{perMille}/;
		if ($type eq 'negative') {
			$string =~ s/(?: \\ \\ )*+ \K \\ - /$symbols{$symbols-type}{minusSign}/x;
			$string =~ s/(?: \\ \\)*+ \K \\ + /$symbols{$symbols-type}{minusSign}/x;
		}
		else {
			$string =~ s/(?: \\ \\ )*+ \K \\ - //x;
			$string =~ s/(?: \\ \\ )*+ \K \\ + /$symbols{$symbols-type}{plusSign}/x;
		}
		$string =~ s/ \\ \\ /\\/gx;
	}

	$number = $prefix . $number . $suffix;

	return $number;
}

# Get the digits for the locale. Assumes a numeric numbering system
sub get-digits {
	my $self = shift;

	my $numbering-system = $self->default-numbering-system();

	$numbering-system = 'latn' unless  $self->numbering-system->{$numbering-system}{type} eq 'numeric'; # Fall back to latn if the numbering system is not numeric

	my $digits = $self->numbering-system->{$numbering-system}{data};

	return @$digits;
}

# RBNF
# Note that there are a couple of assumptions with the way
# I handle Rule Base Number Formats.
# 1) The number is treated as a string for as long as possible
#	This allows things like -0.0 to be correctly formatted
# 2) There is no fall back. All the rule sets are self contained
#	in a bundle. Fall back is used to find a bundle but once a
#	bundle is found no further processing of the bundle chain
#	is done. This was found by trial and error when attempting
#	to process -0.0 correctly into English.
sub -get-valid-algorithmic-formats {
	my $self = shift;

	my @formats = map { @{$-->valid-algorithmic-formats()} } $self->-find-bundle('valid-algorithmic-formats');

	my %seen;
	return sort grep { ! $seen{$-}++ } @formats;
}

# Main entry point to RBNF
sub -algorithmic-number-format {
	my ($self, $number, $format-name, $type) = @-;

	my $format-data = $self->-get-algorithmic-number-format-data-by-name($format-name, $type);

	return $number unless $format-data;

	return $self->-process-algorithmic-number-data($number, $format-data);
}

sub -get-algorithmic-number-format-data-by-name {
	my ($self, $format-name, $type) = @-;

	# Some of these algorithmic formats are in locale/type/name format
	if (my ($locale-id, undef, $format) = $format-name =~ m(^(.*?)/(.*?)/(.*?)$)) {
		my $locale = Locale::CLDR->new($locale-id);
		return $locale->-get-algorithmic-number-format-data-by-name($format, $type)
			if $locale;

		return undef;
	}

	$type //= 'public';

	my %data = ();

	my @data-bundles = $self->-find-bundle('algorithmic-number-format-data');
	foreach my $data-bundle (@data-bundles) {
		my $data = $data-bundle->algorithmic-number-format-data();
		next unless $data->{$format-name};
		next unless $data->{$format-name}{$type};

		foreach my $rule (keys %{$data->{$format-name}{$type}}) {
			$data{$rule} = $data->{$format-name}{$type}{$rule};
		}

		last;
	}

	return keys %data ? \%data : undef;
}

sub -get-plural-form {
	my ($self, $plural, $from) = @-;

	my ($result) = $from =~ /$plural\{(.+?)\}/;
	($result) = $from =~ /other\{(.+?)\}/ unless defined $result;

	return $result;
}

sub -process-algorithmic-number-data {
	my ($self, $number, $format-data, $plural, $in-fraction-rule-set) = @-;

	$in-fraction-rule-set //= 0;

	my $format = $self->-get-algorithmic-number-format($number, $format-data);

	my $format-rule = $format->{rule};
	if (! $plural && $format-rule =~ /(cardinal|ordinal)/) {
		my $type = $1;
		$plural = $self->plural($number, $type);
		$plural = [$type, $plural];
	}

	# Sort out plural forms
	if ($plural) {
		$format-rule =~ s/\$\($plural->[0],(.+)\)\$/$self->-get-plural-form($plural->[1],$1)/eg;
	}

	my $divisor = $format->{divisor};
	my $base-value = $format->{base-value} // '';

	# Negative numbers
	if ($number =~ /^-/) {
		my $positive-number = $number;
		$positive-number =~ s/^-//;

		if ($format-rule =~ /→→/) {
			$format-rule =~ s/→→/$self->-process-algorithmic-number-data($positive-number, $format-data, $plural)/e;
		}
		elsif((my $rule-name) = $format-rule =~ /→(.+)→/) {
			my $type = 'public';
			if ($rule-name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
			if($format-data) {
				# was a valid name
				$format-rule =~ s/→(.+)→/$self->-process-algorithmic-number-data($positive-number, $format-data, $plural)/e;
			}
			else {
				# Assume a format
				$format-rule =~ s/→(.+)→/$self->-format-number($positive-number, $1)/e;
			}
		}
		elsif($format-rule =~ /=%%.*=/) {
			$format-rule =~ s/=%%(.*?)=/$self->-algorithmic-number-format($number, $1, 'private')/eg;
		}
		elsif($format-rule =~ /=%.*=/) {
			$format-rule =~ s/=%(.*?)=/$self->-algorithmic-number-format($number, $1, 'public')/eg;
		}
		elsif($format-rule =~ /=.*=/) {
			$format-rule =~ s/=(.*?)=/$self->-format-number($number, $1)/eg;
		}
	}
	# Fractions
	elsif( $number =~ /\./ ) {
		my $in-fraction-rule-set = 1;
		my ($integer, $fraction) = $number =~ /^([^.]*)\.(.*)$/;

		if ($number >= 0 && $number < 1) {
			$format-rule =~ s/\[.*\]//;
		}
		else {
			$format-rule =~ s/[\[\]]//g;
		}

		if ($format-rule =~ /→→/) {
			$format-rule =~ s/→→/$self->-process-algorithmic-number-data-fractions($fraction, $format-data, $plural)/e;
		}
		elsif((my $rule-name) = $format-rule =~ /→(.*)→/) {
			my $type = 'public';
			if ($rule-name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
			if ($format-data) {
				$format-rule =~ s/→(.*)→/$self->-process-algorithmic-number-data-fractions($fraction, $format-data, $plural)/e;
			}
			else {
				$format-rule =~ s/→(.*)→/$self->-format-number($fraction, $1)/e;
			}
		}

		if ($format-rule =~ /←←/) {
			$format-rule =~ s/←←/$self->-process-algorithmic-number-data($integer, $format-data, $plural, $in-fraction-rule-set)/e;
		}
		elsif((my $rule-name) = $format-rule =~ /←(.+)←/) {
			my $type = 'public';
			if ($rule-name =~ s/^%%/%/) {
				$type = 'private';
			}
			my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
			if ($format-data) {
				$format-rule =~ s/←(.*)←/$self->-process-algorithmic-number-data($integer, $format-data, $plural, $in-fraction-rule-set)/e;
			}
			else {
				$format-rule =~ s/←(.*)←/$self->-format-number($integer, $1)/e;
			}
		}

		if($format-rule =~ /=.*=/) {
			if($format-rule =~ /=%%.*=/) {
				$format-rule =~ s/=%%(.*?)=/$self->-algorithmic-number-format($number, $1, 'private')/eg;
			}
			elsif($format-rule =~ /=%.*=/) {
				$format-rule =~ s/=%(.*?)=/$self->-algorithmic-number-format($number, $1, 'public')/eg;
			}
			else {
				$format-rule =~ s/=(.*?)=/$self->-format-number($integer, $1)/eg;
			}
		}
	}

	# Everything else
	else {
		# At this stage we have a non negative integer
		if ($format-rule =~ /\[.*\]/) {
			if ($in-fraction-rule-set && $number * $base-value == 1) {
				$format-rule =~ s/\[.*\]//;
			}
			# Not fractional rule set      Number is a multiple of $divisor and the multiple is even
			elsif (! $in-fraction-rule-set && ! ($number % $divisor) ) {
				$format-rule =~ s/\[.*\]//;
			}
			else {
				$format-rule =~ s/[\[\]]//g;
			}
		}

		if ($in-fraction-rule-set) {
			if (my ($rule-name) = $format-rule =~ /←(.*)←/) {
				if (length $rule-name) {
					my $type = 'public';
					if ($rule-name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
					if ($format-data) {
						$format-rule =~ s/←(.*)←/$self->-process-algorithmic-number-data($number * $base-value, $format-data, $plural, $in-fraction-rule-set)/e;
					}
					else {
						$format-rule =~ s/←(.*)←/$self->-format-number($number * $base-value, $1)/e;
					}
				}
				else {
					$format-rule =~ s/←←/$self->-process-algorithmic-number-data($number * $base-value, $format-data, $plural, $in-fraction-rule-set)/e;
				}
			}
			elsif($format-rule =~ /=.*=/) {
				$format-rule =~ s/=(.*?)=/$self->-format-number($number, $1)/eg;
			}
		}
		else {
			if (my ($rule-name) = $format-rule =~ /→(.*)→/) {
				if (length $rule-name) {
					my $type = 'public';
					if ($rule-name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
					if ($format-data) {
						$format-rule =~ s/→(.+)→/$self->-process-algorithmic-number-data($number % $divisor, $format-data, $plural)/e;
					}
					else {
						$format-rule =~ s/→(.*)→/$self->-format-number($number % $divisor, $1)/e;
					}
				}
				else {
					$format-rule =~ s/→→/$self->-process-algorithmic-number-data($number % $divisor, $format-data, $plural)/e;
				}
			}

			if (my ($rule-name) = $format-rule =~ /←(.*)←/) {
				if (length $rule-name) {
					my $type = 'public';
					if ($rule-name =~ s/^%%/%/) {
						$type = 'private';
					}
					my $format-data = $self->-get-algorithmic-number-format-data-by-name($rule-name, $type);
					if ($format-data) {
						$format-rule =~ s|←(.*)←|$self->-process-algorithmic-number-data(int ($number / $divisor), $format-data, $plural)|e;
					}
					else {
						$format-rule =~ s|←(.*)←|$self->-format-number(int($number / $divisor), $1)|e;
					}
				}
				else {
					$format-rule =~ s|←←|$self->-process-algorithmic-number-data(int($number / $divisor), $format-data, $plural)|e;
				}
			}

			if($format-rule =~ /=.*=/) {
				if($format-rule =~ /=%%.*=/) {
					$format-rule =~ s/=%%(.*?)=/$self->-algorithmic-number-format($number, $1, 'private')/eg;
				}
				elsif($format-rule =~ /=%.*=/) {
					$format-rule =~ s/=%(.*?)=/$self->-algorithmic-number-format($number, $1, 'public')/eg;
				}
				else {
					$format-rule =~ s/=(.*?)=/$self->-format-number($number, $1)/eg;
				}
			}
		}
	}

	return $format-rule;
}

sub -process-algorithmic-number-data-fractions {
	my ($self, $fraction, $format-data, $plural) = @-;

	my $result = '';
	foreach my $digit (split //, $fraction) {
		$result .= $self->-process-algorithmic-number-data($digit, $format-data, $plural, 1);
	}

	return $result;
}

sub -get-algorithmic-number-format {
	my ($self, $number, $format-data) = @-;

	use bignum;
	return $format-data->{'-x'} if $number =~ /^-/ && exists $format-data->{'-x'};
	return $format-data->{'x.x'} if $number =~ /\./ && exists $format-data->{'x.x'};
	return $format-data->{0} if $number == 0 || $number =~ /^-/;
	return $format-data->{max} if $number >= $format-data->{max}{base-value};

	my $previous = 0;
	foreach my $key (sort { $a <=> $b } grep /^[0-9]+$/, keys %$format-data) {
		next if $key == 0;
		return $format-data->{$key} if $number == $key;
		return $format-data->{$previous} if $number < $key;
		$previous = $key;
	}
}

no Moo::Role;

1;

# vim: tabstop=4
--DATA--
#line 6538
use Unicode::Normalize('NFD');
use Unicode::UCD qw( charinfo );
use List::MoreUtils qw(pairwise);
use Moo;
use Types::Standard qw(Str Int Maybe ArrayRef InstanceOf RegexpRef Bool);
with 'Locale::CLDR::CollatorBase';

my $NUMBER-SORT-TOP = "\x{FD00}\x{0034}";
my $LEVEL-SEPARATOR = "\x{0001}";

has 'type' => (
	is => 'ro',
	isa => Str,
	default => 'standard',
);

has 'locale' => (
	is => 'ro',
	isa => Maybe[InstanceOf['Locale::CLDR']],
	default => undef,
	predicate => 'has-locale',
);

has 'alternate' => (
	is => 'ro',
	isa => Str,
	default => 'noignore'
);

# Note that backwards is only at level 2
has 'backwards' => (
	is => 'ro',
	isa => Str,
	default => 'false',
);

has 'case-level' => (
	is => 'ro',
	isa => Str,
	default => 'false',
);

has 'case-ordering' => (
	is => 'ro',
	isa => Str,
	default => 'false',
);

has 'normalization' => (
	is => 'ro',
	isa => Str,
	default => 'true',
);

has 'numeric' => (
	is => 'ro',
	isa => Str,
	default => 'false',
);

has 'reorder' => (
	is => 'ro',
	isa => ArrayRef,
	default => sub { [] },
);

has 'strength' => (
	is => 'ro',
	isa => Int,
	default => 3,
);

has 'max-variable' => (
	is => 'ro',
	isa => Str,
	default => chr(0x0397),
);

has -character-rx => (
	is => 'ro',
	isa => RegexpRef,
	lazy => 1,
	init-arg => undef,
	default => sub {
		my $self = shift;
		my $list = join '|', @{$self->multi-rx()}, '.';
		return qr/\G($list)/s;
	},
);

has -in-variable-weigting => (
	is => 'rw',
	isa => Bool,
	init-arg => undef,
	default => 0,
);

# Set up the locale overrides
sub BUILD {
	my $self = shift;

	my $overrides = [];
	if ($self->has-locale) {
		$overrides = $self->locale->-collation-overrides($self->type);
	}

	foreach my $override (@$overrides) {
		$self->-set-ce(@$override);
	}
}

# Get the collation element at the current strength
sub get-collation-elements {
	my ($self, $string) = @-;
	my @ce;
	if ($self->numeric eq 'true' && $string =~/^\p{Nd}^/) {
		my $numeric-top = $self->collation-elements()->{$NUMBER-SORT-TOP};
		my @numbers = $self->-convert-digits-to-numbers($string);
		@ce = map { "$numeric-top${LEVEL-SEPARATOR}№$-" } @numbers;
	}
	else {
		my $rx = $self->-character-rx;
		my @characters = $string =~ /$rx/g;

		foreach my $character (@characters) {
			my @current-ce;
			if (length $character > 1) {
				# We have a collation element that dependeds on two or more codepoints
				# Remove the code points that the collation element depends on and if
				# there are still codepoints get the collation elements for them
				my @multi-rx = @{$self->multi-rx};
				my $multi;
				for (my $count = 0; $count < @multi-rx; $count++) {
					if ($character =~ /$multi-rx[$count]/) {
						$multi = $self->multi-class()->[$count];
						last;
					}
				}

				my $match = $character;
				eval "\$match =~ tr/$multi//cd;";
				push @current-ce, $self->collation-elements()->{$match};
				$character =~ s/$multi//g;
				if (length $character) {
					foreach my $codepoint (split //, $character) {
						push @current-ce,
							$self->collation-elements()->{$codepoint}
							// $self->generate-ce($codepoint);
					}
				}
			}
			else {
				my $ce = $self->collation-elements()->{$character};
				$ce //= $self->generate-ce($character);
				push @current-ce, $ce;
			}
			push @ce, $self->-process-variable-weightings(@current-ce);
		}
	}
	return @ce;
}

sub -process-variable-weightings {
	my ($self, @ce) = @-;
	return @ce if $self->alternate() eq 'noignore';

	foreach my $ce (@ce) {
		if ($ce->[0] le $self->max-variable) {
			# Variable waighted codepoint
			if ($self->alternate eq 'blanked') {
				@$ce = map { chr() } qw(0 0 0);

			}
			if ($self->alternate eq 'shifted') {
				my $l4;
				if ($ce->[0] eq "\0" && $ce->[1] eq "\0" && $ce->[2] eq "\0") {
					$ce->[3] = "\0";
				}
				else {
					$ce->[3] = $ce->[1];
				}
				@$ce[0 .. 2] = map { chr() } qw (0 0 0);
			}
			$self->-in-variable-weigting(1);
		}
		else {
			if ($self->-in-variable-weigting()) {
				if( $ce->[0] eq "\0" && $self->alternate eq 'shifted' ) {
					$ce->[3] = "\0";
				}
				elsif($ce->[0] ne "\0") {
					$self->-in-variable-weigting(0);
					if ( $self->alternate eq 'shifted' ) {
						$ce->[3] = chr(0xFFFF)
					}
				}
			}
		}
	}
}

# Converts $string into a sort key. Two sort keys can be correctly sorted by cmp
sub getSortKey {
	my ($self, $string) = @-;

	$string = NFD($string) if $self->normalization eq 'true';

	my @sort-key;

	my @ce = $self->get-collation-elements($string);

	for (my $count = 0; $count < $self->strength(); $count++ ) {
		foreach my $ce (@ce) {
			$ce = [ split //, $ce] unless ref $ce;
			if (defined $ce->[$count] && $ce->[$count] ne "\0") {
				push @sort-key, $ce->[$count];
			}
		}
	}

	return join "\0", @sort-key;
}

sub generate-ce {
	my ($self, $character) = @-;

	my $aaaa;
	my $bbbb;

	if ($^V ge v5.26 && eval q($character =~ /(?!\p{Cn})(?:\p{Block=Tangut}|\p{Block=Tangut-Components})/)) {
		$aaaa = 0xFB00;
		$bbbb = (ord($character) - 0x17000) | 0x8000;
	}
	# Block Nushu was added in Perl 5.28
	elsif ($^V ge v5.28 && eval q($character =~ /(?!\p{Cn})\p{Block=Nushu}/)) {
		$aaaa = 0xFB01;
		$bbbb = (ord($character) - 0x1B170) | 0x8000;
	}
	elsif ($character =~ /(?=\p{Unified-Ideograph=True})(?:\p{Block=CJK-Unified-Ideographs}|\p{Block=CJK-Compatibility-Ideographs})/) {
		$aaaa = 0xFB40 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	elsif ($character =~ /(?=\p{Unified-Ideograph=True})(?!\p{Block=CJK-Unified-Ideographs})(?!\p{Block=CJK-Compatibility-Ideographs})/) {
		$aaaa = 0xFB80 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	else {
		$aaaa = 0xFBC0 + (ord($character) >> 15);
		$bbbb = (ord($character) & 0x7FFFF) | 0x8000;
	}
	return join '', map {chr($-)} $aaaa, 0x0020, 0x0002, ord($LEVEL-SEPARATOR), $bbbb, 0, 0;
}

# sorts a list according to the locales collation rules
sub sort {
	my $self = shift;

	return map { $-->[0]}
		sort { $a->[1] cmp $b->[1] }
		map { [$-, $self->getSortKey($-)] }
		@-;
}

sub cmp {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) cmp $self->getSortKey($b);
}

sub eq {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) eq $self->getSortKey($b);
}

sub ne {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) ne $self->getSortKey($b);
}

sub lt {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) lt $self->getSortKey($b);
}

sub le {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) le $self->getSortKey($b);
}
sub gt {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) gt $self->getSortKey($b);
}

sub ge {
	my ($self, $a, $b) = @-;

	return $self->getSortKey($a) ge $self->getSortKey($b);
}

# Get Human readable sort key
sub viewSortKey {
	my ($self, $sort-key) = @-;

	my @levels = split/\x0/, $sort-key;

	foreach my $level (@levels) {
		$level = join ' ',  map { sprintf '%0.4X', ord } split //, $level;
	}

	return '[ ' . join (' | ', @levels) . ' ]';
}

sub -convert-digits-to-numbers {
	my ($self, $digits) = @-;
	my @numbers = ();
	my $script = '';
	foreach my $number (split //, $digits) {
		my $char-info = charinfo(ord($number));
		my ($decimal, $chr-script) = @{$char-info}{qw( decimal script )};
		if ($chr-script eq $script) {
			$numbers[-1] *= 10;
			$numbers[-1] += $decimal;
		}
		else {
			push @numbers, $decimal;
			$script = $chr-script;
		}
	}
	return @numbers;
}
