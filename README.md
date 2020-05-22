# WAFF Exploder: MSIE Web Archive expander

![Icon](icon.png)

## About

There used to be a time when there was a Mac OS version of Internet Explorer and at some point it was even considered the standard browser. If you are a long-time Mac OS user, perhaps you actually used that browser, and maybe you saved some ‘Web Archives’ in it. If you still have such archives and want to open them, you are pretty much forced to somehow run either the old Internet Explorer, or extract their contents. There used to be a Mac OS Classic application called ‘WebArchivConverter’ that could extract the contents from those files, but running that app is at least as cumbersome as running IE itself. That's where this script comes in: it is a plain Perl script that will run in any OS with a Perl interpreter. It may also produce better results than WebArchivConverter.

The archives that can be extracted by this script, used to have a Mac OS creator code `MSIE` and file type `WAFF`. The files start with the 4 bytes “`.WAF`”. Anything else cannot be extracted.


## Using

Simply run the script in a terminal with the file(s) as arguments. It will create folders with the same name as the file sans extension. If something already exists with that name, it will append `_` until the name is unique. A list of expanded files will be printed to the console, usually the first one is also the entry point that you can open in any browser to view the archive.

Some attempts have been done to make the expanded archive usable without too much fuss. Paths inside files will be transformed to relative paths such that in theory the archive can be simply opened without editing. In practice this isn't perfect. If there is too much junk in JavaScripts, things may be broken. You might also be pestered by JavaScripts that try to do stupid things like sending you back to a main page because it appears like you're not in a frameset. Some manual hacking may therefore be needed on the expanded files to make them usable.

Your mileage may vary, this is mostly a quick-n-dirty implementation that does the job. I had some ideas to make it better, but the motivation to work on this is very low, especially now that I have already expanded practically all my old archives. This is why I have put this on GitHub: you can fork this project and add your own improvements. Pull requests are welcome.


## License

This is released under a BSD-2-Clause a.k.a. Simplified BSD License. See the LICENSE file for details.

