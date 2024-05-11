/*****************************************************************************
 * Copyright (c) 2022 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *****************************************************************************/

	.arch_extension sme

	mov	w0, #0
	mov	w1, #0
	mov	w2, #0
	mov	w3, #0
	mov	w4, #0
	mov	w5, #0
	mov	w6, #0
	mov	w7, #0
	mov	w8, #0
	mov	w9, #0
	mov	w10, #0
	mov	w11, #0
	mov	w12, #0
	mov	w13, #0
	mov	w14, #0
	mov	w15, #0
	mov	w16, #0
	mov	w17, #0
	mov	w18, #0
	mov	w19, #0
	mov	w20, #0
	mov	w21, #0
	mov	w22, #0
	mov	w23, #0
	mov	w24, #0
	mov	w25, #0
	mov	w26, #0
	mov	w27, #0
	mov	w28, #0
	mov	w29, #0
	mov	w30, #0

	smstart

	ptrue	p0.b
	rdsvl	x12, #1

0:	subs	w12, w12, #1
	lsl	w13, w12, #4
	index	z0.b, w13, #1
	mova	za0h.b[w12, #0], p0/m, z0.b
	b.ne	0b

	.inst 0x00005af0		/* compare */

	rdsvl	x12, #1
0:	subs	w12, w12, #1
	lsl	w13, w12, #4
	index	z0.b, w13, #1
	mova	za0v.b[w12, #0], p0/m, z0.b
	b.ne	0b

	.inst 0x00005af1		/* exit */
