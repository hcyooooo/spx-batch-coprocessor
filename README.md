# SPHINCS+ Batch Coprocessor Workspace

This repository is a staged workspace for exploring a 4-lane batch vector
coprocessor for SPHINCS+/SLH-DSA. The current focus is software profiling and
C reference models before any RTL or processor integration work.

Start here:

- [Project structure](docs/project_structure.md)
- [Phase 0 profiling](docs/sphincs_profile_result.md)
- [Phase 0.5 batch utilization](docs/sphincs_batch_utilization.md)
- [Phase 1 / 1.5 C model](docs/phase1_c_model.md)
- [Phase 1.6 batch scheduler](docs/phase1_6_batch_scheduler.md)
- [Phase 2 standalone RTL](docs/phase2_standalone_rtl.md)
- [Phase 2.5 RTL PPA](docs/phase2_5_rtl_ppa.md)
- [Phase 3.0 coprocessor wrapper](docs/phase3_0_cop_wrapper.md)

Primary software target:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple test/spx
./sw/sphincsplus/ref/test/spx
```

Batch-utilization profiling:

```sh
make -C sw/sphincsplus/ref PARAMS=sphincs-shake-128f THASH=simple \
  EXTRA_CFLAGS=-DSPX_BATCH_PROFILE test/profile
./sw/sphincsplus/ref/test/profile
```
