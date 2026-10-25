from pathlib import Path
import tempfile
import unittest

from tests.persistence import create, update, verify


class TestPersistence(unittest.TestCase):
    def test_reopen_and_apply_serialized_batch(self):
        for compression in ('snappy', 'zlib', 'lz4', 'lz4hc', 'zstd'):
            with self.subTest(compression=compression), tempfile.TemporaryDirectory() as directory:
                path = Path(directory) / 'database'
                create(path, compression=compression)
                update(path, compression=compression)
                verify(path, updated=True, compression=compression)
