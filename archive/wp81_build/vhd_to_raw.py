#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Конвертер динамического VHD -> разреженный (sparse) raw-образ.

Формат VHD big-endian. Пишем только аллоцированные блоки, дыры остаются
sparse, чтобы 10-гигабайтный диск занял ~1,6 ГБ. Затем печатаем GPT.

Использование: python3 vhd_to_raw.py <input.vhd> <output.raw>
"""
import struct
import sys

SECTOR = 512


def main(src, dst):
    with open(src, 'rb') as f:
        footer = f.read(512)
        if footer[:8] != b'conectix':
            print('Не динамический VHD:', footer[:8])
            sys.exit(1)
        disk_size = struct.unpack_from('>Q', footer, 40)[0]  # CurrentSize

        f.seek(512)
        ddh = f.read(1024)
        table_offset = struct.unpack_from('>Q', ddh, 16)[0]
        max_entries, block_size = struct.unpack_from('>II', ddh, 28)
        print(f'Диск {disk_size} байт; BAT @ {table_offset}; '
              f'блоков {max_entries} по {block_size} байт')
        f.seek(table_offset)
        bat = struct.unpack(f'>{max_entries}I', f.read(max_entries * 4))
        bitmap_bytes = ((block_size // SECTOR) + 7) // 8
        bitmap_bytes = ((bitmap_bytes + SECTOR - 1) // SECTOR) * SECTOR

        out = open(dst, 'wb')
        allocated = 0
        for i, entry in enumerate(bat):
            if entry == 0xFFFFFFFF:
                continue
            f.seek(entry * SECTOR)
            f.read(bitmap_bytes)          # секторная битовая карта блока
            data = f.read(block_size)
            out.seek(i * block_size)
            out.write(data)
            allocated += 1
        out.truncate(disk_size)
        out.close()
        print(f'raw готов (sparse): аллоцировано {allocated} блоков')

    # GPT
    with open(dst, 'rb') as g:
        g.seek(512)
        hdr = g.read(92)
        if hdr[:8] != b'EFI PART':
            print('GPT не найден!')
            sys.exit(1)
        part_entry_lba = struct.unpack_from('>Q', hdr, 72)[0]
        num_entries = struct.unpack_from('>I', hdr, 80)[0]
        entry_size = struct.unpack_from('>I', hdr, 84)[0]
        print(f'GPT: {num_entries} записей по {entry_size} байт, с LBA {part_entry_lba}')
        g.seek(part_entry_lba * 512)
        for i in range(num_entries):
            e = g.read(entry_size)
            if len(e) < entry_size:
                break
            if e[:16] == b'\x00' * 16:
                continue
            first_lba, last_lba = struct.unpack_from('>QQ', e, 32)
            name = e[56:128].decode('utf-16-le').rstrip('\x00')
            gb = (last_lba - first_lba + 1) * 512 / (1024 ** 3)
            print(f'  [{i}] {name:24s} LBA {first_lba:>9}..{last_lba:>9}  '
                  f'{gb:6.2f} ГБ  byte-offset {first_lba * 512}')


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
