/*****************************************************************************
 * Copyright (c) 2016 Laurent Vivier
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

#include <stdio.h>
#include <ucontext.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>

#include "risu.h"
#include "risu_reginfo_m68k.h"

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
    int i;
    memset(ri, 0, sizeof(*ri));

    ri->faulting_insn = *((uint32_t *) uc->uc_mcontext.gregs[R_PC]);
    ri->pc = uc->uc_mcontext.gregs[R_PC] - image_start_address;

    for (i = 0; i < NGREG; i++) {
        ri->gregs[i] = uc->uc_mcontext.gregs[i];
    }

    ri->fpregs.f_pcr = uc->uc_mcontext.fpregs.f_pcr;
    ri->fpregs.f_psr = uc->uc_mcontext.fpregs.f_psr;
    ri->fpregs.f_fpiaddr = uc->uc_mcontext.fpregs.f_fpiaddr;
    for (i = 0; i < 8; i++) {
        memcpy(ri->fpregs.f_fpregs[i],
               uc->uc_mcontext.fpregs.f_fpregs[i],
               sizeof(ri->fpregs.f_fpregs[0]));
    }
}

/* reginfo_is_eq: compare the reginfo structs, returns true if equal */
bool reginfo_is_eq(struct reginfo *m, struct reginfo *a)
{
    int i;

    if (m->gregs[R_PS] != a->gregs[R_PS]) {
        return false;
    }

    for (i = 0; i < 16; i++) {
        if (i == R_SP || i == R_A6) {
            continue;
        }
        if (m->gregs[i] != a->gregs[i]) {
            return false;
        }
    }

    if (m->fpregs.f_pcr != a->fpregs.f_pcr) {
        return false;
    }

    if (m->fpregs.f_psr != a->fpregs.f_psr) {
        return false;
    }

    for (i = 0; i < 8; i++) {
        if (m->fpregs.f_fpregs[i][0] != a->fpregs.f_fpregs[i][0] ||
            m->fpregs.f_fpregs[i][1] != a->fpregs.f_fpregs[i][1] ||
            m->fpregs.f_fpregs[i][2] != a->fpregs.f_fpregs[i][2]) {
            return false;
        }
    }

    return true;
}

/* reginfo_dump: print state to a stream */
void reginfo_dump(struct reginfo *ri, FILE *f)
{
    int i;
    fprintf(f, "  pc            \e[1;101;37m0x%08x\e[0m\n", ri->pc);

    fprintf(f, "\tPC: %08x\n", ri->gregs[R_PC]);
    fprintf(f, "\tPS: %04x\n", ri->gregs[R_PS]);

    for (i = 0; i < 8; i++) {
        fprintf(f, "\tD%d: %8x\tA%d: %8x\n", i, ri->gregs[i],
                i, ri->gregs[i + 8]);
    }


    for (i = 0; i < 8; i++) {
        fprintf(f, "\tFP%d: %08x %08x %08x\n", i,
                ri->fpregs.f_fpregs[i][0], ri->fpregs.f_fpregs[i][1],
                ri->fpregs.f_fpregs[i][2]);
    }

    fprintf(f, "\n");
}

void reginfo_dump_mismatch(struct reginfo *m, struct reginfo *a, FILE *f)
{
    int i;

    if (m->gregs[R_PS] != a->gregs[R_PS]) {
        fprintf(f, "    PS: %08x vs %08x\n",
                m->gregs[R_PS], a->gregs[R_PS]);
    }

    for (i = 0; i < 16; i++) {
        if (i == R_SP || i == R_A6) {
            continue;
        }
        if (m->gregs[i] != a->gregs[i]) {
            fprintf(f, "    %c%d: %08x vs %08x\n",
                    i < 8 ? 'D' : 'A', i % 8, m->gregs[i], a->gregs[i]);
        }
    }

    if (m->fpregs.f_pcr != a->fpregs.f_pcr) {
        fprintf(f, "  FPCR: %04x vs %04x\n",
                m->fpregs.f_pcr, a->fpregs.f_pcr);
    }

    if (m->fpregs.f_psr != a->fpregs.f_psr) {
        fprintf(f, "  FPSR: %04x vs %04x\n",
                m->fpregs.f_psr, a->fpregs.f_psr);
    }

    for (i = 0; i < 8; i++) {
        if (m->fpregs.f_fpregs[i][0] != a->fpregs.f_fpregs[i][0] ||
            m->fpregs.f_fpregs[i][1] != a->fpregs.f_fpregs[i][1] ||
            m->fpregs.f_fpregs[i][2] != a->fpregs.f_fpregs[i][2]) {
            fprintf(f, "   FP%d: %08x%08x%08x vs %08x%08x%08x\n", i,
                    m->fpregs.f_fpregs[i][0], m->fpregs.f_fpregs[i][1],
                    m->fpregs.f_fpregs[i][2], a->fpregs.f_fpregs[i][0],
                    a->fpregs.f_fpregs[i][1], a->fpregs.f_fpregs[i][2]);
        }
    }
}
