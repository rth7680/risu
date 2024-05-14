/*****************************************************************************
 * Copyright (c) 2024 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

/* Initialise the fp regs */

	.register %g2, #ignore
	.register %g3, #ignore
	.register %g6, #ignore

.text
	rd	%pc, %g1
	sethi	%pc22(.Ldata+4), %g2
	or	%g2, %pc10(.Ldata+8), %g2
	add	%g2, %g1, %g1

	ldd	[%g1 + 4 * 0], %f0
	ldd	[%g1 + 4 * 2], %f2
	ldd	[%g1 + 4 * 4], %f4
	ldd	[%g1 + 4 * 6], %f6
	ldd	[%g1 + 4 * 8], %f8
	ldd	[%g1 + 4 * 10], %f10
	ldd	[%g1 + 4 * 12], %f12
	ldd	[%g1 + 4 * 14], %f14
	ldd	[%g1 + 4 * 16], %f16
	ldd	[%g1 + 4 * 18], %f18
	ldd	[%g1 + 4 * 20], %f20
	ldd	[%g1 + 4 * 22], %f22
	ldd	[%g1 + 4 * 24], %f24
	ldd	[%g1 + 4 * 26], %f26
	ldd	[%g1 + 4 * 28], %f28
	ldd	[%g1 + 4 * 30], %f30
	ldd	[%g1 + 4 * 32], %f32
	ldd	[%g1 + 4 * 34], %f34
	ldd	[%g1 + 4 * 36], %f36
	ldd	[%g1 + 4 * 38], %f38
	ldd	[%g1 + 4 * 40], %f40
	ldd	[%g1 + 4 * 42], %f42
	ldd	[%g1 + 4 * 44], %f44
	ldd	[%g1 + 4 * 46], %f46
	ldd	[%g1 + 4 * 48], %f48
	ldd	[%g1 + 4 * 50], %f50
	ldd	[%g1 + 4 * 52], %f52
	ldd	[%g1 + 4 * 54], %f54
	ldd	[%g1 + 4 * 56], %f56
	ldd	[%g1 + 4 * 58], %f58
	ldd	[%g1 + 4 * 60], %f60
	ldd	[%g1 + 4 * 62], %f62

/* Initialize the special regs */

	wr	%g0, 0x100, %y
	wr	%g0, 0x200, %gsr
	cmp	%g0, %g0

/* Initialise the gp regs */

	mov	1, %g1
	mov	2, %g2
	mov	3, %g3
	mov	4, %g4
	mov	5, %g5
	mov	6, %g6
	/* g7 is the thread pointer */

	mov	8, %o0
	mov	9, %o1
	mov	10, %o2
	mov	11, %o3
	mov	12, %o4
	mov	13, %o5
	/* o6 is the stack pointer */
	mov	15, %o7

	mov	16, %l0
	mov	17, %l1
	mov	18, %l2
	mov	19, %l3
	mov	20, %l4
	mov	21, %l5
	mov	22, %l6
	mov	23, %l7

	mov	24, %i0
	mov	25, %i1
	mov	26, %i2
	mov	27, %i3
	mov	28, %i4
	mov	29, %i5
	/* i6 is the frame pointer */
	mov	31, %i7

/* Do compare. */

	illtrap	0xdead0
	illtrap	0xdead1

.data
	.align	8
.Ldata:
	.double 1
	.double 2
	.double 3
	.double 4
	.double 5
	.double 6
	.double 7
	.double 8
	.double 9
	.double 10
	.double 11
	.double 12
	.double 13
	.double 14
	.double 15
	.double 16
	.double 17
	.double 18
	.double 19
	.double 20
	.double 21
	.double 22
	.double 23
	.double 24
	.double 25
	.double 26
	.double 27
	.double 28
	.double 29
	.double 30
	.double 31
	.double 32

