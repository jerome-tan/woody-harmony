Woody uses dynamically linked, unmodified Qt 6.12.0 libraries under LGPL v3.
Woody itself retains the repository's MIT license. No Qt WebEngine, Qt Charts,
or Qt Graphs is included. The included LGPL-3.0-only.txt and GPL-3.0-only.txt
are the upstream Qt license texts.

The corresponding Qt source is available at:
https://download.qt.io/official_releases/qt/6.12/6.12.0/submodules/

Runtime modules used by this application are from qtbase, qtdeclarative,
qtshadertools, qtsvg, and qttranslations. Module source archives are named
<module>-everywhere-src-6.12.0.tar.xz in that directory. Qt third-party notices
are available in the source archives and at https://doc.qt.io/qt-6/licenses-used-in-qt.html.

Qt libraries remain separate DLLs/frameworks and may be replaced with compatible
modified builds. On macOS, replacing a library invalidates the ad-hoc signature;
re-sign the modified bundle locally using `codesign --force --deep --sign - Woody.app`.
Reverse engineering for debugging modifications to LGPL libraries is permitted.

Application source and build instructions:
https://github.com/jerome-tan/woody-harmony/tree/codex/qt-6.12.0/qt
