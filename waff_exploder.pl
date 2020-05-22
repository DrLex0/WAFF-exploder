#!/usr/bin/perl
# Expands MSIE (Macintosh Internet Explorer) web archive files (WAFF format).
#
# BSD 2-Clause License
#
# Copyright (c) 2020, Alexander Thomas
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_CUR);
use File::Path qw(make_path);

my $VERSION = '0.1';
my $verbose = 0;

sub usage()
{
	print "Usage: $0 [-v] inputFile [inputFile2 ..]\n".
	      "Expands MSIE (Macintosh Internet Explorer) web archive files (WAFF format).\n".
	      "Version: ${VERSION}\n".
	      "  -v enables verbose output.\n";
}

while($#ARGV > -1 && substr($ARGV[0], 0, 1) eq '-') {
	if($ARGV[0] eq '--') {
		shift;
		last;
	}
	foreach my $opt (split('', substr($ARGV[0], 1))) {
		if($opt eq 'v') {
			$verbose = 1;
		}
		elsif($opt eq 'h') {
			usage();
			exit();
		}
		else {
			print STDERR "Warning: ignoring unknown option '${opt}'\n";
		}
	}
	shift;
}

if($#ARGV < 0) {
	usage();
	exit(2);
}


while(my $inFile = shift) {
	my $dirName = $inFile;
	$dirName =~ s|^.*/||;
	$dirName =~ s/\.[^.]+$//;
	my $give_up = 5;
	while(-e $dirName && $give_up > 0) {
		$dirName .= '_';
		$give_up-- if(-e $dirName);
	}
	if($give_up <= 0) {
		print STDERR "ERROR: too many existing files or directories with a name similar to '${dirName}', skipping it\n";
		next;
	}

	print "Exploding ${inFile} to ${dirName}...\n" if($verbose);
	open(my $fHandle, '<', $inFile) or die "ERROR: cannot read file '${inFile}': $!\n";

	my $bits32;
	read($fHandle, $bits32, 4);
	if($bits32 ne '.WAF') {
		close($fHandle);
		print STDERR "ERROR: ${inFile} is not a .WAF file, skipping\n";
		next;
	}

	read($fHandle, $bits32, 4);
	my $length = unpack('N', $bits32);
	print "Header length: ${length}\n" if($verbose);
	seek($fHandle, $length, SEEK_SET);

	mkdir($dirName);
	while(1) {
		# === 'ntry' section ===
		read($fHandle, $bits32, 4);
		if($bits32 eq 'cat ') {
			close($fHandle);
			print "'cat ' chunk reached, considering it end of file\n" if($verbose);
			last;
		}
		elsif($bits32 ne 'ntry') {
			close($fHandle);
			print STDERR "ERROR: unexpected chunk in ${inFile} instead of expected 'ntry'\n";
			last;
		}
		read($fHandle, $bits32, 4);
		$length = unpack('N', $bits32);
		print "INFO: 'ntry' header of unexpected length, things may go haywire: ${length}\n" if($verbose && $length != 0x28);
		seek($fHandle, 0x20, SEEK_CUR);
		read($fHandle, $bits32, 4);
		my $dataLength = unpack('N', $bits32) - $length - 0x58;

		# === fields section ===
		my $url;
		read($fHandle, $bits32, 4);
		my $fieldsLength = unpack('N', $bits32);
		print "Fields length: ${fieldsLength}\n" if($verbose);
		my $fieldsIndex = 0;
		while($fieldsIndex < $fieldsLength) {
			my $fieldName;
			read($fHandle, $fieldName, 4);
			read($fHandle, $bits32, 4);
			$length = unpack('N', $bits32);
			print "Field '${fieldName}' of length ${length}\n" if($verbose);
			my $fieldData;
			read($fHandle, $fieldData, $length);
			# Beware of null-terminated strings
			$fieldData =~ s/\0$//;
			$url = $fieldData if($fieldName eq 'url ');
			$fieldsIndex += 8 + $length;
		}
		if(! $url) {
			print STDERR "ERROR: no URL found for entry, skipping it\n";
		}
		else {
			print "URL: ${url}\n" if($verbose);
		}

		# === data section ===
		$dataLength -= $fieldsLength;
		print "Data length: ${dataLength}\n" if($verbose);
		read($fHandle, $bits32, 4);
		if($bits32 ne 'data') {
			close($fHandle);
			print STDERR "ERROR: 'data' chunk not in expected position in ${inFile}, aborting\n";
			last;
		}
		read($fHandle, $bits32, 4);
		$length = unpack('N', $bits32);
		if($length) {
			print STDERR "WARNING: number after 'data' is not zero, don't know what to do with this, things may go awry\n";
		}
		my $remaining = $dataLength;
		my $buffer;
		my $writeHandle;
		if($url) {
			# FIXME: proper path handling!!!
			# Also beware of # anchors: they must be stripped
			# It may be wise to convert '?' and '&' signs to something else
			my @path = url_to_path($url);
			my $fileName = $path[-1];
			my $dir = join('/', @path[0 .. $#path - 1]);
			my $full_dir = "${dirName}/${dir}";
			make_path($full_dir);
			if(! -d $full_dir) {
				print STDERR "ERROR: failed to create directory ${dirName}/${dir}\n";
				exit(1);
			}
			my $filePath = "${dirName}/${dir}/${fileName}";

			print "Creating: ${filePath}\n";
			open($writeHandle, '>', $filePath) or die "FATAL: cannot write to '${filePath}'\n";
		}
		while($remaining) {
			my $bufSize = $remaining > 16384 ? 16384 : $remaining;
			my $read = read($fHandle, $buffer, $bufSize);
			print $writeHandle $buffer if($url);
			if($read < $bufSize) {
				print STDERR "ERROR: unexpected end of file in ${inFile}, result will be incomplete\n";
				close($writeHandle);
				close($fHandle);
				last;
			}
			$remaining -= $read;
		}
		close($writeHandle) if($url);

		# === remaining crap ===
		read($fHandle, $bits32, 4);
		if($bits32 ne 'post') {
			close($fHandle);
			print STDERR "ERROR: 'post' chunk not in expected position in ${inFile}, aborting\n";
			last;
		}
		read($fHandle, $bits32, 4);
		$length = unpack('N', $bits32);
		print "INFO: 'post' chunk of unexpected length in ${inFile}\n" if($verbose && $length != 4);
		seek($fHandle, $length, SEEK_CUR);
		# Now we should be skipping 0x80 (128) 'X' bytes. I guess at some moment
		# in history someone at Microsoft knew what was the point of this.
		seek($fHandle, 0x80, SEEK_CUR);
		read($fHandle, $bits32, 4);
		if($bits32 ne 'cate') {
			close($fHandle);
			print STDERR "ERROR: 'cate' chunk not in expected position in ${inFile}, aborting\n";
			last;
		}
		read($fHandle, $bits32, 4);
		$length = unpack('N', $bits32);
		print "INFO: 'cate' chunk of unexpected length in ${inFile}\n" if($verbose && $length != 0x20);
		seek($fHandle, $length, SEEK_CUR);
	}
	close($fHandle);
}


sub url_to_path
# Generates local file path from URL.
{
	# TODO? Should we consider ../ path components?
	my ($url, $baseUrl) = @_;
	$url =~ s|^https?://||;
	$url =~ s/#.*//;
	my @path = split('/', $url);
	push(@path, 'index.html') if($url =~ m|/$|);
	return @path;
}