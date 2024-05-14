#!/usr/bin/perl -w
###############################################################################
# Copyright (c) 2024 Linaro Limited
# All rights reserved. This program and the accompanying materials
# are made available under the terms of the Eclipse Public License v1.0
# which accompanies this distribution, and is available at
# http://www.eclipse.org/legal/epl-v10.html
###############################################################################

# risugen -- generate a test binary file for use with risu
# See 'risugen --help' for usage information.
package risugen_sparc64;

use strict;
use warnings;

use risugen_common;

require Exporter;

our @ISA    = qw(Exporter);
our @EXPORT = qw(write_test_code);

my $periodic_reg_random = 1;

# Maximum alignment restriction permitted for a memory op.
my $MAXALIGN = 64;
my $MAXBLOCK = 2048;
my $PARAMREG = 15;         # %o7

my $OP_COMPARE = 0;        # compare registers
my $OP_TESTEND = 1;        # end of test, stop
my $OP_SETMEMBLOCK = 2;    # g1 is address of memory block (8192 bytes)
my $OP_GETMEMBLOCK = 3;    # add the address of memory block to g1
my $OP_COMPAREMEM = 4;     # compare memory block

my @GREGS = ( "%g0", "%g1", "%g2", "%g3", "%g4", "%g5", "%g6", "%g7",
              "%o0", "%o1", "%o2", "%o3", "%o4", "%o5", "%o6", "%o7",
              "%l0", "%l1", "%l2", "%l3", "%l4", "%l5", "%l6", "%l7",
              "%i0", "%i1", "%i2", "%i3", "%i4", "%i5", "%i6", "%i7" );

sub write_data32($)
{
    my ($val) = @_;
    printf "\t.word\t%#x\n", $val;
}

sub write_data64($)
{
    my ($val) = @_;
    printf "\t.quad\t%#x\n", $val;
}

sub write_risuop($)
{
    my ($op) = @_;
    printf "\tilltrap\t%#x\n", 0xdead0 + $op;
}

sub write_mov_rr($$)
{
    my ($rd, $rs) = @_;
    printf "\tmov\t%s,%s\n", $GREGS[$rs], $GREGS[$rd];
}

sub write_mov_ri($$)
{
    my ($rd, $imm) = @_;

    if (-0x1000 <= $imm < 0x1000) {
        printf "\tmov\t%d,%s\n", $imm, $GREGS[$rd];
    } else {
        my $immhi = $imm & 0xfffff000;
        my $immlo = $imm & 0x00000fff;

        if ($imm < 0) {
            $immhi ^= 0xfffff000;
            $immlo |= -0x1000;
        }
        printf "\tsethi\t%%hi(%d),%s\n", $immhi, $GREGS[$rd];
        if ($immlo != 0) {
            printf "\txor\t%s,%d,%s\n", $GREGS[$rd], $immlo, $GREGS[$rd];
        }
    }
}

sub write_add_rri($$$)
{
    my ($rd, $rs, $imm) = @_;
    die "bad imm!" if ($imm < -0x1000 || $imm >= 0x1000);

    printf "\txor\t%s,%d,%s\n", $GREGS[$rs], $imm, $GREGS[$rd];
}

sub write_sub_rrr($$$)
{
    my ($rd, $rs1, $rs2) = @_;

    printf "\tsub\t%s,%s,%s\n", $GREGS[$rs1], $GREGS[$rs2], $GREGS[$rd];
}

sub begin_datablock($$)
{
    my ($align, $label) = @_;
    die "bad align!" if ($align < 4 || $align > 255 || !is_pow_of_2($align));

    printf ".data\n";
    printf "\t.balign %d\n", $align;
    printf "%s:\n", $label;
}

sub end_datablock()
{
    printf ".text\n"
}

sub write_ref_datablock($$$$)
{
    my ($rd, $offset, $scratch, $label) = @_;

    printf "\trd\t%%pc,%s\n", $GREGS[$rd];
    printf "\tsethi\t%%pc22(%s+%d),%s\n",
           $label, $offset + 4, $GREGS[$scratch];
    printf "\tor\t%s,%%pc10(%s+%d),%s\n",
           $GREGS[$scratch], $label, $offset + 8, $GREGS[$scratch];
    printf "\tadd\t%s,%s,%s\n", $GREGS[$scratch], $GREGS[$rd], $GREGS[$rd];
}

sub write_random_register_data($$)
{
    my ($fp_enabled, $fsr) = @_;
    my $size = 32 * 8;

    if ($fp_enabled) {
        # random data for 32 double-precision regs plus %gsr
        $size += $fp_enabled ? 33 * 8 : 0;
    }

    begin_datablock(8, "1");
    for (my $i = 0; $i < $size; $i += 4) {
        write_data32(rand(0xffffffff));
    }
    if ($fp_enabled) {
        # %fsr gets constant data
        write_data64($fsr);
    }
    end_datablock();

    write_ref_datablock(1, 0, 2, "1b");

    # Load floating point / SIMD registers
    if ($fp_enabled) {
        for (my $rt = 0; $rt < 64; $rt += 2) {
            printf "\tldd\t[%s+%d],%%f%d\n", $GREGS[1], 32 * 8 + $rt * 4, $rt;
        }
        printf "\tldx\t[%s+%d],%s\n", $GREGS[1], 64 * 8, $GREGS[2];
        printf "\twr\t%s,0,%%gsr\n", $GREGS[2];
        printf "\tldx\t[%s+%d],%%fsr\n", $GREGS[1], 65 * 8;
    }

    # Load Y
    printf "\tldx\t[%s],%s\n", $GREGS[1], $GREGS[2];
    printf "\twr\t%s,0,%%y\n", $GREGS[2];

    # Clear flags
    printf "\twr\t%%g0,0,%%ccr\n";

    # Load general purpose registers
    for (my $i = 31; $i >= 1; --$i) {
        if (reg_ok($i)) {
            printf "\tldx\t[%s+%d],%s\n", $GREGS[1], $i * 8, $GREGS[$i];
        }
    }

    write_risuop($OP_COMPARE);
}

sub write_memblock_setup()
{
    begin_datablock($MAXALIGN, "2");

    for (my $i = 0; $i < $MAXBLOCK; $i += 4) {
        write_data32(rand(0xffffffff));
    }

    end_datablock();
    write_ref_datablock($PARAMREG, 0, 1, "2b");
    write_risuop($OP_SETMEMBLOCK);
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
    if (!is_pow_of_2($a) || !(0 < $a <= $MAXALIGN)) {
        die "bad align() value $a\n";
    }
    $alignment_restriction = $a;
}

sub gen_memblock_offset()
{
    # Generate a random offset within the memory block, of the correct
    # alignment. We require the offset to not be within 16 bytes of either
    # end, to (more than) allow for the worst case data transfer.
    return (rand($MAXBLOCK - 32) + 16) & ~($alignment_restriction - 1);
}

sub reg_ok($)
{
    my ($r) = @_;

    # Avoid special registers %g7 (tp), %o6 (sp), %i6 (fp).
    return $r != 7 && $r != 14 && $r != 30;
}

sub reg_plus_imm($$@)
{
    # Handle reg + immediate addressing mode
    my ($base, $imm, @trashed) = @_;
    my $offset = gen_memblock_offset();
    my $scratch = $base != 1 ? 1 : 2;

    write_ref_datablock($base, $offset - $imm, $scratch, "2b");
    write_mov_ri($scratch, 0);

    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub reg($@)
{
    my ($base, @trashed) = @_;
    return reg_plus_imm($base, 0, @trashed);
}

sub reg_plus_reg($$@)
{
    # Handle reg + reg addressing mode
    my ($base, $idx, @trashed) = @_;
    my $offset = gen_memblock_offset();
    my $scratch = 1;

    if ($base == $idx) {
        return -1;
    }

    while ($base == $scratch || $idx == $scratch) {
        ++$scratch;
    }

    write_ref_datablock($base, $offset, $scratch, "2b");
    write_mov_ri($scratch, 0);
    write_sub_rrr($base, $base, $idx);

    if (grep $_ == $base, @trashed) {
        return -1;
    }
    return $base;
}

sub gen_one_insn($)
{
    my ($rec) = @_;
    my $insnname = $rec->{name};
    my $insnwidth = $rec->{width};
    my $fixedbits = $rec->{fixedbits};
    my $fixedbitmask = $rec->{fixedbitmask};
    my $constraint = $rec->{blocks}{"constraints"};
    my $memblock = $rec->{blocks}{"memory"};

    # Given an instruction-details array, generate an instruction
    my $constraintfailures = 0;

    INSN: while(1) {
        my $insn = int(rand(0xffffffff));

        $insn &= ~$fixedbitmask;
        $insn |= $fixedbits;

        if (defined $constraint) {
            # User-specified constraint: evaluate in an environment
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
            align(16);
            $basereg = eval_with_fields($insnname, $insn, $rec, "memory", $memblock);
        }

	write_data32($insn);

        if (defined $memblock) {
            # Clean up following a memory access instruction:
            # we need to turn the (possibly written-back) basereg
            # into an offset from the base of the memory block,
            # to avoid making register values depend on memory layout.
            # $basereg -1 means the basereg was a target of a load
            # (and so it doesn't contain a memory address after the op)
            if ($basereg != -1) {
                write_mov_ri($basereg, 0);
            }
            write_risuop($OP_COMPAREMEM);
        }
        return;
    }
}

sub write_test_code($)
{
    my ($params) = @_;

    my $fp_enabled = $params->{ 'fp_enabled' };
    my $fsr = $params->{ 'fpscr' };
    my $numinsns = $params->{ 'numinsns' };
    my $outfile = $params->{ 'outfile' };

    my %insn_details = %{ $params->{ 'details' } };
    my @keys = @{ $params->{ 'keys' } };

    open_asm($outfile);

    # TODO better random number generator?
    srand(0);

    print STDOUT "Generating code using patterns: @keys...\n";
    progress_start(78, $numinsns);

    if (grep { defined($insn_details{$_}->{blocks}->{"memory"}) } @keys) {
        write_memblock_setup();
    }

    # memblock setup doesn't clean its registers, so this must come afterwards.
    write_random_register_data($fp_enabled, $fsr);

    for my $i (1..$numinsns) {
        my $insn_enc = $keys[int rand (@keys)];
        gen_one_insn($insn_details{$insn_enc});
        write_risuop($OP_COMPARE);
        # Rewrite the registers periodically.
        if ($periodic_reg_random && ($i % 100) == 0) {
            write_random_register_data($fp_enabled, $fsr);
        }
        progress_update($i);
    }
    write_risuop($OP_TESTEND);
    progress_end();

    close_asm();
    assemble_and_link($outfile, $params->{ 'cross_prefix' },
                      $params->{ 'keep' }, "-Av9a");
}

1;
