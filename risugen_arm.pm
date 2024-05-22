#!/usr/bin/perl -w
###############################################################################
# Copyright (c) 2010 Linaro Limited
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
#
# Contributors:
#     Peter Maydell (Linaro) - initial implementation
#     Claudio Fontana (Linaro) - initial aarch64 support
#     Jose Ricardo Ziviani (IBM) - modularize risugen
###############################################################################

# risugen -- generate a test binary file for use with risu
# See 'risugen --help' for usage information.
package risugen_arm;

use strict;
use warnings;

use risugen_common;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(write_test_code);

# Note that we always start in ARM mode even if the C code was compiled for
# thumb because we are called by branch to a lsbit-clear pointer.
# is_thumb tracks the mode we're actually currently in (ie should we emit
# an arm or thumb insn?); test_thumb tells us which mode we need to switch
# to to emit the insns under test.
# Use .mode aarch64 to start in Aarch64 mode.

my $is_aarch64 = 0; # are we in aarch64 mode?
# For aarch64 it only makes sense to put the mode directive at the
# beginning, and there is no switching away from aarch64 to arm/thumb.

my $is_thumb = 0;   # are we currently in Thumb mode?
my $test_thumb = 0; # should test code be Thumb mode?

# Maximum alignment restriction permitted for a memory op.
my $MAXALIGN = 64;
# Maximum offset permitted for a memory op.
my $MEMBLOCKLEN = 8192;

# An instruction pattern as parsed from the config file turns into
# a record like this:
#   name          # name of the pattern
#   width         # 16 or 32
#   fixedbits     # values of the fixed bits
#   fixedbitmask  # 1s indicate locations of the fixed bits
#   blocks        # hash of blockname->contents (for constraints etc)
#   fields        # array of arrays, each element is [ varname, bitpos, bitmask ]
#
# We store these in the insn_details hash.

# Valid block names (keys in blocks hash)
my %valid_blockname = ( constraints => 1, memory => 1 );

# used for aarch64 only for now
sub data_barrier()
{
    if ($is_aarch64) {
        printf "\tdsb\tsy\n";
    }
}

# The space 0xE7F___F_ is guaranteed to always UNDEF
# and not to be allocated for insns in future architecture
# revisions. So we use it for our 'do comparison' and
# 'end of test' instructions.
# We fill in the middle bit with a randomly selected
# 'e5a' just in case the space is being used by somebody
# else too.

# For Thumb the equivalent space is 0xDExx
# and we use 0xDEEx.

# So the last nibble indicates the desired operation:
my $OP_COMPARE = 0;        # compare registers
my $OP_TESTEND = 1;        # end of test, stop
my $OP_SETMEMBLOCK = 2;    # r0 is address of memory block (8192 bytes)
my $OP_GETMEMBLOCK = 3;    # add the address of memory block to r0
my $OP_COMPAREMEM = 4;     # compare memory block

sub xr($)
{
    my ($reg) = @_;
    if (!$is_aarch64) {
        return "r$reg";
    } elsif ($reg == 31) {
        return "xzr";
    } else {
        return "x$reg";
    }
}

sub write_thumb_risuop($)
{
    my ($op) = @_;
    printf "\t.inst.n\t%#x\n", 0xdee0 | $op;
}

sub write_arm_risuop($)
{
    my ($op) = @_;
    printf "\t.inst\t%#x\n", 0xe7fe5af0 | $op;
}

sub write_aarch64_risuop($)
{
    # instr with bits (28:27) == 0 0 are UNALLOCATED
    my ($op) = @_;
    printf "\t.inst\t%#x\n", 0x00005af0 | $op;
}

sub write_risuop($)
{
    my ($op) = @_;
    if ($is_thumb) {
        write_thumb_risuop($op);
    } elsif ($is_aarch64) {
        write_aarch64_risuop($op);
    } else {
        write_arm_risuop($op);
    }
}

sub write_data32($)
{
    my ($data) = @_;
    printf "\t.word\t%#08x\n", $data;
}

sub write_switch_to_thumb()
{
    # Switch to thumb if we're not already there
    if (!$is_thumb) {
        # Note that we have to clean up R0 afterwards so it isn't
        # tainted with a value which depends on PC.
        printf "\tadd\tr0, pc, #1\n";
        printf "\tbx\tr0\n";
        printf ".thumb\n";
        printf "\teors\tr0, r0\n";
        $is_thumb = 1;
    }
}

sub write_switch_to_arm()
{
    # Switch to ARM mode if we are in thumb mode
    if ($is_thumb) {
        printf "\t.balign\t4\n";
        printf "\tbx\tpc\n";
        printf "\tnop\n";
        printf ".arm\n";
        $is_thumb = 0;
    }
}

sub write_switch_to_test_mode()
{
    # Switch to whichever mode we need for test code
    if ($is_aarch64) {
        return; # nothing to do
    }

    if ($test_thumb) {
        write_switch_to_thumb();
    } else {
        write_switch_to_arm();
    }
}

sub write_add_rri($$$)
{
    my ($rd, $rn, $i) = @_;
    printf "\tadd\t%s, %s, #%d\n", xr($rd), xr($rn), $i;
}

sub write_sub_rrr($$$)
{
    my ($rd, $rn, $rm) = @_;
    printf "\tsub\t%s, %s, %s\n", xr($rd), xr($rn), xr($rm);
}

# valid shift types
my $SHIFT_LSL = "lsl";
my $SHIFT_LSR = "lsr";
my $SHIFT_ASR = "asr";
my $SHIFT_ROR = "ror";

sub write_sub_rrrs($$$$$)
{
    # sub rd, rn, rm, shifted
    my ($rd, $rn, $rm, $type, $imm) = @_;
    $type = $SHIFT_LSL if $imm == 0;

    printf "\tsub\t%s, %s, %s, %s #%d\n",
           xr($rd), xr($rn), xr($rm), $type, $imm;
}

sub write_mov_rr($$)
{
    my ($rd, $rm) = @_;
    printf "\tmov\t%s, %s\n", xr($rd), xr($rm);
}

sub write_mov_ri($$)
{
    my ($rd, $imm) = @_;
    my $highhalf = ($imm >> 16) & 0xffff;

    if (!$is_aarch64) {
        printf "\tmovw\t%s, #%#x\n", xr($rd), 0xffff & $imm;
        if ($highhalf != 0) {
            printf "\tmovt\t%s, #%#x\n", xr($rd), $highhalf;
        }
    } elsif ($imm < 0) {
        printf "\tmovn\t%s, #%#x\n", xr($rd), 0xffff & ~$imm;
        if ($highhalf != 0xffff) {
            printf "\tmovk\t%s, #%#x, lsl #16\n", xr($rd), $highhalf;
        }
    } else {
        printf "\tmovz\t%s, #%#x\n", xr($rd), 0xffff & $imm;
        if ($highhalf != 0) {
            printf "\tmovk\t%s, #%#x, lsl #16\n", xr($rd), $highhalf;
        }
    }
}

sub write_addpl_rri($$$)
{
    my ($rd, $rn, $imm) = @_;
    die "write_addpl: invalid operation for this arch.\n" if (!$is_aarch64);

    printf "\taddpl\t%s, %s, #%d\n", xr($rd), xr($rn), $imm;
}

sub write_addvl_rri($$$)
{
    my ($rd, $rn, $imm) = @_;
    die "write_addvl: invalid operation for this arch.\n" if (!$is_aarch64);

    printf "\taddvl\t%s, %s, #%d\n", xr($rd), xr($rn), $imm;
}

sub write_rdvl_ri($$)
{
    my ($rd, $imm) = @_;
    die "write_rdvl: invalid operation for this arch.\n" if (!$is_aarch64);

    printf "\trdvl\t%s, #%d\n", xr($rd), $imm;
}

sub write_madd_rrrr($$$$)
{
    my ($rd, $rn, $rm, $ra) = @_;
    die "write_madd: invalid operation for this arch.\n" if (!$is_aarch64);

    printf "\tmadd\t%s, %s, %s, %s\n", xr($rd), xr($rn), xr($rm), xr($ra);
}

sub write_msub_rrrr($$$$)
{
    my ($rd, $rn, $rm, $ra) = @_;
    die "write_msub: invalid operation for this arch.\n" if (!$is_aarch64);

    printf "\tmsub\t%s, %s, %s, %s\n", xr($rd), xr($rn), xr($rm), xr($ra);
}

sub write_mul_rrr($$$)
{
    my ($rd, $rn, $rm) = @_;

    printf "\tmul\t%s, %s, %s\n", xr($rd), xr($rn), xr($rm);
}

# write random fp value of passed precision (1=single, 2=double, 4=quad)
sub write_random_fpreg_var($)
{
    my ($precision) = @_;
    my $randomize_low = 0;

    if ($precision != 1 && $precision != 2 && $precision != 4) {
        die "write_random_fpreg: invalid precision.\n";
    }

    my ($low, $high);
    my $r = rand(100);
    if ($r < 5) {
        # +-0 (5%)
        $low = $high = 0;
        $high |= 0x80000000 if (rand() < 0.5);
    } elsif ($r < 10) {
        # NaN (5%)
        # (plus a tiny chance of generating +-Inf)
        $randomize_low = 1;
        $high = rand(0xffffffff) | 0x7ff00000;
    } elsif ($r < 15) {
        # Infinity (5%)
        $low = 0;
        $high = 0x7ff00000;
        $high |= 0x80000000 if (rand() < 0.5);
    } elsif ($r < 30) {
        # Denormalized number (15%)
        # (plus tiny chance of +-0)
        $randomize_low = 1;
        $high = rand(0xffffffff) & ~0x7ff00000;
    } else {
        # Normalized number (70%)
        # (plus a small chance of the other cases)
        $randomize_low = 1;
        $high = rand(0xffffffff);
    }

    for (my $i = 1; $i < $precision; $i++) {
        if ($randomize_low) {
            $low = rand(0xffffffff);
        }
        printf "\t.word\t%#08x\n", $low;
    }
    printf "\t.word\t%#08x\n", $high;
}

sub write_random_arm_fpreg()
{
    # Write out 64 bits of random data intended to
    # initialise an FP register.
    # We tweak the "randomness" here to increase the
    # chances of picking interesting values like
    # NaN, -0.0, and so on, which would be unlikely
    # to occur if we simply picked 64 random bits.
    if (rand() < 0.5) {
        write_random_fpreg_var(2); # double
    } else {
        write_random_fpreg_var(1); # single
        write_random_fpreg_var(1); # single
    }
}

sub write_random_arm_regdata($)
{
    my ($fp_enabled) = @_;
    my $vfp = $fp_enabled ? 2 : 0; # 0 : no vfp, 1 : vfpd16, 2 : vfpd32
    write_switch_to_arm();

    # initialise all registers
    printf "\tadr\tr0, 0f\n";
    printf "\tb\t1f\n";

    printf "\t.balign %d\n", $fp_enabled ? 8 : 4;
    printf "0:\n";

    for (0..(($vfp * 16) - 1)) { # NB: never done for $vfp == 0
        write_random_arm_fpreg();
    }
    #  .word [14 words of data for r0..r12,r14]
    for (0..13) {
        write_data32(rand(0xffffffff));
    }

    printf "1:\n";
    if ($vfp == 1) {
        printf "\tvldmia\tr0!, {d0-d15}\n";
    } elsif ($vfp == 2) {
        printf "\tvldmia\tr0!, {d0-d15}\n";
        printf "\tvldmia\tr0!, {d16-d31}\n";
    }
    printf "\tldmia\tr0, {r0-r12,r14}\n";

    # clear the flags (NZCVQ and GE)
    printf "\tmsr\tAPSR_nzcvqg, #0\n";
}

sub write_random_aarch64_fpdata()
{
    # load floating point / SIMD registers
    printf "\t.data\n";
    printf "\t.balign\t16\n";
    printf "1:\n";

    for (0..31) {
        write_random_fpreg_var(4); # quad
    }

    printf "\t.text\n";
    printf "\tadr\tx0, 1b\n";

    for (my $rt = 0; $rt < 32; $rt += 4) {
        printf "\tld1\t{v%d.2d-v%d.2d}, [x0], #64\n", $rt, $rt + 3;
    }
}

sub write_random_aarch64_svedata()
{
    # Max SVE size
    my $vq = 16;

    # Load SVE registers
    printf "\t.data\n";
    printf "\t.balign\t16\n";
    printf "1:\n";

    for (my $i = 0; $i < 32 * 16 * $vq; $i += 16) {
        write_random_fpreg_var(4); # quad
    }
    for (my $i = 0; $i < 16 * 2 * $vq; $i += 4) {
        write_data32(rand(0xffffffff));
    }

    printf "\t.text\n";
    printf "\tadr\tx0, 1b\n";

    for (my $rt = 0; $rt <= 31; $rt++) {
        printf "\tldr\tz%d, [x0, #%d, mul vl]\n", $rt, $rt;
    }
    write_add_rri(0, 0, 32 * 16 * $vq);

    for (my $rt = 0; $rt <= 15; $rt++) {
        printf "\tldr\tp%d, [x0, #%d, mul vl]\n", $rt, $rt;
    }
}

sub write_random_aarch64_regdata($$)
{
    my ($fp_enabled, $sve_enabled) = @_;

    # clear flags
    printf "\tmsr\tnzcv, xzr\n";

    # Load floating point / SIMD registers
    # (one or the other as they overlap)
    if ($sve_enabled) {
        write_random_aarch64_svedata();
    } elsif ($fp_enabled) {
        write_random_aarch64_fpdata();
    }

    # general purpose registers
    for (my $i = 0; $i <= 30; $i++) {
        # TODO full 64 bit pattern instead of 32
        write_mov_ri($i, rand(0xffffffff));
    }
}

sub write_random_register_data($$)
{
    my ($fp_enabled, $sve_enabled) = @_;

    if ($is_aarch64) {
        write_random_aarch64_regdata($fp_enabled, $sve_enabled);
    } else {
        write_random_arm_regdata($fp_enabled);
    }

    write_risuop($OP_COMPARE);
}

sub write_memblock_setup()
{
    # Write code which sets up the memory block for loads and stores.
    # We set r0 to point to a block of 8K length
    # of random data, aligned to the maximum desired alignment.
    write_switch_to_arm();

    printf "\tadr\t%s, 2f\n", xr(0);
    if ($is_aarch64) {
        printf "\t.data\n";
    } else {
        printf "\tb\t3f\n";
    }

    printf "\t.balign\t%d\n", $MAXALIGN;
    printf "2:\n";

    for (my $i = 0; $i < $MEMBLOCKLEN; $i += 4) {
        write_data32(rand(0xffffffff));
    }

    if ($is_aarch64) {
        printf "\t.text\n";
    } else {
        printf "3:\n";
    }

    write_risuop($OP_SETMEMBLOCK);
}

sub write_set_fpscr_arm($)
{
    my ($fpscr) = @_;
    write_switch_to_arm();
    write_mov_ri(0, $fpscr);
    printf "\tvmsr\tfpscr, r0\n";
}

sub write_set_fpscr_aarch64($)
{
    # on aarch64 we have split fpcr and fpsr registers.
    # Status will be initialized to 0, while user param controls fpcr.
    my ($fpcr) = @_;
    printf "\tmsr\tfpsr, xzr\n";
    write_mov_ri(0, $fpcr);
    printf "\tmsr\tfpcr, x0\n";
}

sub write_set_fpscr($)
{
    my ($fpscr) = @_;
    if ($is_aarch64) {
        write_set_fpscr_aarch64($fpscr);
    } else {
        write_set_fpscr_arm($fpscr);
    }
}

# Functions used in memory blocks to handle addressing modes.
# These all have the same basic API: they get called with parameters
# corresponding to the interesting fields of the instruction,
# and should generate code to set up the base register to be
# valid. They must return the register number of the base register.
# The last (array) parameter lists the registers which are trashed
# by the instruction (ie which are the targets of the load).
# This is used to avoid problems when the base reg is a load target.

# Global used to communicate between align(x) and reg() etc.
my $alignment_restriction;

sub align($)
{
    my ($a) = @_;
    if (!is_pow_of_2($a) || ($a < 0) || ($a > $MAXALIGN)) {
        die "bad align() value $a\n";
    }
    $alignment_restriction = $a;
}

sub get_offset()
{
    # We require the offset to not be within 256 bytes of either
    # end, to (more than) allow for the worst case data transfer, which is
    # 16 * 64 bit regs
    return (rand($MEMBLOCKLEN - 512) + 256) & ~($alignment_restriction - 1);
}

# Return the log2 of the memory size of an operation described by dtype.
sub dtype_msz($)
{
    my ($dtype) = @_;
    my $dth = $dtype >> 2;
    my $dtl = $dtype & 3;
    return $dtl >= $dth ? $dth : 3 - $dth;
}

sub reg_plus_imm($$@)
{
    # Handle reg + immediate addressing mode
    my ($base, $imm, @trashed) = @_;
    my $offset = get_offset() - $imm;

    if ($is_aarch64) {
        printf "\tadr\tx%d, 2b%+d\n", $base, $offset;
    } else {
        write_mov_ri(0, $offset);
        write_risuop($OP_GETMEMBLOCK);
        if ($base != 0) {
            write_mov_rr($base, 0);
            write_mov_ri(0, 0);
        }
    }
    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg($@)
{
    # Handle reg addressing mode
    my ($base, @trashed) = @_;
    return reg_plus_imm($base, 0, @trashed);
}

sub reg_plus_imm_pl($$@)
{
    # Handle reg + immediate addressing mode
    my ($base, $imm, @trashed) = @_;
    my $offset = get_offset();

    printf "\tadr\tx%d, 2b+%+d\n", $base, $offset;

    # Set the basereg by doing the inverse of the
    # addressing mode calculation, ie base = r0 - imm
    #
    # Note that addpl has a 6-bit immediate, but ldr has a 9-bit
    # immediate, so we need to be able to support larger immediates.
    if (-$imm >= -32 && -$imm <= 31) {
        write_addpl_rri($base, $base, -$imm);
    } else {
        # Select two temporaries (no need to zero afterward, since we don't
        # leave anything which depends on the location of the memory block.
        my $t1 = $base == 0 ? 1 : 0;
        my $t2 = $base == 1 ? 2 : 1;
        write_mov_ri($t1, 0);
        write_addpl_rri($t1, $t1, 1);
        write_mov_ri($t2, -$imm);
        write_madd_rrrr($base, $t1, $t2, $base);
    }
    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg_plus_imm_vl($$$@)
{
    # The usual address formulation is
    #   elements = VL DIV esize
    #   mbytes = msize DIV 8
    #   addr = base + imm * elements * mbytes
    # Here we compute
    #   scale = log2(esize / msize)
    #   base + (imm * VL) >> scale
    my ($base, $imm, $scale, @trashed) = @_;
    my $offset = get_offset();
    my $t1 = $base == 0 ? 1 : 0;
    my $t2 = $base == 1 ? 2 : 1;

    printf "\tadr\tx%d, 2b+%+d\n", $base, $offset;

    # Set the basereg by doing the inverse of the addressing calculation.
    # Note that rdvl/addvl have a 6-bit immediate, but ldr has a 9-bit
    # immediate, so we need to be able to support larger immediates.

    use integer;
    my $mul = 1 << $scale;
    my $imm_div = $imm / $mul;

    if ($imm == $imm_div * $mul && -$imm_div >= -32 && -$imm_div <= 31) {
        write_addvl_rri($base, $base, -$imm_div);
    } elsif ($imm >= -32 && $imm <= 31) {
        write_rdvl_ri($t1, $imm);
        write_sub_rrrs($base, $base, $t1, $SHIFT_ASR, $scale);
    } else {
        write_rdvl_ri($t1, 1);
        if ($scale == 0) {
            write_mov_ri($t2, -$imm);
            write_madd_rrrr($base, $t1, $t2, $base);
        } else {
            write_mov_ri($t2, $imm);
            write_mul_rrr($t1, $t1, $t2);
            write_sub_rrrs($base, $base, $t1, $SHIFT_ASR, $scale);
        }
    }
    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg_minus_imm($$@)
{
    my ($base, $imm, @trashed) = @_;
    return reg_plus_imm($base, -$imm, @trashed);
}

sub reg_plus_reg_shifted($$$@)
{
    # handle reg + reg LSL imm addressing mode
    my ($base, $idx, $shift, @trashed) = @_;
    my $offset = get_offset();

    if ($shift < 0 || $shift > 4 || (!$is_aarch64 && $shift == 4)) {
        print ("\n(shift) $shift\n");
        print ("\n(arch) $is_aarch64\n");
        die "reg_plus_reg_shifted: bad shift size\n";
    }

    if ($is_aarch64) {
        printf "\tadr\tx%d, 2b%+d\n", $base, $offset;
        write_sub_rrrs($base, $base, $idx, $SHIFT_LSL, $shift);
    } else {
        my $savedidx = 0;

        if ($idx == 0) {
            # save the index into some other register for the
            # moment, because the risuop will trash r0
            $idx = 1;
            $idx++ if $idx == $base;
            $savedidx = 1;
            write_mov_rr($idx, 0);
        }

        write_mov_ri(0, $offset);
        write_risuop($OP_GETMEMBLOCK);
        write_sub_rrrs($base, 0, $idx, $SHIFT_LSL, $shift);

        if ($savedidx) {
            # We can move idx back to r0 now
            write_mov_rr(0, $idx);
        } elsif ($base != 0) {
            write_mov_ri(0, 0);
        }
    }
    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg_plus_reg($$@)
{
    my ($base, $idx, @trashed) = @_;
    return reg_plus_reg_shifted($base, $idx, 0, @trashed);
}

sub gen_one_insn($$)
{
    # Given an instruction-details array, generate an instruction
    my $constraintfailures = 0;

    INSN: while(1) {
        my ($forcecond, $rec) = @_;
        my $insn = int(rand(0xffffffff));
        my $insnname = $rec->{name};
        my $insnwidth = $rec->{width};
        my $fixedbits = $rec->{fixedbits};
        my $fixedbitmask = $rec->{fixedbitmask};
        my $constraint = $rec->{blocks}{"constraints"};
        my $memblock = $rec->{blocks}{"memory"};

        $insn &= ~$fixedbitmask;
        $insn |= $fixedbits;
        for my $tuple (@{ $rec->{fields} }) {
            my ($var, $pos, $mask) = @$tuple;
            my $val = ($insn >> $pos) & $mask;
            # XXX (claudio) ARM-specific - maybe move to arm.risu?
            # Check constraints here:
            # not allowed to use or modify sp or pc
            if (!$is_aarch64) {
                next INSN if ($var =~ /^r/ && (($val == 13) || ($val == 15)));
                # Some very arm-specific code to force the condition field
                # to 'always' if requested.
                if ($forcecond) {
                    if ($var eq "cond") {
                        $insn &= ~ ($mask << $pos);
                        $insn |= (0xe << $pos);
                    }
                }
            }
        }
        if (defined $constraint) {
            # user-specified constraint: evaluate in an environment
            # with variables set corresponding to the variable fields.
            my $v = eval_with_fields($insnname, $insn, $rec, "constraints", $constraint);
            if (!$v) {
                $constraintfailures++;
                if ($constraintfailures > 10000) {
                    print "10000 consecutive constraint failures for $insnname constraints string:\n$constraint\n";
                    exit (1);
                }
                next INSN;
            }
        }

        # OK, we got a good one
        $constraintfailures = 0;

        my $basereg;

        if (defined $memblock) {
            # This is a load or store. We simply evaluate the block,
            # which is expected to be a call to a function which emits
            # the code to set up the base register and returns the
            # number of the base register.
            # Default alignment requirement for ARM is 4 bytes,
            # we use 16 for Aarch64, although often unnecessary and overkill.
            if ($is_aarch64) {
                align(16);
            } else {
                align(4);
            }
            $basereg = eval_with_fields($insnname, $insn, $rec, "memory", $memblock);

            if ($is_aarch64) {
                data_barrier();
            }
        }

        if ($is_thumb) {
            if ($insnwidth == 32) {
                printf "\t.inst.w\t%#08x\n", $insn;
            } else {
                # For a 16 bit Thumb instruction the generated insn is in
                # the high halfword (because we didn't bother to readjust
                # all the bit positions in parse_config_file() when we
                # got to the end and found we only had 16 bits).
                printf "\t.inst.n\t%#04x\n", $insn >> 16;
            }
        } else {
            # ARM is simple, always a 32 bit word
            printf "\t.inst\t%#08x\n", $insn;
        }

        if (defined $memblock) {
            # Clean up following a memory access instruction:
            # we need to turn the (possibly written-back) basereg
            # into an offset from the base of the memory block,
            # to avoid making register values depend on memory layout.
            # $basereg -1 means the basereg was a target of a load
            # (and so it doesn't contain a memory address after the op)

            if ($is_aarch64) {
                data_barrier();
            }

            if ($basereg != -1) {
                if ($is_aarch64) {
                    printf "\tadr\tx0, 2b\n";
                } else {
                    write_mov_ri(0, 0);
                    write_risuop($OP_GETMEMBLOCK);
                }
                write_sub_rrr($basereg, $basereg, 0);
                write_mov_ri(0, 0);
            }
            write_risuop($OP_COMPAREMEM);
        }
        return;
    }
}

sub write_test_code($$$$$$$$)
{
    my ($params) = @_;

    my $arch = $params->{ 'arch' };
    my $subarch = $params->{ 'subarch' };

    if ($subarch && $subarch eq 'aarch64') {
        $test_thumb = 0;
        $is_aarch64 = 1;
    } elsif ($subarch && $subarch eq 'thumb') {
        $test_thumb = 1;
        $is_aarch64 = 0;
    } else {
        $test_thumb = 0;
        $is_aarch64 = 0;
    }

    my $condprob = $params->{ 'condprob' };
    my $fpscr = $params->{ 'fpscr' };
    my $numinsns = $params->{ 'numinsns' };
    my $fp_enabled = $params->{ 'fp_enabled' };
    my $sve_enabled = $params->{ 'sve_enabled' };
    my $outfile = $params->{ 'outfile' };

    my %insn_details = %{ $params->{ 'details' } };
    my @keys = @{ $params->{ 'keys' } };

    open_asm($outfile);

    printf "\t.text\n";
    if (!$is_aarch64) {
	printf "\t.syntax unified\n";
        printf "\t.arm\n";
        printf "\t.arch armv7-a\n";
        printf "\t.fpu neon\n" if ($fp_enabled);
    }

    # convert from probability that insn will be conditional to
    # probability of forcing insn to unconditional
    $condprob = 1 - $condprob;

    # TODO better random number generator?
    srand(0);

    print STDOUT "Generating code using patterns: @keys...\n";
    progress_start(78, $numinsns);

    if ($fp_enabled) {
        write_set_fpscr($fpscr);
    }

    if (grep { defined($insn_details{$_}->{blocks}->{"memory"}) } @keys) {
        write_memblock_setup();
    }
    # memblock setup doesn't clean its registers, so this must come afterwards.
    write_random_register_data($fp_enabled, $sve_enabled);
    write_switch_to_test_mode();

    for my $i (1..$numinsns) {
        my $insn_enc = $keys[int rand (@keys)];
        #dump_insn_details($insn_enc, $insn_details{$insn_enc});
        my $forcecond = (rand() < $condprob) ? 1 : 0;
        gen_one_insn($forcecond, $insn_details{$insn_enc});
        write_risuop($OP_COMPARE);
        # Rewrite the registers periodically. This avoids the tendency
        # for the VFP registers to decay to NaNs and zeroes.
        if (($i % 100) == 0) {
            write_random_register_data($fp_enabled, $sve_enabled);
            write_switch_to_test_mode();
        }
        progress_update($i);
    }
    write_risuop($OP_TESTEND);
    progress_end();

    close_asm();
    assemble_and_link($outfile, $params->{ 'cross_prefix' },
                      $params->{ 'keep' });
}

1;
