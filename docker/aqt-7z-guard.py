# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Simorg
#
# Loaded into every Python that aqt's virtual environment starts, through a .pth
# file (docker/Dockerfile.linux-build), so that aqt's download workers, which it
# spawns as fresh interpreters, have it too.
#
# aqt 3.3.0 asks zipfile.is_zipfile() about each downloaded archive before it
# hands it to py7zr, and before Python 3.14 is_zipfile() says yes to any file
# with a zip end-of-directory record somewhere near its end. Qt 6.11.2's arm64
# qttools archive is a 7z with such bytes inside it, so on Ubuntu 24.04's Python
# 3.12 aqt opened it as a zip and stopped with "Bad offset for central
# directory". A file that starts with the 7z signature is not a zip.

import zipfile

_SEVEN_ZIP_SIGNATURE = b"7z\xbc\xaf\x27\x1c"
_is_zipfile = zipfile.is_zipfile


def _is_zipfile_unless_7z(filename):
    try:
        with open(filename, "rb") as archive:
            if archive.read(len(_SEVEN_ZIP_SIGNATURE)) == _SEVEN_ZIP_SIGNATURE:
                return False
    except (OSError, TypeError):
        pass
    return _is_zipfile(filename)


zipfile.is_zipfile = _is_zipfile_unless_7z
