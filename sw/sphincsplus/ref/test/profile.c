#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../api.h"
#include "../params.h"
#include "../profile.h"
#include "../randombytes.h"

#define SPX_MLEN 32

#if !defined(SPX_PROFILE) && !defined(SPX_BATCH_PROFILE)
int main(void)
{
    puts("Rebuild with EXTRA_CFLAGS='-DSPX_PROFILE -DSPX_BATCH_PROFILE' to enable profiling.");
    return 1;
}
#else
int main(void)
{
    int ret = 0;
    unsigned char pk[SPX_PK_BYTES];
    unsigned char sk[SPX_SK_BYTES];
    unsigned char *m = malloc(SPX_MLEN);
    unsigned char *sm = malloc(SPX_BYTES + SPX_MLEN);
    unsigned char *mout = malloc(SPX_BYTES + SPX_MLEN);
    unsigned long long smlen = 0;
    unsigned long long mlen = 0;

    setbuf(stdout, NULL);

    if (m == NULL || sm == NULL || mout == NULL) {
        free(m);
        free(sm);
        free(mout);
        return 1;
    }

    randombytes(m, SPX_MLEN);

    printf("Parameters: %s, THASH=%s\n", xstr(PARAMS), xstr(THASH));
    printf("n=%d h=%d d=%d fors_height=%d fors_trees=%d wots_w=%d\n",
           SPX_N, SPX_FULL_HEIGHT, SPX_D, SPX_FORS_HEIGHT, SPX_FORS_TREES,
           SPX_WOTS_W);

    spx_profile_reset_all();

    ret = crypto_sign_keypair(pk, sk);
    if (ret != 0) {
        puts("crypto_sign_keypair failed");
        goto cleanup;
    }
#ifdef SPX_PROFILE
    spx_profile_print_phase(SPX_PROFILE_PHASE_KEYGEN, stdout);
#endif

    ret = crypto_sign(sm, &smlen, m, SPX_MLEN, sk);
    if (ret != 0) {
        puts("crypto_sign failed");
        goto cleanup;
    }
#ifdef SPX_PROFILE
    spx_profile_print_phase(SPX_PROFILE_PHASE_SIGN, stdout);
#endif

    ret = crypto_sign_open(mout, &mlen, sm, smlen, pk);
    if (ret != 0) {
        puts("crypto_sign_open failed");
        goto cleanup;
    }
#ifdef SPX_PROFILE
    spx_profile_print_phase(SPX_PROFILE_PHASE_VERIFY, stdout);
#endif

#if defined(SPX_PROFILE) || defined(SPX_BATCH_PROFILE)
    spx_profile_print_batch(stdout);
#endif

    if (mlen != SPX_MLEN || memcmp(m, mout, SPX_MLEN) != 0) {
        puts("verification output mismatch");
        ret = 1;
        goto cleanup;
    }

    printf("\nSignature size: %d bytes\n", SPX_BYTES);

cleanup:
    free(m);
    free(sm);
    free(mout);
    return ret;
}
#endif
