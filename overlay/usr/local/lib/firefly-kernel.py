#!/usr/bin/python3
# SPDX-License-Identifier: MIT
"""Produce the raw ARM64 Image used by U-Boot booti from a packaged vmlinuz."""
import argparse
import gzip
import io
from pathlib import Path
import shutil
import struct
import subprocess

ARM64 = b'ARM\x64'


def require(condition, message):
    if not condition:
        raise ValueError(message)


def linux_section(uki):
    # UAPI.5 places the kernel payload in the .linux section of an ARM64 PE.
    require(len(uki) >= 64 and uki[:2] == b'MZ', 'expected an ARM64 Image, gzip, zboot or UKI')
    pe = struct.unpack_from('<I', uki, 60)[0]
    require(64 <= pe <= len(uki) - 24 and uki[pe:pe+4] == b'PE\0\0', 'invalid PE header')
    machine, count, _, _, _, opt_size, _ = struct.unpack_from('<HHIIIHH', uki, pe + 4)
    table = pe + 24 + opt_size
    end = table + 40 * count
    require(machine == 0xaa64 and opt_size >= 2 and end <= len(uki) and
            uki[pe+24:pe+26] == b'\x0b\x02', 'invalid ARM64 PE32+ section table')
    sections = []
    for entry in range(table, end, 40):
        name, size, _, raw_size, offset = struct.unpack_from('<8sIIII', uki, entry)
        if name.rstrip(b'\0') == b'.linux':
            require(0 < size <= raw_size and end <= offset <= len(uki) - raw_size,
                    'invalid UKI Linux section bounds')
            sections.append((offset, size))
    require(len(sections) == 1, 'expected exactly one UKI Linux section')
    offset, size = sections[0]
    return uki[offset:offset+size]


def unpack(data, out):
    if data[:2] == b'MZ' and data[4:8] != b'zimg' and data[56:60] != ARM64:
        data = linux_section(data)
    if data[:8] == b'MZ\0\0zimg':
        # Linux EFI zboot header: offset, length, compression type.
        require(len(data) >= 64, 'truncated EFI zboot header')
        offset, size = struct.unpack_from('<II', data, 8)
        kind = data[24:56].partition(b'\0')[0]
        require(64 <= offset <= len(data) and 0 < size <= len(data) - offset,
                'invalid EFI zboot payload bounds')
        data = data[offset:offset+size]
        if kind == b'zstd':
            require(data[:4] == b'\x28\xb5\x2f\xfd', 'invalid zstd payload magic')
            subprocess.run(['zstd', '-qdc'], input=data, stdout=out, check=True)
            return
        require(kind == b'gzip' and data[:2] == b'\x1f\x8b', 'unsupported EFI zboot compression')
    if data[:2] == b'\x1f\x8b':
        with gzip.GzipFile(fileobj=io.BytesIO(data)) as stream:
            shutil.copyfileobj(stream, out)
    else:
        out.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('kernel', type=Path)
    parser.add_argument('image', type=Path, help='temporary output file')
    args = parser.parse_args()
    try:
        data = args.kernel.read_bytes()
        with args.image.open('w+b') as out:
            unpack(data, out)
            out.seek(56)
            require(out.read(4) == ARM64, 'output is not a raw ARM64 Image')
    except (OSError, ValueError, EOFError, struct.error, subprocess.CalledProcessError) as err:
        parser.exit(1, f'{args.kernel.name}: {err}\n')


if __name__ == '__main__':
    main()
