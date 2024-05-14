/******************************************************************************
 * Copyright (c) 2024 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

#ifndef RISU_REGINFO_SPARC64_H
#define RISU_REGINFO_SPARC64_H

#ifdef __linux__
typedef struct sigcontext host_context_t;
#else
typedef ucontext_t host_context_t;
#endif

struct reginfo {
    uint32_t faulting_insn;
    uint32_t ccr;

    uint64_t pc;
    uint64_t npc;

    uint64_t g[8];
    uint64_t o[8];
    uint64_t l[8];
    uint64_t i[8];

    uint64_t y;
    uint64_t fsr;

    uint64_t fregs[32];
};

#endif /* RISU_REGINFO_SPARC64_H */
