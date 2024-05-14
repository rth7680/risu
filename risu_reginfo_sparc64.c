/******************************************************************************
 * Copyright (c) 2024 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

#include <stdio.h>
#include <ucontext.h>
#include <string.h>
#include <signal.h>
#include <stdlib.h>

#include "risu.h"
#include "risu_reginfo_sparc64.h"

#define STACK_BIAS 2047

const struct option * const arch_long_opts;
const char * const arch_extra_help;

void process_arch_opt(int opt, const char *arg)
{
    abort();
}

void arch_init(void)
{
}

int reginfo_size(struct reginfo *ri)
{
    return sizeof(*ri);
}

/* reginfo_init: initialize with a ucontext */
void reginfo_init(struct reginfo *ri, host_context_t *hc, void *siaddr)
{
    memset(ri, 0, sizeof(*ri));

#ifdef __linux__
    ri->pc = hc->sigc_regs.tpc;
    ri->npc = hc->sigc_regs.tnpc;
    ri->ccr = (hc->sigc_regs.tstate >> 32) & 0xff;
    ri->y = hc->sigc_regs.y;

    /* g + o */
    memcpy(&ri->g, hc->sigc_regs.u_regs, 16 * 8);
    /* l + i are just before sc */
    memcpy(&ri->l, (void *)hc - 8 * 8 * 3, 16 * 8);

    if (hc->sigc_fpu_save) {
        ri->fsr = hc->sigc_fpu_save->si_fsr;
        /* TODO: ri->gsr = hc->sigc_fpu_save->si_gsr; */
        memcpy(ri->fregs, hc->sigc_fpu_save->si_float_regs, 32 * 8);
    }
#elif defined(__sun__)
    ri->pc = hc->uc_mcontext.gregs[REG_PC];
    ri->npc = hc->uc_mcontext.gregs[REG_nPC];
    ri->ccr = hc->uc_mcontext.gregs[REG_CCR];

    /* G and O are in the signal frame. */
    memcpy(&ri->g[1], &hc->uc_mcontext.gregs[REG_G1], 7 * sizeof(greg_t));
    memcpy(&ri->o[0], &hc->uc_mcontext.gregs[REG_O0], 8 * sizeof(greg_t));

    /* L and I are flushed to the regular stack frame. */
    memcpy(&ri->l[0], (void *)(ri->o[6] + STACK_BIAS), 16 * sizeof(greg_t));

    ri->y = hc->uc_mcontext.gregs[REG_Y];
    ri->fsr = hc->uc_mcontext.fpregs.fpu_fsr;
    /* ??? Despite %gsr being asr19, uc->mc.asrs[19-16] is not populated. */

    memcpy(&ri->fregs[0], &hc->uc_mcontext.fpregs.fpu_fr,
           32 * sizeof(uint64_t));
#endif

    ri->g[7] = 0xdeadbeefdeadbeeful;  /* tp */
    ri->o[6] = 0xdeadbeefdeadbeeful;  /* sp */
    ri->i[6] = 0xdeadbeefdeadbeeful;  /* fp */

    ri->faulting_insn = *(uint32_t *)ri->pc;

    ri->pc -= image_start_address;
    ri->npc -= image_start_address;
}

/* reginfo_is_eq: compare the reginfo structs, returns nonzero if equal */
bool reginfo_is_eq(struct reginfo *r1, struct reginfo *r2)
{
    return memcmp(r1, r2, reginfo_size(r1)) == 0;
}

/* reginfo_dump: print state to a stream, returns nonzero on success */
void reginfo_dump(struct reginfo *ri, FILE * f)
{
    int i;

    fprintf(f, "  insn   : %08x\n", ri->faulting_insn);
    fprintf(f, "  ccr    : %02x\n", ri->ccr);
    fprintf(f, "  pc     : %016" PRIx64 "\n", ri->pc);
    fprintf(f, "  npc    : %016" PRIx64 "\n", ri->npc);

    for (i = 1; i < 8; i++) {
        fprintf(f, "  G%d     : %016" PRIx64 "\n", i, ri->g[i]);
    }
    for (i = 0; i < 8; i++) {
        fprintf(f, "  O%d     : %016" PRIx64 "\n", i, ri->o[i]);
    }
    for (i = 0; i < 8; i++) {
        fprintf(f, "  L%d     : %016" PRIx64 "\n", i, ri->l[i]);
    }
    for (i = 0; i < 8; i++) {
        fprintf(f, "  I%d     : %016" PRIx64 "\n", i, ri->i[i]);
    }

    fprintf(f, "  y      : %016" PRIx64 "\n", ri->y);
    fprintf(f, "  fsr    : %016" PRIx64 "\n", ri->fsr);

    for (i = 0; i < 32; i++) {
        fprintf(f, "  F%-2d    : %016" PRIx64 "\n", i * 2, ri->fregs[i]);
    }
}

/* reginfo_dump_mismatch: print mismatch details to a stream, ret nonzero=ok */
void reginfo_dump_mismatch(struct reginfo *m, struct reginfo *a, FILE * f)
{
    int i;

    if (m->faulting_insn != a->faulting_insn) {
        fprintf(f, "  insn   : %08x vs %08x\n",
                m->faulting_insn, a->faulting_insn);
    }
    if (m->ccr != a->ccr) {
        fprintf(f, "  ccr    : %02x vs %02x\n", m->ccr, a->ccr);
    }
    if (m->pc != a->pc) {
        fprintf(f, "  pc     : %016" PRIx64 " vs %016" PRIx64 "\n",
                m->pc, a->pc);
    }
    if (m->npc != a->npc) {
        fprintf(f, "  npc    : %016" PRIx64 " vs %016" PRIx64 "\n",
                m->npc, a->npc);
    }

    for (i = 1; i < 8; i++) {
        if (m->g[i] != a->g[i]) {
            fprintf(f, "  G%d     : %016" PRIx64 " vs %016" PRIx64 "\n",
                    i, m->g[i], a->g[i]);
        }
    }
    for (i = 0; i < 8; i++) {
        if (m->o[i] != a->o[i]) {
            fprintf(f, "  O%d     : %016" PRIx64 " vs %016" PRIx64 "\n",
                    i, m->o[i], a->o[i]);
        }
    }
    for (i = 0; i < 8; i++) {
        if (m->l[i] != a->l[i]) {
            fprintf(f, "  L%d     : %016" PRIx64 " vs %016" PRIx64 "\n",
                    i, m->l[i], a->l[i]);
        }
    }
    for (i = 0; i < 8; i++) {
        if (m->i[i] != a->i[i]) {
            fprintf(f, "  I%d     : %016" PRIx64 " vs %016" PRIx64 "\n",
                    i, m->i[i], a->i[i]);
        }
    }

    if (m->y != a->y) {
        fprintf(f, "  y      : %016" PRIx64 " vs %016" PRIx64 "\n",
                m->y, a->y);
    }
    if (m->fsr != a->fsr) {
        fprintf(f, "  fsr    : %016" PRIx64 " vs %016" PRIx64 "\n",
                m->fsr, a->fsr);
    }

    for (i = 0; i < 32; i++) {
        if (m->fregs[i] != a->fregs[i]) {
            fprintf(f, "  F%-2d    : %016" PRIx64 " vs %016" PRIx64 "\n",
                    i * 2, m->fregs[i], a->fregs[i]);
        }
    }
}
