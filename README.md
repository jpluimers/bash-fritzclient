# bash shell scripts to act as a Fritz!Box client 

This is meant as a bare bones set of scripts to help me communicating with my own Fritz!Box. If they are useful for others: great!

When not: There are much more fancy clients in other languages, like these:

- PHP (last update 2013-11): <https://github.com/nihunde/FritzClient>
- C++ (last update 2015-03): <https://github.com/jowi24/kfritz>
- C++ (last update 2015-01): <https://github.com/jowi24/vdr-fritz>
- Python (last update: 2014-02): <https://github.com/exhuma/fritzclient>
- Python (last update: 2015-02): <https://github.com/geier/frytz>
- Perl (last update: 2014-05}: <https://github.com/rhuss/aha>
- C++ (lastupdate 2014-02): <https://github.com/jowi24/libfritzpp>

Note: the dates are at the time of writing this.

Base repository is at <https://github.com/jpluimers/bash-fritzclient.git>

Ensure there is a `bash-fritzclient.config` in the parent directory. You can copy it from `bash-fritzclient.config.template`.

Commands supported:

- `reboot`: reboots your Fritz!Box by first sending a POST request followed by an AJAX get request.
- `get-config`: downloads the Fritz!Box configuration.

Both perform authentication to the Fritz!Box with the [infamous MD5 challenge protocol](http://avm.de/fileadmin/user_upload/Global/Service/Schnittstellen/AVM_Technical_Note_-_Session_ID.pdf). For that I reused quite some code from <https://home.debian-hell.org/dokuwiki/scripts/fritzbox.backup.mit.curl.bash> after doing some badly needed cleanup.

Note: the PDF has moved around over time, so if the link is broken, search for `AVM_Technical_Note_-_Session_ID.pdf`.

