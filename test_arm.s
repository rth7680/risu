/*******************************************************************************
 * Copyright (c) 2010 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Peter Maydell (Linaro) - initial implementation
 *******************************************************************************/

.text

/* magic instruction to force ARM mode whether we were in ARM or Thumb before */
.inst 0xe0004778

/* Initialise the gp regs */
add r0, pc, #4
ldmia r0, {r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12,r14}
b 1f

.int 0,1,2,3,4,5,6,7,8,9,10,11,12,14

1:
msr CPSR_fs, #0

/* do compare.
 * The space 0xE7F___F_ is guaranteed to always UNDEF
 * and not to be allocated for insns in future architecture
 * revisions.
 */
.inst 0xe7fe5af0
/* exit test */
.inst 0xe7fe5af1
