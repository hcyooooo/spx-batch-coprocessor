PARAMS = sphincs-haraka-128f
THASH = robust

CC=/usr/bin/gcc
CFLAGS=-Wall -Wextra -Wpedantic -O3 -std=c99 -Wconversion -Wmissing-prototypes -DPARAMS=$(PARAMS) -DTHASH=$(THASH) $(EXTRA_CFLAGS)

SOURCES =          address.c randombytes.c merkle.c wots.c wotsx1.c utils.c utilsx1.c fors.c sign.c profile.c batch_scheduler.c
HEADERS = params.h address.h randombytes.h merkle.h wots.h wotsx1.h utils.h utilsx1.h fors.h api.h  hash.h thash.h profile.h batch_scheduler.h
X4_TESTS =
BATCH_TESTS =

ifneq (,$(findstring shake,$(PARAMS)))
	SOURCES += fips202.c hash_shake.c thash_shake_$(THASH).c keccakx4.c
	HEADERS += fips202.h keccakx4.h
	X4_TESTS += test/test_keccakx4
ifeq ($(THASH),simple)
	SOURCES += thashx4_shake_simple.c
	HEADERS += thashx4_shake_simple.h
	X4_TESTS += test/test_thashx4
	BATCH_TESTS += test/test_wots_batch
endif
endif
ifneq (,$(findstring haraka,$(PARAMS)))
	SOURCES += haraka.c hash_haraka.c thash_haraka_$(THASH).c
	HEADERS += haraka.h
endif
ifneq (,$(findstring sha2,$(PARAMS)))
	SOURCES += sha2.c hash_sha2.c thash_sha2_$(THASH).c
	HEADERS += sha2.h
endif

DET_SOURCES = $(SOURCES:randombytes.%=rng.%)
DET_HEADERS = $(HEADERS:randombytes.%=rng.%)

TESTS =         test/fors \
		test/spx \

TESTS += $(X4_TESTS)

BENCHMARK = test/benchmark
PROFILE = test/profile

.PHONY: clean test benchmark profile x4-test x4-tests batch-test batch-tests

default: PQCgenKAT_sign

all: PQCgenKAT_sign tests benchmarks

tests: $(TESTS)

test: $(TESTS:=.exec)

x4-tests: $(X4_TESTS)

x4-test: $(X4_TESTS:=.exec)

batch-tests: EXTRA_CFLAGS += -DSPX_USE_THASHX4_BATCH
batch-tests: $(BATCH_TESTS)

batch-test: EXTRA_CFLAGS += -DSPX_USE_THASHX4_BATCH
batch-test: $(BATCH_TESTS:=.exec)

benchmarks: $(BENCHMARK)

benchmark: $(BENCHMARK:=.exec)

profile: EXTRA_CFLAGS += -DSPX_PROFILE -DSPX_BATCH_PROFILE
profile: $(PROFILE)
	@$<

PQCgenKAT_sign: PQCgenKAT_sign.c $(DET_SOURCES) $(DET_HEADERS)
	$(CC) $(CFLAGS) -o $@ $(DET_SOURCES) $< -lcrypto

test/benchmark: test/benchmark.c test/cycles.c $(SOURCES) $(HEADERS)
	$(CC) $(CFLAGS) -o $@ test/cycles.c $(SOURCES) $< $(LDLIBS)

test/%: test/%.c $(SOURCES) $(HEADERS)
	$(CC) $(CFLAGS) -o $@ $(SOURCES) $< $(LDLIBS)

test/haraka: test/haraka.c $(filter-out haraka.c,$(SOURCES)) $(HEADERS)
	$(CC) $(CFLAGS) -o $@ $(filter-out haraka.c,$(SOURCES)) $< $(LDLIBS)

test/%.exec: test/%
	@$<

clean:
	-$(RM) $(TESTS)
	-$(RM) $(BATCH_TESTS)
	-$(RM) $(BENCHMARK)
	-$(RM) $(PROFILE)
	-$(RM) PQCgenKAT_sign
	-$(RM) PQCsignKAT_*.rsp
	-$(RM) PQCsignKAT_*.req
