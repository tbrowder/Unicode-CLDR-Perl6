# App::Perlcldr

Note: This started as a fork of <http://github/ThePilgrim/perlcldr> as
a base to port the Perl 5 code to Perl 6.

It is used to generate the **Locale-CLDR** module and associated data files.

The general overview of the project is to convert the XML of the CLDR
into a large number of small Perl modules that can be loaded from the
main **Local::CLDR** when needed to do what ever localisation is required.

## INSTALLATION

To install this module, run the following command:

	$ zef install App::Perlcldr

## Locale Data

This package comes with the Locale data for **en_US**, other locale
data can be found in the **Locale::CLDR::Locales::\*** distributions

Building from github

The data is built with the **mkcldr.p6** script (in the ./bin
directory) which is use to download the latest CLDR data file and
process the data.

Run the script with the optional -v (verbose) flag and come back in 40
minutes or so and you will have a **Distributions** directory with each
of the language CPAN distributions in it.

In the **lib** directory you will also find a Bundle directory that bundles the
data into regions

## SUPPORT AND DOCUMENTATION

After installing, you can find documentation for this module with the
**perldoc** command.

    perldoc Locale::CLDR

## COPYRIGHT AND LICENCE

Copyright (C) 2019 - Tom Browder
Copyright (C) 2009 - 2014 John Imrie

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.
