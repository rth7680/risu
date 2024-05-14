/******************************************************************************
 * Copyright (c) 2024 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

#include <signal.h>
#include "risu.h"

void advance_pc(host_context_t *hc)
{
#ifdef __linux__
    hc->sigc_regs.tpc = hc->sigc_regs.tnpc;
    hc->sigc_regs.tnpc += 4;
#else
    hc->uc_mcontext.gregs[REG_PC] = hc->uc_mcontext.gregs[REG_nPC];
    hc->uc_mcontext.gregs[REG_nPC] += 4;
#endif
}

void set_ucontext_paramreg(host_context_t *hc, uint64_t value)
{
#ifdef __linux__
    hc->sigc_regs.u_regs[15] = value;
#else
    hc->uc_mcontext.gregs[REG_O7] = value;
#endif
}

uint64_t get_reginfo_paramreg(struct reginfo *ri)
{
    return ri->o[7];
}

RisuOp get_risuop(struct reginfo *ri)
{
    /* Return the risuop we have been asked to do
     * (or OP_SIGILL if this was a SIGILL for a non-risuop insn)
     */
    uint32_t insn = ri->faulting_insn;
    uint32_t op = insn & 0xf;
    uint32_t key = insn & ~0xf;
    uint32_t risukey = 0x000dead0;
    return (key != risukey) ? OP_SIGILL : op;
}

uintptr_t get_pc(struct reginfo *ri)
{
   return ri->pc;
}
