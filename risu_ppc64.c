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

#include "risu.h"
#include <sys/user.h>

void advance_pc(ucontext_t *uc)
{
    uc->uc_mcontext.regs->nip += 4;
}

void set_ucontext_paramreg(ucontext_t *uc, uint64_t value)
{
    uc->uc_mcontext.gp_regs[0] = value;
}

uint64_t get_reginfo_paramreg(struct reginfo *ri)
{
    return ri->gregs[0];
}

RisuOp get_risuop(struct reginfo *ri)
{
    uint32_t insn = ri->faulting_insn;
    uint32_t op = insn & 0xf;
    uint32_t key = insn & ~0xf;
    uint32_t risukey = 0x00005af0;
    return (key != risukey) ? OP_SIGILL : op;
}

uintptr_t get_pc(struct reginfo *ri)
{
   return ri->nip;
}
