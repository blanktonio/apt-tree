
# apt-tree.sh

Prints package dependency tree or flattened recursive list.

Syntax:

```shell
apt-tree.sh [-hlnrRvV] [-p|t|T STR] [-i IN] [-o OUT] [PACKAGE...]
```

Void options:

* **-h** — Show this help page.
* **-l** — Print flattened list (rather than a tree).
* **-n** — Print number of direct dependencies.
* **-r** — Use reverse dependencies.
* **-R** — Do not repeat sub-trees already printed before.
* **-v** — Increase verbosity level.
* **-V** — Print program name and version.

Scalar options:

* **-i** _LISTFILE_ — Read package list from file.
* **-o** _TREEFILE_ — Output tree (or flattened list) to file.
* **-p** _PREFIX_ — Indentation prefix for list and tree items (default: empty).
* **-t** _INDENT_ — Indentation string for each tree level (default: tab).
* **-T** _SUFFIX_ — Indentation suffix for tree items (default: empty).


## Examples

Print dependency tree for a package:

```
$ apt-tree.sh bash
bash
	glibc
```

Print flattened recursive list of dependencies for multiple packages:

```
$ apt-tree.sh -l libxau libxcb
check
libpthread-stubs
libxau
libxcb
libxdmcp
util-macros
xcb-proto
xproto
```

Print dependency tree for multiple packages, showing their dependency count:

```
$ apt-tree.sh -n gpm libssh2 libxdmcp
gpm (2)
	chkconfig (1)
		insserv (0)
	ncurses (0)
libssh2 (2)
	libressl (0)
	zlib (0)
libxdmcp (2)
	util-macros (0)
	xproto (1)
		util-macros (0)
```

Print reverse dependency tree:

```
$ apt-tree.sh -r xinit
xinit
	meta-desktop
	meta-tablet
	xfce4-session
		meta-desktop
```

Suppress printing of repeating sub-trees (already printed before);
note how circular dependencies and absent packages are labeled:

```
$ apt-tree.sh -R udev non-existing-package
non-existing-package (missing!)
udev
	chkconfig
		insserv
	usbutils
		libusb
			glibc
			udev (loop!)
		libusb-compat
			libusb (repeating)
		zlib
```

Redecorate a tree:

```
$ apt-tree.sh -p '| ' -t '  ' -T '+ ' coreutils
| + coreutils
|   + acl
|     + attr
|   + attr
|   + gmp
|     + ncurses
```


## System requirements

This shell script is written for `bash` 4.0 as a minimum version,
and is actively tested against version 5.0 and newer ones.

This script relies on `apt-cache` as the actual workhorse
to retrieve package metadata.

Other external dependencies include `sort` from **coreutils**
and, optionally, `tput` from **ncurses** (used under certain conditions only).
