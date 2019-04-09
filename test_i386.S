/*#############################################################################
 * Copyright (c) 2010 Linaro Limited
 * All rights reserved. This program and the accompanying materials
 * are made available under the terms of the Eclipse Public License v1.0
 * which accompanies this distribution, and is available at
 * http://www.eclipse.org/legal/epl-v10.html
 *
 * Contributors:
 *     Peter Maydell (Linaro) - initial implementation
 *###########################################################################*/

/* A trivial test image for x86 */

/* Initialise the registers to avoid spurious mismatches */

#ifdef __x86_64__
#define BASE	%rax
	lea	2f(%rip), BASE
#else
#define BASE	%eax
	call	1f
1:	pop	BASE
	add	$2f-1b, BASE
#endif

	vmovdqa	0(BASE), %ymm0
	vmovdqa	1*32(BASE), %ymm1
	vmovdqa	2*32(BASE), %ymm2
	vmovdqa	3*32(BASE), %ymm3
	vmovdqa	4*32(BASE), %ymm4
	vmovdqa	5*32(BASE), %ymm5
	vmovdqa	6*32(BASE), %ymm6
	vmovdqa	7*32(BASE), %ymm7

#ifdef __x86_64__
	vmovdqa	8*32(BASE), %ymm8
	vmovdqa	9*32(BASE), %ymm9
	vmovdqa	10*32(BASE), %ymm10
	vmovdqa	11*32(BASE), %ymm11
	vmovdqa	12*32(BASE), %ymm12
	vmovdqa	13*32(BASE), %ymm13
	vmovdqa	14*32(BASE), %ymm14
	vmovdqa	15*32(BASE), %ymm15
#endif

	xor	%eax, %eax
	sahf				/* init eflags */

	mov	$0x12345678, %eax
	mov	$0x9abcdef0, %ebx
	mov	$0x97361234, %ecx
	mov	$0x84310284, %edx
	mov	$0x83624173, %edi
	mov	$0xfaebfaeb, %esi
	mov	$0x84610123, %ebp

#ifdef __x86_64__
	movq	$0x123456789abcdef0, %r8
	movq	$0xaaaabbbbccccdddd, %r9
	movq	$0x1010101010101010, %r10
	movq	$0x1111111111111111, %r11
	movq	$0x1212121212121212, %r12
	movq	$0x1313131313131313, %r13
	movq	$0x1414141414141414, %r14
	movq	$0x1515151515151515, %r15
#endif

/* do compare */
	ud1	%eax, %eax

/* exit test */
	ud1	%ecx, %eax

	.p2align 16
2:
	.set	i, 0
	.rept	256
	.byte	i, i, i, i
	.set	i, i + 1
	.endr
