/******************************************************************************
 * Copyright (c) 2013 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Claudio Fontana (Linaro) - initial implementation
 *     based on Peter Maydell's risu_arm.c
 *****************************************************************************/

#ifndef RISU_REGINFO_AARCH64_H
#define RISU_REGINFO_AARCH64_H

#include <signal.h>

typedef ucontext_t host_context_t;

/* The kernel headers set this based on future arch extensions.
   The current arch maximum is 16.  Save space below.  */
#undef SVE_VQ_MAX
#define SVE_VQ_MAX 16

#define ROUND_UP(SIZE, POW2)    (((SIZE) + (POW2) - 1) & -(POW2))

#ifdef ZA_MAGIC
/* System headers have all Streaming SVE definitions. */
typedef struct sve_context risu_sve_context;
typedef struct za_context  risu_za_context;
#else
#define ZA_MAGIC         0x54366345
#define SVE_SIG_FLAG_SM  1

/* System headers missing flags field. */
typedef struct {
    struct _aarch64_ctx head;
    uint16_t vl;
    uint16_t flags;
    uint16_t reserved[2];
} risu_sve_context;

typedef struct {
    struct _aarch64_ctx head;
    uint16_t vl;
    uint16_t reserved[3];
} risu_za_context;

#define ZA_SIG_REGS_OFFSET \
    ROUND_UP(sizeof(risu_za_context), SVE_VQ_BYTES)

#define ZA_SIG_REGS_SIZE(vq) \
    ((vq) * (vq) * SVE_VQ_BYTES * SVE_VQ_BYTES)

#define ZA_SIG_ZAV_OFFSET(vq, n) \
    (ZA_SIG_REGS_OFFSET + (SVE_SIG_ZREG_SIZE(vq) * n))

#define ZA_SIG_CONTEXT_SIZE(vq) \
    (ZA_SIG_REGS_OFFSET + ZA_SIG_REGS_SIZE(vq))

#endif /* ZA_MAGIC */

#define RISU_SVE_REGS_SIZE(VQ)  ROUND_UP(SVE_SIG_REGS_SIZE(VQ), 16)
#define RISU_SIMD_REGS_SIZE     (32 * 16)

struct reginfo {
    uint64_t fault_address;
    uint64_t regs[31];
    uint64_t sp;
    uint64_t pc;
    uint32_t flags;
    uint32_t faulting_insn;

    /* FP/SIMD */
    uint32_t fpsr;
    uint32_t fpcr;
    uint16_t sve_vl;
    uint16_t svcr;

    char extra[RISU_SVE_REGS_SIZE(SVE_VQ_MAX) +
               ZA_SIG_REGS_SIZE(SVE_VQ_MAX)]
        __attribute__((aligned(16)));
};

#define SVCR_SM  1
#define SVCR_ZA  2

static inline uint64_t *reginfo_vreg(struct reginfo *ri, int i)
{
    return (uint64_t *)&ri->extra[i * 16];
}

static inline uint64_t *reginfo_zreg(struct reginfo *ri, int vq, int i)
{
    return (uint64_t *)&ri->extra[SVE_SIG_ZREG_OFFSET(vq, i) -
                                  SVE_SIG_REGS_OFFSET];
}

static inline uint16_t *reginfo_preg(struct reginfo *ri, int vq, int i)
{
    return (uint16_t *)&ri->extra[SVE_SIG_PREG_OFFSET(vq, i) -
                                  SVE_SIG_REGS_OFFSET];
}

static inline uint64_t *reginfo_zav(struct reginfo *ri, int vq, int i)
{
    return (uint64_t *)&ri->extra[RISU_SVE_REGS_SIZE(vq) +
                                  ZA_SIG_ZAV_OFFSET(vq, i) -
                                  ZA_SIG_REGS_OFFSET];
}

#endif /* RISU_REGINFO_AARCH64_H */
