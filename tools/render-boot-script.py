#!/usr/bin/env python3
"""Render the variant-specific Orange Pi U-Boot script image."""

import argparse
import os
import struct
import zlib
from pathlib import Path


UIMAGE_MAGIC = 0x27051956
UIMAGE_OS_LINUX = 5
UIMAGE_ARCH_ARM = 2
UIMAGE_TYPE_SCRIPT = 6
UIMAGE_COMP_NONE = 0
PERMISSIVE_ARG = " androidboot.selinux=permissive"


def render_payload(source: str, variant: str) -> bytes:
    count = source.count(PERMISSIVE_ARG)
    if count != 1:
        raise ValueError(
            f"expected exactly one {PERMISSIVE_ARG.strip()!r} in boot command; found {count}"
        )
    if variant == "user":
        source = source.replace(PERMISSIVE_ARG, "")
    elif variant != "userdebug":
        raise ValueError(f"unsupported build variant: {variant}")
    return source.encode("utf-8")


def uimage(payload: bytes) -> bytes:
    timestamp = int(os.environ.get("SOURCE_DATE_EPOCH", "0"))
    name = b"Orange Pi 5 Android boot".ljust(32, b"\0")
    fields = (
        UIMAGE_MAGIC,
        0,
        timestamp,
        len(payload),
        0,
        0,
        zlib.crc32(payload),
        UIMAGE_OS_LINUX,
        UIMAGE_ARCH_ARM,
        UIMAGE_TYPE_SCRIPT,
        UIMAGE_COMP_NONE,
        name,
    )
    header = struct.pack(">7I4B32s", *fields)
    fields = (fields[0], zlib.crc32(header), *fields[2:])
    return struct.pack(">7I4B32s", *fields) + payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--variant", choices=("user", "userdebug"), required=True)
    args = parser.parse_args()

    payload = render_payload(args.input.read_text(encoding="utf-8"), args.variant)
    args.output.write_bytes(uimage(payload))


if __name__ == "__main__":
    main()
