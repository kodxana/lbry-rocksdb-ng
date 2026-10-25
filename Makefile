all: src/rocksdb/librocksdb.a

JOBS ?= 2
ROCKSDB_DIR := $(abspath src/rocksdb)

src/rocksdb/librocksdb.a: Makefile src/rocksdb/libz.a
	$(MAKE) \
		-e EXTRA_CXXFLAGS="-fPIC" \
		-e EXTRA_CFLAGS="-fPIC" \
		-C src/rocksdb \
		-j $(JOBS) \
		LZ4_VER=1.10.0 \
		LZ4_SHA256=537512904744b35e232912055ccf8ec66d768639ff3abe5788d90d792ec5f48b \
			libsnappy.a \
			liblz4.a \
			libbz2.a \
			libzstd.a

	(cd src/rocksdb && mkdir -p build && cd build && cmake \
		-DWITH_SNAPPY=1 \
		-DWITH_LZ4=1 \
		-DWITH_ZLIB=1 \
		-DWITH_ZSTD=1 \
		-DWITH_GFLAGS=0 \
		-DROCKSDB_BUILD_SHARED=0 \
		-DPORTABLE=ON \
		-DWITH_TOOLS=0 \
		-DWITH_BENCHMARK_TOOLS=0 \
		-DWITH_CORE_TOOLS=0 \
		-DWITH_JEMALLOC=0 \
		-DCMAKE_BUILD_TYPE=Release \
		-DSnappy_INCLUDE_DIRS=$(ROCKSDB_DIR)/snappy-1.1.8 \
		-DSnappy_LIBRARIES=$(ROCKSDB_DIR)/libsnappy.a \
		-Dlz4_INCLUDE_DIRS=$(ROCKSDB_DIR)/lz4-1.10.0/lib \
		-Dlz4_LIBRARIES=$(ROCKSDB_DIR)/liblz4.a \
		-Dzstd_INCLUDE_DIRS=$(ROCKSDB_DIR)/zstd-1.4.9/lib \
		-Dzstd_LIBRARIES=$(ROCKSDB_DIR)/libzstd.a \
		-DZLIB_INCLUDE_DIR=$(ROCKSDB_DIR)/zlib-1.3.2 \
		-DZLIB_LIBRARY=$(ROCKSDB_DIR)/libz.a \
		-DCMAKE_CXX_FLAGS="-fPIC -I../snappy-1.1.8/build -I../zstd-1.4.9/lib/dictBuilder" \
		.. && $(MAKE) -j $(JOBS))

	cp src/rocksdb/build/librocksdb.a src/rocksdb/librocksdb.a

# Keep the upstream gzwrite fix until it is included in a zlib release.
src/rocksdb/libz.a: Makefile patches/zlib-CVE-2026-85091.patch
	$(MAKE) -C src/rocksdb ZLIB_VER=1.3.2 \
		ZLIB_SHA256=bb329a0a2cd0274d05519d61c667c062e06990d72e125ee2dfa8de64f0119d16 \
		ZLIB_DOWNLOAD_BASE=https://zlib.net/fossils zlib-1.3.2.tar.gz
	cd src/rocksdb && tar xzf zlib-1.3.2.tar.gz
	cd src/rocksdb/zlib-1.3.2 && patch --batch --fuzz=0 -p1 < ../../../patches/zlib-CVE-2026-85091.patch
	cd src/rocksdb/zlib-1.3.2 && CFLAGS='-fPIC -O2' ./configure --static && $(MAKE) -j $(JOBS) && $(MAKE) check
	cp src/rocksdb/zlib-1.3.2/libz.a src/rocksdb/libz.a

clean:
	rm -rf src/rocksdb/build
	make -C src/rocksdb clean
