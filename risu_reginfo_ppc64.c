/******************************************************************************
 * Copyright (c) IBM Corp, 2016
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Jose Ricardo Ziviani - initial implementation
 *     based on Claudio Fontana's risu_aarch64.c
 *     based on Peter Maydell's risu_arm.c
 *****************************************************************************/

#include <stdio.h>
#include <ucontext.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include <sys/user.h>

#include "risu.h"
#include "risu_reginfo_ppc64.h"

#define XER 37
#define CCR 38

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
void reginfo_init(struct reginfo *ri, ucontext_t *uc, void *siaddr)
{
    memset(ri, 0, sizeof(*ri));

    ri->faulting_insn = *((uint32_t *) uc->uc_mcontext.regs->nip);
    ri->nip = uc->uc_mcontext.regs->nip - image_start_address;

    memcpy(ri->gregs, uc->uc_mcontext.gp_regs, 32 * sizeof(ri->gregs[0]));
    ri->gregs[1] = 0xdeadbeefdeadbeef;   /* sp */
    ri->gregs[13] = 0xdeadbeefdeadbeef;  /* tp */
    ri->gregs[XER] = uc->uc_mcontext.gp_regs[XER];
    ri->gregs[CCR] = uc->uc_mcontext.gp_regs[CCR];

    memcpy(ri->fpregs, uc->uc_mcontext.fp_regs, 32 * sizeof(double));
    ri->fpscr = uc->uc_mcontext.fp_regs[32];

    memcpy(ri->vrregs.vrregs, uc->uc_mcontext.v_regs->vrregs,
           sizeof(ri->vrregs.vrregs[0]) * 32);
    ri->vrregs.vscr = uc->uc_mcontext.v_regs->vscr;
    ri->vrregs.vrsave = uc->uc_mcontext.v_regs->vrsave;
}

/* reginfo_is_eq: compare the reginfo structs, returns nonzero if equal */
int reginfo_is_eq(struct reginfo *m, struct reginfo *a)
{
    return memcmp(m, a, sizeof(*m)) == 0;
}

/* reginfo_dump: print state to a stream */
void reginfo_dump(struct reginfo *ri, FILE * f)
{
    int i;

    fprintf(f, "%6s: %08x\n", "insn", ri->faulting_insn);
    fprintf(f, "%6s: %016lx\n", "pc", ri->nip);

    for (i = 0; i < 32; i++) {
        fprintf(f, "%*s%d: %016lx%s",
                6 - (i < 10 ? 1 : 2), "r", i, ri->gregs[i],
                i & 1 ? "\n" : "  ");
    }

    fprintf(f, "%6s: %016lx  %6s: %016lx\n",
            "xer", ri->gregs[XER],
            "ccr", ri->gregs[CCR]);

    for (i = 0; i < 32; i++) {
        fprintf(f, "%*s%d: %016lx%s",
                6 - (i < 10 ? 1 : 2), "f", i, ri->fpregs[i],
                i & 1 ? "\n" : "  ");
    }
    fprintf(f, "%6s: %016lx\n", "fpscr", ri->fpscr);

    for (i = 0; i < 32; i++) {
        fprintf(f, "%*s%d: %08x %08x %08x %08x\n",
                6 - (i < 10 ? 1 : 2), "vr", i,
                ri->vrregs.vrregs[i][0], ri->vrregs.vrregs[i][1],
                ri->vrregs.vrregs[i][2], ri->vrregs.vrregs[i][3]);
    }
}

void reginfo_dump_mismatch(struct reginfo *m, struct reginfo *a, FILE *f)
{
    int i;

    for (i = 0; i < 32; i++) {
        if (m->gregs[i] != a->gregs[i]) {
            fprintf(f, "%*s%d: %016lx vs %016lx\n",
                    6 - (1 < 10 ? 1 : 2), "r", i,
                    m->gregs[i], a->gregs[i]);
        }
    }

    if (m->gregs[XER] != a->gregs[XER]) {
        fprintf(f, "%6s: %016lx vs %016lx\n",
                "xer", m->gregs[XER], a->gregs[XER]);
    }

    if (m->gregs[CCR] != a->gregs[CCR]) {
        fprintf(f, "%6s: %016lx vs %016lx\n",
                "ccr", m->gregs[CCR], a->gregs[CCR]);
    }

    for (i = 0; i < 32; i++) {
        if (m->fpregs[i] != a->fpregs[i]) {
            fprintf(f, "%*s%d: %016lx vs %016lx\n",
                    6 - (i < 10 ? 1 : 2), "f", i,
                    m->fpregs[i], a->fpregs[i]);
        }
    }

    for (i = 0; i < 32; i++) {
        if (m->vrregs.vrregs[i][0] != a->vrregs.vrregs[i][0] ||
            m->vrregs.vrregs[i][1] != a->vrregs.vrregs[i][1] ||
            m->vrregs.vrregs[i][2] != a->vrregs.vrregs[i][2] ||
            m->vrregs.vrregs[i][3] != a->vrregs.vrregs[i][3]) {

            fprintf(f, "%*s%d: %08x%08x%08x%08x vs %08x%08x%08x%08x\n",
                    6 - (i < 10 ? 1 : 2), "vr", i,
                    m->vrregs.vrregs[i][0], m->vrregs.vrregs[i][1],
                    m->vrregs.vrregs[i][2], m->vrregs.vrregs[i][3],
                    a->vrregs.vrregs[i][0], a->vrregs.vrregs[i][1],
                    a->vrregs.vrregs[i][2], a->vrregs.vrregs[i][3]);
        }
    }
}
