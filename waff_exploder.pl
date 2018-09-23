#!/usr/bin/perl
# Expands MSIE (Macintosh Internet Explorer) web archive files (WAFF format).

use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_CUR);
use File::Path qw(make_path);

my $bVerbose = 1;

die "Usage: $0 inputFile [..]\n" if($#ARGV < 0);

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

	print "Exploding ${inFile} to ${dirName}...\n" if($bVerbose);
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
	print "Header length: ${length}\n" if($bVerbose);
	seek($fHandle, $length, SEEK_SET);

	mkdir($dirName);
	while(1) {
		# === 'ntry' section ===
		read($fHandle, $bits32, 4);
		if($bits32 eq 'cat ') {
			close($fHandle);
			print "'cat ' chunk reached, considering it end of file\n" if($bVerbose);
			last;
		}
		elsif($bits32 ne 'ntry') {
			close($fHandle);
			print STDERR "ERROR: unexpected chunk in ${inFile} instead of expected 'ntry'\n";
			last;
		}
		read($fHandle, $bits32, 4);
		$length = unpack('N', $bits32);
		print "INFO: 'ntry' header of unexpected length, things may go haywire: ${length}\n" if($bVerbose && $length != 0x28);
		seek($fHandle, 0x20, SEEK_CUR);
		read($fHandle, $bits32, 4);
		my $dataLength = unpack('N', $bits32) - $length - 0x58;

		# === fields section ===
		my $url;
		read($fHandle, $bits32, 4);
		my $fieldsLength = unpack('N', $bits32);
		print "Fields length: ${fieldsLength}\n" if($bVerbose);
		my $fieldsIndex = 0;
		while($fieldsIndex < $fieldsLength) {
			my $fieldName;
			read($fHandle, $fieldName, 4);
			read($fHandle, $bits32, 4);
			$length = unpack('N', $bits32);
			print "Field '${fieldName}' of length ${length}\n" if($bVerbose);
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
			print "URL: ${url}\n" if($bVerbose);
		}

		# === data section ===
		$dataLength -= $fieldsLength;
		print "Data length: ${dataLength}\n" if($bVerbose);
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

			print "Saving to ${filePath}\n" if($bVerbose);
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
		print "INFO: 'post' chunk of unexpected length in ${inFile}\n" if($bVerbose && $length != 4);
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
		print "INFO: 'cate' chunk of unexpected length in ${inFile}\n" if($bVerbose && $length != 0x20);
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