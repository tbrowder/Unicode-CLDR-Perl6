#!perl
use strict;
use warnings;

use Test::More tests => 28;
use Test::Exception;

use ok 'Locale::CLDR';

my $locale = Locale::CLDR->new(language => 'en');
is("$locale", 'en', 'Set Language explicitly');

$locale = Locale::CLDR->new('en');
is("$locale", 'en', 'Set Language implicitly');

$locale = Locale::CLDR->new(language => 'en', territory => 'gb');
is("$locale", 'en_GB', 'Set Language and Territory explicitly');

$locale = Locale::CLDR->new('en-gb');
is("$locale", 'en_GB', 'Set Language and Territory implicitly');

$locale = Locale::CLDR->new(language => 'en', script => 'latn');
is("$locale", 'en_Latn', 'Set Language and Script explicitly');

$locale = Locale::CLDR->new('en-latn');
is("$locale", 'en_Latn', 'Set Language and Script implicitly');

$locale = Locale::CLDR->new(language => 'en', territory => 'gb', script => 'latn');
is("$locale", 'en_Latn_GB', 'Set Language, Territory and Script explicitly');

$locale = Locale::CLDR->new('en-latn-gb');
is("$locale", 'en_Latn_GB', 'Set Language, Territory and Script implicitly');

$locale = Locale::CLDR->new(language => 'en', variant => 'BOKMAL');
is("$locale", 'en_BOKMAL', 'Set Language and Variant from string explicitly');

$locale = Locale::CLDR->new('en_BOKMAL');
is("$locale", 'en_BOKMAL', 'Set Language and variant implicitly');

$locale = Locale::CLDR->new('en_latn_gb_BOKMAL');
is("$locale", 'en_Latn_GB_BOKMAL', 'Set Language, Territory, Script and variant implicitly');

throws_ok { $locale = Locale::CLDR->new('wibble') } qr/Invalid language/, "Caught invalid language";
throws_ok { $locale = Locale::CLDR->new('en_wi') } qr/Invalid territory/, "Caught invalid territory";
throws_ok { $locale = Locale::CLDR->new('en_wibb') } qr/Invalid script/, "Caught invalid script";

$locale = Locale::CLDR->new('en');
is ($locale->locale_name('fr'), 'French', 'Name without territory');
is ($locale->locale_name('fr_CA'), 'Canadian French', 'Name with known territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Name with unknown territory') ;
is ($locale->locale_name('fr_BE'), 'French (Belgium)', 'Cached method') ;
$locale = Locale::CLDR->new('en');
is ($locale->language_name, 'English', 'Language name');
is ($locale->language_name('wibble'), 'Unknown or Invalid Language', 'Unknown Language name');
is ($locale->script_name('Cher'), 'Cherokee', 'Script name');
is ($locale->script_name('wibl'), 'Unknown or Invalid Script', 'Invalid Script name');
is ($locale->territory_name('GB'), 'United Kingdom', 'Territory name');
is ($locale->territory_name('wibble'), 'Unknown or Invalid Region', 'Invalid Territory name');
is ($locale->variant_name('AREVMDA'), 'Western Armenian', 'Variant name');
is ($locale->variant_name('WIBBLE'), '', 'Invalid Variant name');
is ($locale->language_name('i-klingon'), 'Klingon', 'Language alias');
