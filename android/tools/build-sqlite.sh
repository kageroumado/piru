#!/bin/zsh
# Builds the SQLite amalgamation for Android arm64 with the compile options of Apple's system
# SQLite (`sqlite3 :memory: 'pragma compile_options'` on macOS 27), so the core's SQL runs
# against the same dialect and limits on both platforms. USE_URI matters most: the catalog is
# opened as `file:…?immutable=1`, which a default build reads as a literal path.
set -e
. "${0:A:h}/env.sh"
piru_require_ndk || exit 1
SRC="$PIRU_ANDROID/downloads/$SQLITE_AMALGAMATION"
CC=$(ls -d $ANDROID_NDK_HOME/toolchains/llvm/prebuilt/*/bin)/aarch64-linux-android28-clang
AR=$(dirname $CC)/llvm-ar
FLAGS=(
  -DSQLITE_USE_URI=1 -DSQLITE_DQS=3 -DSQLITE_THREADSAFE=2
  -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_DEFAULT_SYNCHRONOUS=2 -DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1
  -DSQLITE_DEFAULT_CACHE_SIZE=2000 -DSQLITE_DEFAULT_JOURNAL_SIZE_LIMIT=32768 -DSQLITE_TEMP_STORE=1
  -DSQLITE_MAX_VARIABLE_NUMBER=500000 -DSQLITE_MAX_ATTACHED=10 -DSQLITE_MAX_MMAP_SIZE=1073741824
  -DSQLITE_ENABLE_FTS3 -DSQLITE_ENABLE_FTS3_PARENTHESIS -DSQLITE_ENABLE_FTS4 -DSQLITE_ENABLE_FTS5
  -DSQLITE_ENABLE_RTREE -DSQLITE_ENABLE_MATH_FUNCTIONS -DSQLITE_ENABLE_COLUMN_METADATA
  -DSQLITE_ENABLE_SNAPSHOT -DSQLITE_ENABLE_PREUPDATE_HOOK -DSQLITE_ENABLE_SESSION
  -DSQLITE_ENABLE_PERCENTILE -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT -DSQLITE_ENABLE_API_ARMOR
  -DSQLITE_OMIT_LOAD_EXTENSION -DHAVE_ISNAN
)
mkdir -p "$PIRU_ANDROID/sqlite/include" "$PIRU_ANDROID/sqlite/lib"
cp "$SRC/sqlite3.h" "$SRC/sqlite3ext.h" "$PIRU_ANDROID/sqlite/include/"
$CC -c -O2 -fPIC $FLAGS "$SRC/sqlite3.c" -o "$PIRU_ANDROID/sqlite/sqlite3.o"
$AR rcs "$PIRU_ANDROID/sqlite/lib/libsqlite3.a" "$PIRU_ANDROID/sqlite/sqlite3.o"
echo "libsqlite3.a rebuilt with ${#FLAGS} options"
