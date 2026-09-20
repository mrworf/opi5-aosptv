#!/usr/bin/env python3
"""Validate an executable U-Boot legacy script image and its boot policy."""

import argparse
import struct
import sys
import zlib
from pathlib import Path


HEADER = struct.Struct(">7I4B32s")
UIMAGE_MAGIC = 0x27051956
UIMAGE_TYPE_SCRIPT = 6
PERMISSIVE_ARG = "androidboot.selinux=permissive"


def fail(message: str) -> None:
    raise ValueError(message)


def read_image(path: str) -> bytes:
    return sys.stdin.buffer.read() if path == "-" else Path(path).read_bytes()


def verify(image: bytes, variant: str) -> None:
    if len(image) < HEADER.size + 8:
        fail("truncated U-Boot script image")

    fields = HEADER.unpack_from(image)
    magic, header_crc, _timestamp, data_size, _load, _entry, data_crc = fields[:7]
    _os, _arch, image_type, _compression = fields[7:11]
    if magic != UIMAGE_MAGIC:
        fail("invalid U-Boot legacy-image magic")
    if image_type != UIMAGE_TYPE_SCRIPT:
        fail(f"expected script image type {UIMAGE_TYPE_SCRIPT}, found {image_type}")

    zero_crc_header = bytearray(image[: HEADER.size])
    zero_crc_header[4:8] = b"\0" * 4
    if zlib.crc32(zero_crc_header) != header_crc:
        fail("invalid U-Boot header CRC")

    data = image[HEADER.size :]
    if len(data) != data_size:
        fail(f"header declares {data_size} data bytes, found {len(data)}")
    if zlib.crc32(data) != data_crc:
        fail("invalid U-Boot data CRC")

    offset = 0
    lengths: list[int] = []
    while offset + 4 <= len(data):
        (length,) = struct.unpack_from(">I", data, offset)
        offset += 4
        if length == 0:
            break
        lengths.append(length)
    else:
        fail("script length table has no terminator")
    if len(lengths) != 1:
        fail(f"expected exactly one script, found {len(lengths)}")
    if sum(lengths) != len(data) - offset:
        fail("script length table does not describe the image payload")

    try:
        script = data[offset:].decode("utf-8")
    except UnicodeDecodeError as error:
        fail(f"script is not UTF-8: {error}")
    if "booti " not in script:
        fail("script has no booti command")
    if sum(line.strip().startswith("if ") for line in script.splitlines()) != sum(
        line.strip().rstrip(";") == "fi" for line in script.splitlines()
    ):
        fail("script has unbalanced if/fi commands")
    if variant == "user" and PERMISSIVE_ARG in script:
        fail("user boot script requests permissive SELinux")
    if variant == "userdebug" and PERMISSIVE_ARG not in script:
        fail("userdebug boot script lacks permissive SELinux")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--variant", choices=("user", "userdebug"), required=True)
    args = parser.parse_args()
    verify(read_image(args.input), args.variant)


if __name__ == "__main__":
    main()
