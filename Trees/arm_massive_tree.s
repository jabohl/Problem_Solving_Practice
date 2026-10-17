/*
 * Trees/arm_massive_tree.s
 * Massive AArch64 assembly program (GNU assembler syntax) for Linux.
 * - Default depth: 20 -> 1,048,575 nodes (~25 MB allocation at NODE_SIZE=24)
 * - Iterative builder (no recursion) that allocates a contiguous node array
 * - Multiple iterative analyses: sum of values, BFS levels, iterative inorder sample
 * - Uses malloc/free/printf from libc
 *
 * WARNING: This program will attempt to allocate ~25 MB + temporary buffers for depth=20.
 * Ensure the running system has sufficient memory. To change depth, edit the immediate
 * in main or pass through source and recompile.
 *
 * Build: aarch64-linux-gnu-gcc -nostartfiles Trees/arm_massive_tree.s -o arm_massive_tree
 * Run: ./arm_massive_tree
 *
 * Node layout (24 bytes):
 *  offset 0: 8-byte int value
 *  offset 8: 8-byte pointer left
 *  offset16: 8-byte pointer right
 */

    .text
    .global main
    .extern malloc
    .extern free
    .extern printf
    .align 3

    .data
fmt_summary:
    .asciz "Massive tree: nodes=%ld depth=%ld sum=%ld inorder_sample=%ld levels=%ld\n"
fmt_alloc_fail:
    .asciz "malloc failed for %ld bytes\n"

    .equ NODE_SIZE, 24

    .bss
    .align 3
g_node_count:
    .quad 0

    .text

/* main: build default-depth tree and run analyses */
.type main, %function
main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* default depth = 20 (change immediate below to alter) */
    mov x0, #20
    bl build_massive_tree    /* returns base pointer in x0 (or 0 on fail) */
    cbz x0, .L_exit_fail

    /* store base in x19 for later free */
    mov x19, x0

    /* compute sum using iterative preorder stack */
    mov x0, x19
    bl compute_sum_preorder_iter
    /* sum returned in x0, also stored to g_sum */
    mov x20, x0

    /* compute inorder sample (first value visited by iterative inorder) */
    mov x0, x19
    bl compute_inorder_sample_iter
    mov x21, x0

    /* compute levels (BFS) */
    mov x0, x19
    bl compute_levels_bfs
    mov x22, x0

    /* load node_count and depth */
    adrp x23, g_node_count@PAGE
    ldr x23, [x23, g_node_count@PAGEOFF]
    adrp x24, g_depth@PAGE
    ldr x24, [x24, g_depth@PAGEOFF]

    /* print summary: printf(fmt_summary, nodes, depth, sum, sample, levels) */
    adrp x0, fmt_summary@PAGE
    add x0, x0, fmt_summary@PAGEOFF
    mov x1, x23
    mov x2, x24
    mov x3, x20
    mov x4, x21
    mov x5, x22
    bl printf

    /* free base */
    mov x0, x19
    bl free

.L_exit_fail:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

/*
 * build_massive_tree(depth)
 * Input x0 = depth
 * Returns x0 = base pointer or 0 on allocation failure
 * Stores node_count in g_node_count and depth in g_depth and saves base in g_base
 */
.type build_massive_tree, %function
build_massive_tree:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* compute node_count = (1<<depth) - 1 */
    mov x1, #1
    mov x2, x0    /* depth */
    cbz x2, .L_depth_zero_massive
    mov x3, #0
.L_shift_massive:
    lsl x1, x1, #1
    add x3, x3, #1
    cmp x3, x2
    blt .L_shift_massive
    sub x1, x1, #1    /* node_count */

    /* store node_count */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    str x1, [x4]

    /* store depth */
    adrp x5, g_depth@PAGE
    add x5, x5, g_depth@PAGEOFF
    str x0, [x5]

    /* compute total size = node_count * NODE_SIZE (24)
     * size = (node_count << 4) + (node_count << 3)
     */
    lsl x6, x1, #4
    lsl x7, x1, #3
    add x6, x6, x7  /* x6=size */

    /* allocate contiguous nodes */
    mov x0, x6
    bl malloc
    cbz x0, .L_alloc_fail_massive
    mov x8, x0    /* base pointer */

    /* store base in g_base */
    adrp x9, g_base@PAGE
    add x9, x9, g_base@PAGEOFF
    str x8, [x9]

    /* initialize nodes i=0..node_count-1 */
    mov x10, #0
    mov x11, x1   /* node_count */
.L_init_massive_loop:
    cmp x10, x11
    bge .L_init_massive_done
    /* offset = i*24 = (i<<4) + (i<<3) */
    lsl x12, x10, #4
    lsl x13, x10, #3
    add x14, x12, x13
    add x15, x8, x14    /* node ptr */
    /* set node->val = i */
    str x10, [x15]
    /* left idx = 2*i + 1 */
    add x16, x10, x10
    add x16, x16, #1
    cmp x16, x11
    bhs .L_left_null_massive
    lsl x17, x16, #4
    lsl x18, x16, #3
    add x17, x17, x18
    add x17, x8, x17
    str x17, [x15, #8]
    b .L_right_massive
.L_left_null_massive:
    mov x19, #0
    str x19, [x15, #8]
.L_right_massive:
    /* right idx = 2*i + 2 */
    add x16, x10, x10
    add x16, x16, #2
    cmp x16, x11
    bhs .L_right_null_massive
    lsl x17, x16, #4
    lsl x18, x16, #3
    add x17, x17, x18
    add x17, x8, x17
    str x17, [x15, #16]
    b .L_inc_massive
.L_right_null_massive:
    mov x19, #0
    str x19, [x15, #16]
.L_inc_massive:
    add x10, x10, #1
    b .L_init_massive_loop
.L_init_massive_done:
    mov x0, x8
    b .L_build_massive_done

.L_alloc_fail_massive:
    /* print allocation failure */
    adrp x0, fmt_alloc_fail@PAGE
    add x0, x0, fmt_alloc_fail@PAGEOFF
    mov x1, x6
    bl printf
    mov x0, #0
    b .L_build_massive_done

.L_depth_zero_massive:
    /* depth 0: zero nodes */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    mov x1, #0
    str x1, [x4]
    mov x0, #0

.L_build_massive_done:
    ldp x29, x30, [sp], #16
    ret

/*
 * compute_sum_preorder_iter(base)
 * Iterative preorder using stack (array of pointers)
 * Returns sum in x0 and stores to g_sum
 */
.type compute_sum_preorder_iter, %function
compute_sum_preorder_iter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbz x0, .L_sum_zero_massive
    mov x1, x0    /* base */

    /* load node_count */
    adrp x2, g_node_count@PAGE
    ldr x2, [x2, g_node_count@PAGEOFF]
    cbz x2, .L_sum_zero_massive

    /* stack bytes = node_count * 8 */
    lsl x3, x2, #3
    mov x0, x3
    bl malloc
    cbz x0, .L_sum_zero_massive
    mov x4, x0    /* stack_base */

    mov x5, #0    /* top */
    /* push root */
    str x1, [x4, x5, lsl #3]
    add x5, x5, #1

    mov x6, #0    /* sum */
    mov x7, #-1   /* sample unset */

.L_sum_loop_massive:
    cmp x5, #0
    beq .L_sum_done_massive
    sub x5, x5, #1
    ldr x8, [x4, x5, lsl #3]
    cbz x8, .L_sum_loop_massive
    ldr x9, [x8]
    add x6, x6, x9
    /* set sample if unset */
    cmp x7, #-1
    bne .L_no_sample_massive
    mov x7, x9
.L_no_sample_massive:
    /* push right then left */
    ldr x10, [x8, #16]
    cbz x10, .L_skip_r_massive
    str x10, [x4, x5, lsl #3]
    add x5, x5, #1
.L_skip_r_massive:
    ldr x10, [x8, #8]
    cbz x10, .L_skip_l_massive
    str x10, [x4, x5, lsl #3]
    add x5, x5, #1
.L_skip_l_massive:
    b .L_sum_loop_massive

.L_sum_done_massive:
    /* store g_sum and g_sample */
    adrp x11, g_sum@PAGE
    add x11, x11, g_sum@PAGEOFF
    str x6, [x11]
    adrp x12, g_sample@PAGE
    add x12, x12, g_sample@PAGEOFF
    str x7, [x12]
    /* free stack */
    mov x0, x4
    bl free
    mov x0, x6
    b .L_sum_return_massive

.L_sum_zero_massive:
    mov x0, #0
.L_sum_return_massive:
    ldp x29, x30, [sp], #16
    ret

/*
 * compute_inorder_sample_iter(base)
 * Iterative inorder using explicit stack but limited to finding first sample value
 * Returns sample in x0 (or -1 if none)
 */
.type compute_inorder_sample_iter, %function
compute_inorder_sample_iter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbz x0, .L_inorder_zero
    mov x1, x0    /* base */

    /* load node_count to size stack allocate conservatively */
    adrp x2, g_node_count@PAGE
    ldr x2, [x2, g_node_count@PAGEOFF]
    cbz x2, .L_inorder_zero

    lsl x3, x2, #3
    mov x0, x3
    bl malloc
    cbz x0, .L_inorder_zero
    mov x4, x0    /* stack_base */
    mov x5, #0    /* top */
    mov x6, x1    /* cur = base */

.L_inorder_loop:
    cbz x6, .L_inorder_backtrack
    /* push cur */
    str x6, [x4, x5, lsl #3]
    add x5, x5, #1
    ldr x6, [x6, #8]   /* cur = cur->left */
    b .L_inorder_loop
.L_inorder_backtrack:
    cmp x5, #0
    beq .L_inorder_done
    sub x5, x5, #1
    ldr x7, [x4, x5, lsl #3]
    /* visit node: load value and return as sample */
    ldr x8, [x7]
    /* free stack and return sample */
    mov x0, x8
    mov x1, x4
    bl free
    b .L_inorder_ret

.L_inorder_done:
    mov x0, #-1
    mov x1, x4
    bl free
.L_inorder_ret:
    ldp x29, x30, [sp], #16
    ret

.L_inorder_zero:
    mov x0, #-1
    ldp x29, x30, [sp], #16
    ret

/*
 * compute_levels_bfs(base)
 * Iterative BFS counting levels
 */
.type compute_levels_bfs, %function
compute_levels_bfs:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbz x0, .L_levels_zero_massive
    mov x1, x0

    adrp x2, g_node_count@PAGE
    ldr x2, [x2, g_node_count@PAGEOFF]
    cbz x2, .L_levels_zero_massive

    lsl x3, x2, #3
    mov x0, x3
    bl malloc
    cbz x0, .L_levels_zero_massive
    mov x4, x0    /* queue base */

    mov x5, #0    /* head */
    mov x6, #0    /* tail */
    /* enqueue root */
    str x1, [x4, x6, lsl #3]
    add x6, x6, #1
    mov x7, #0    /* levels */

.L_levels_outer_massive:
    cmp x5, x6
    beq .L_levels_done_massive
    sub x8, x6, x5   /* level_size */
    add x7, x7, #1
.L_levels_proc_massive:
    cmp x8, #0
    beq .L_levels_outer_massive_continue
    ldr x9, [x4, x5, lsl #3]
    add x5, x5, #1
    ldr x10, [x9, #8]
    cbz x10, .L_skip_l2
    str x10, [x4, x6, lsl #3]
    add x6, x6, #1
.L_skip_l2:
    ldr x10, [x9, #16]
    cbz x10, .L_skip_r2
    str x10, [x4, x6, lsl #3]
    add x6, x6, #1
.L_skip_r2:
    sub x8, x8, #1
    b .L_levels_proc_massive
.L_levels_outer_massive_continue:
    b .L_levels_outer_massive
.L_levels_done_massive:
    /* store in g_levels and free queue */
    adrp x11, g_levels@PAGE
    add x11, x11, g_levels@PAGEOFF
    str x7, [x11]
    mov x0, x4
    bl free
    mov x0, x7
    ldp x29, x30, [sp], #16
    ret

.L_levels_zero_massive:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

    .data
    .align 3
g_base:
    .quad 0
g_depth:
    .quad 0
g_sum:
    .quad 0
g_sample:
    .quad -1
g_levels:
    .quad 0

    .size main, .-main
