
/*
 * Trees/arm_large_tree.s
 * A large ARM64 (AArch64) assembly program for Linux (GNU assembler syntax).
 * Builds a perfect binary tree to a configurable depth (default 12 -> 4095 nodes),
 * computes its height recursively, and prints node count and height using printf.
 *
 * Build: aarch64-linux-gnu-gcc -nostartfiles Trees/arm_large_tree.s -o arm_large_tree
 * Run: ./arm_large_tree
 *
 * Notes:
 * - Uses malloc and printf from libc.
 * - Node struct (24 bytes):
 *     offset 0: 64-bit integer value
 *     offset 8: pointer to left child
 *     offset 16: pointer to right child
 *
 */

    .text
    .global main
    .extern malloc
    .extern printf
    .extern free

    .align 3

/* format strings */
fmt_nodes:
    .asciz "Built tree with %ld nodes and depth %ld\n"

/* node struct size */
.equ NODE_SIZE, 24

/* global place to store node count (64-bit) */
    .data
    .align 3
g_node_count:
    .quad 0

    .text

/*
 * main()
 * Build a tree of default depth 12 (can be changed below), compute height and print.
 */
.type main, %function
main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* depth = 12 (change here if you want a different default) */
    mov x0, #12
    bl build_tree_from_depth    /* returns base pointer in x0 and sets g_node_count */

    /* x0 = base pointer */
    mov x1, x0                  /* keep base pointer in x1 if needed */

    /* compute height: pass root pointer (base) */
    mov x0, x1
    bl compute_height           /* result in x0 */
    mov x2, x0                  /* height -> x2 */

    /* load node count from g_node_count */
    adrp x0, g_node_count@PAGE
    ldr x0, [x0, g_node_count@PAGEOFF]

    /* print the summary: printf(fmt_nodes, node_count, height); */
    mov x1, x0                  /* node_count -> x1 (arg1) */
    mov x2, x2                  /* height already in x2 (arg2) */
    adrp x0, fmt_nodes@PAGE
    add x0, x0, fmt_nodes@PAGEOFF
    /* per AArch64 calling: x0=format, x1=arg1, x2=arg2 */
    bl printf

    /* free memory: call free(base) */
    mov x0, x1
    bl free

    /* return 0 */
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret


/*
 * build_tree_from_depth(depth)
 * Input: x0 = depth (bits)
 * Returns: x0 = base pointer to contiguous node array
 * Side-effect: writes node count to g_node_count
 */
.type build_tree_from_depth, %function
build_tree_from_depth:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* compute node_count = (1 << depth) - 1
     * We'll compute by loop shifting left.
     */
    mov x1, #1          /* one */
    mov x2, x0          /* depth -> x2 */
    mov x3, #0          /* counter of shifts */
    cbz x2, .L_depth_zero

.L_shift_loop:
    lsl x1, x1, #1      /* x1 <<= 1 */
    add x3, x3, #1
    cmp x3, x2
    blt .L_shift_loop

    /* x1 == (1 << depth) */
    sub x1, x1, #1      /* node_count = x1 - 1 */

    /* store node_count to g_node_count */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    str x1, [x4]

    /* compute total allocation size = node_count * NODE_SIZE (24)
     * We'll compute size = node_count * 24 = node_count*16 + node_count*8
     */
    lsl x5, x1, #4      /* x5 = node_count << 4  ( *16 ) */
    lsl x6, x1, #3      /* x6 = node_count << 3  ( *8 ) */
    add x5, x5, x6      /* x5 = size */

    /* call malloc(size)
     * x0 = size
     */
    mov x0, x5
    bl malloc
    /* x0 returned base pointer */

    /* If malloc returned NULL, return NULL */
    cbz x0, .L_alloc_failed

    /* base pointer in x7 for convenience */
    mov x7, x0

    /* We'll initialize nodes in a loop for i=0..node_count-1 */
    /* Use registers:
     * x8 = i (index)
     * x9 = node_count
     * x10 = temp for addr calculation
     */
    mov x8, #0
    mov x9, x1          /* node_count */

.L_init_loop:
    cmp x8, x9
    bge .L_init_done

    /* compute offset = i * NODE_SIZE (24)
     * offset = (i << 4) + (i << 3)
     */
    lsl x10, x8, #4     /* i<<4 */
    lsl x11, x8, #3     /* i<<3 */
    add x10, x10, x11   /* x10 = offset */

    /* node_ptr = base + offset */
    add x12, x7, x10

    /* store node->val = i
     * store 64-bit integer value at offset 0
     */
    str x8, [x12]

    /* compute left index = 2*i + 1 */
    add x13, x8, x8     /* x13 = 2*i */
    add x13, x13, #1
    cmp x13, x9
    bhs .L_left_null     /* if left_index >= node_count -> NULL */
    /* left_ptr = base + left_index * NODE_SIZE */
    lsl x14, x13, #4
    lsl x15, x13, #3
    add x14, x14, x15
    add x14, x7, x14
    str x14, [x12, #8]  /* store left pointer at offset 8 */
    b .L_right_part

.L_left_null:
    mov x16, #0
    str x16, [x12, #8]

.L_right_part:
    /* compute right index = 2*i + 2 */
    add x13, x8, x8
    add x13, x13, #2
    cmp x13, x9
    bhs .L_right_null
    lsl x14, x13, #4
    lsl x15, x13, #3
    add x14, x14, x15
    add x14, x7, x14
    str x14, [x12, #16] /* store right pointer at offset 16 */
    b .L_continue_loop

.L_right_null:
    mov x16, #0
    str x16, [x12, #16]

.L_continue_loop:
    add x8, x8, #1
    b .L_init_loop

.L_init_done:
    /* return base pointer in x0 */
    mov x0, x7
    b .L_build_done

.L_alloc_failed:
    /* store zero node count just in case */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    mov x1, #0
    str x1, [x4]
    mov x0, #0

.L_build_done:
    ldp x29, x30, [sp], #16
    ret

.L_depth_zero:
    /* depth == 0 -> node_count = 0, return NULL */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    mov x1, #0
    str x1, [x4]
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret


/*
 * compute_height(node_ptr)
 * Recursive function
 * Input: x0 = pointer to node or 0
 * Return: x0 = height (64-bit)
 */
.type compute_height, %function
compute_height:
    /* prologue: save frame and callee-saved registers we use (x19,x20) */
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    stp x19, x20, [sp, #-16]!

    cbz x0, .L_height_zero

    /* preserve node pointer in x19 for loads after calls */
    mov x19, x0

    /* compute left height */
    ldr x1, [x19, #8]    /* left pointer */
    mov x0, x1
    bl compute_height
    mov x20, x0          /* left height in x20 */

    /* compute right height */
    ldr x1, [x19, #16]   /* right pointer */
    mov x0, x1
    bl compute_height
    /* right height in x0 */

    /* compare x20 and x0, take max */
    cmp x20, x0
    csel x0, x20, x0, gt
    /* add 1 */
    add x0, x0, #1

    /* epilogue */
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

.L_height_zero:
    mov x0, #0
    ldp x19, x20, [sp], #16
    ldp x29, x30, [sp], #16
    ret

    .size main, .-main

