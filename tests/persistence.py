"""A durable fixture shared by the unit suite and cross-Python wheel checks."""
import argparse
from pathlib import Path
import struct
import sys

import rocksdb
from rocksdb.merge_operators import UintAddOperator


INITIAL_TOTAL = (1 << 63) + 1


def initial_rows():
    rows = {b'': b'', b'\x00\xff': bytes(range(256)), b'remove': b'old value'}
    rows.update({b'row/%04d' % i: bytes(range(256)) * 16 + bytes([i]) for i in range(128)})
    return rows


def open_db(path, create=False, compression='snappy'):
    codec = getattr(rocksdb.CompressionType, compression + '_compression')
    options = rocksdb.Options(create_if_missing=create, compression=codec)
    families = {
        b'index': rocksdb.ColumnFamilyOptions(compression=codec),
        b'counter': rocksdb.ColumnFamilyOptions(merge_operator=UintAddOperator()),
    }
    if create:
        db = rocksdb.DB(str(path), options)
        for name, family_options in families.items():
            db.create_column_family(name, family_options)
        return db
    return rocksdb.DB(str(path), options, column_families=families)


def batch_path(path):
    return path.with_suffix('.batch')


def verify(path, updated=False, compression='snappy'):
    expected = initial_rows()
    expected[b'wal'] = b'written after compaction'
    expected_index = {b'\xff': b'index value', b'empty': b''}
    if updated:
        del expected[b'remove']
        del expected[b'row/0001']
        expected[b'\x00\xff'] = b'updated\x00\xff'
        expected[b'batch'] = b'serialized write batch'
        expected_index[b'serialized'] = b'column-family write batch'
    db = open_db(path, compression=compression)
    try:
        assert sorted(handle.name for handle in db.column_families) == [b'counter', b'default', b'index']
        for family, rows in ((None, expected), (db.get_column_family(b'index'), expected_index)):
            iterator = db.iteritems(family)
            try:
                iterator.seek_to_first()
                actual = list(iterator)
            finally:
                del iterator
            expected_items = sorted(rows.items())
            if family is not None:
                expected_items = [((family, key), value) for key, value in expected_items]
            assert actual == expected_items, 'persisted keys or values changed'
        counter = db.get_column_family(b'counter')
        expected_total = INITIAL_TOTAL + (22 if updated else 0)
        assert db.get((counter, b'total')) == struct.pack('Q', expected_total)
        serialized = batch_path(path).read_bytes()
        batch = rocksdb.WriteBatch(serialized)
        assert batch.count() == 3
        assert batch.data() == serialized, 'write-batch serialization changed'
    finally:
        db.close()


def create(path, compression='snappy'):
    db = open_db(path, create=True, compression=compression)
    try:
        index = db.get_column_family(b'index')
        counter = db.get_column_family(b'counter')
        batch = rocksdb.WriteBatch()
        for key, value in initial_rows().items():
            batch.put(key, value)
        batch.put((index, b'\xff'), b'index value')
        batch.put((index, b'empty'), b'')
        batch.merge((counter, b'total'), struct.pack('Q', (1 << 63) - 1))
        batch.merge((counter, b'total'), struct.pack('Q', 2))
        db.write(batch, sync=True)
        db.compact_range()
        db.compact_range(column_family=index)
        db.put(b'wal', b'written after compaction', sync=True)
        pending = rocksdb.WriteBatch()
        pending.put(b'batch', b'serialized write batch')
        pending.put((index, b'serialized'), b'column-family write batch')
        pending.merge((counter, b'total'), struct.pack('Q', 17))
        batch_path(path).write_bytes(pending.data())
    finally:
        db.close()
    assert any(path.glob('*.sst')), 'fixture must exercise SST files as well as the WAL'
    verify(path, compression=compression)


def update(path, compression='snappy'):
    verify(path, compression=compression)
    db = open_db(path, compression=compression)
    try:
        db.write(rocksdb.WriteBatch(batch_path(path).read_bytes()), sync=True)
        batch = rocksdb.WriteBatch()
        batch.delete(b'remove')
        batch.delete(b'row/0001')
        batch.put(b'\x00\xff', b'updated\x00\xff')
        batch.merge((db.get_column_family(b'counter'), b'total'), struct.pack('Q', 5))
        db.write(batch, sync=True)
    finally:
        db.close()
    verify(path, updated=True, compression=compression)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('create', 'update', 'verify-updated'))
    parser.add_argument('path', type=Path)
    parser.add_argument('--compression', choices=('snappy', 'zlib', 'lz4', 'lz4hc', 'zstd'), default='snappy')
    args = parser.parse_args()
    if args.action == 'create':
        create(args.path, compression=args.compression)
    elif args.action == 'update':
        update(args.path, compression=args.compression)
    else:
        verify(args.path, updated=True, compression=args.compression)
    print(f'Python {sys.version.split()[0]}: {args.action} passed')
