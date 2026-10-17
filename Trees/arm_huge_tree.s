/*
 * Trees/arm_huge_tree.s
 * A larger ARM64 (AArch64) assembly program for Linux (GNU assembler syntax).
 * - Builds a perfect binary tree to a configurable depth (default 18 -> 262,143 nodes)
 * - Uses iterative algorithms (stack and queue allocated via malloc) to avoid deep recursion
 * - Computes node count, tree depth, sum of node values, does an iterative preorder and BFS
 * - Prints summary statistics
 *
 * WARNING: depth 18 allocates ~6.3MB for nodes (262143 * 24 bytes). Increase with care.
 * Change the default depth in main by modifying the immediate below.
 *
 * Build: aarch64-linux-gnu-gcc -nostartfiles Trees/arm_huge_tree.s -o arm_huge_tree_huge
 * Run: ./arm_huge_tree_huge
 */

    .text
    .global main
    .extern malloc
    .extern free
    .extern printf
    .align 3

    .data
fmt_summary:
    .asciz "Huge tree: nodes=%ld depth=%ld sum=%ld preorder_sample=%ld levels=%ld\n"
fmt_error_alloc:
    .asciz "Allocation failed (needed %ld bytes)\n"

.equ NODE_SIZE, 24

    .bss
    .align 3
g_node_count:
    .quad 0

    .text

/* main: build, analyze, print, free */
.type main, %function
main:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* default depth: 18 -> 262143 nodes */
    mov x0, #18
    bl build_tree_from_depth_huge   /* returns base ptr in x0, node_count in g_node_count */
    cbz x0, .L_exit_null

    /* base pointer in x1 */
    mov x1, x0

    /* compute sum of node values using iterative preorder (stack) */
    mov x0, x1
    bl compute_sum_preorder_iter
    mov x2, x0    /* sum in x2 */

    /* compute number of levels using BFS (iterative) */
    mov x0, x1
    bl compute_levels_bfs
    mov x3, x0    /* levels in x3 */

    /* get node_count from g_node_count */
    adrp x4, g_node_count@PAGE
    ldr x4, [x4, g_node_count@PAGEOFF]

    /* prepare a preorder sample (first node value encountered) using quick loop
       but reuse compute_sum_preorder_iter which also left a sample in g_sample if needed
    */
    adrp x5, g_sample@PAGE
    ldr x5, [x5, g_sample@PAGEOFF]

    /* print summary: printf(fmt_summary, node_count, depth, sum, sample, levels) */
    adrp x0, fmt_summary@PAGE
    add x0, x0, fmt_summary@PAGEOFF
    mov x1, x4
    /* depth was the argument used to build tree; we stored depth in g_depth */
    adrp x6, g_depth@PAGE
    ldr x6, [x6, g_depth@PAGEOFF]
    mov x2, x2
    mov x3, x5
    mov x4, x3
    /* calling: x0=fmt, x1=node_count, x2=depth, x3=sum, x4=preorder_sample, x5=levels? but printf supports up to x7 */
    mov x2, x6  /* depth in x2 */
    mov x3, x2  /* sum already in x3? fix order: we'll move registers accordingly */

    /* reorder properly: x0=format, x1=node_count, x2=depth, x3=sum, x4=preorder_sample, x5=levels */
    adrp x0, fmt_summary@PAGE
    add x0, x0, fmt_summary@PAGEOFF
    mov x1, x4        /* node_count */
    adrp x6, g_depth@PAGE
    ldr x2, [x6, g_depth@PAGEOFF]
    mov x3, x2        /* zzz temporary (we'll reload sum and sample below) */

    /* reload proper values */
    adrp x4, g_node_count@PAGE
    ldr x1, [x4, g_node_count@PAGEOFF]
    adrp x5, g_depth@PAGE
    ldr x2, [x5, g_depth@PAGEOFF]
    /* sum in reg x6 (we saved sum earlier in x2 at function return) - but x2 overwritten; reload sum from g_sum */
    adrp x6, g_sum@PAGE
    ldr x3, [x6, g_sum@PAGEOFF]
    adrp x7, g_sample@PAGE
    ldr x4, [x7, g_sample@PAGEOFF]
    /* levels */
    adrp x8, g_levels@PAGE
    ldr x5, [x8, g_levels@PAGEOFF]

    /* call printf(fmt_summary, node_count, depth, sum, sample, levels) */
    bl printf

    /* free big allocations: nodes, plus any temp buffers freed in functions */
    mov x0, x1    /* base pointer was saved earlier at build; but we lost it — recompute: build stored base in g_base */
    adrp x9, g_base@PAGE
    ldr x0, [x9, g_base@PAGEOFF]
    bl free

.L_exit_null:
    mov x0, #0
    ldp x29, x30, [sp], #16
    ret

/*
 * build_tree_from_depth_huge(depth)
 * Input x0 = depth
 * Returns x0 = base pointer or 0 on failure
 * Stores node_count in g_node_count, base pointer in g_base, depth in g_depth
 */
.type build_tree_from_depth_huge, %function
build_tree_from_depth_huge:
    stp x29, x30, [sp, #-16]!
    mov x29, sp

    /* compute node_count = (1<<depth) - 1 */
    mov x1, #1
    mov x2, x0    /* depth */
    cbz x2, .L_depth0_huge
    mov x3, #0
.L_shift_huge:
    lsl x1, x1, #1
    add x3, x3, #1
    cmp x3, x2
    blt .L_shift_huge
    sub x1, x1, #1    /* node_count */

    /* store node_count */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    str x1, [x4]

    /* store depth into g_depth */
    adrp x5, g_depth@PAGE
    add x5, x5, g_depth@PAGEOFF
    str x0, [x5]

    /* compute total size = node_count * 24 */
    lsl x6, x1, #4
    lsl x7, x1, #3
    add x6, x6, x7   /* x6 = size */

    /* allocate nodes */
    mov x0, x6
    bl malloc
    cbz x0, .L_alloc_fail_huge
    mov x8, x0    /* base pointer */

    /* store base pointer in g_base */
    adrp x9, g_base@PAGE
    add x9, x9, g_base@PAGEOFF
    str x8, [x9]

    /* initialize nodes in loop i=0..node_count-1 */
    mov x10, #0
    mov x11, x1    /* node_count */
.L_init_huge_loop:
    cmp x10, x11
    bge .L_init_huge_done
    /* offset = i*24 = (i<<4) + (i<<3) */
    lsl x12, x10, #4
    lsl x13, x10, #3
    add x14, x12, x13
    add x15, x8, x14    /* node ptr */
    /* store 64-bit value = i */
    str x10, [x15]
    /* left index = 2*i + 1 */
    add x16, x10, x10
    add x16, x16, #1
    cmp x16, x11
    bhs .L_left_null_huge
    lsl x17, x16, #4
    lsl x18, x16, #3
    add x17, x17, x18
    add x17, x8, x17
    str x17, [x15, #8]
    b .L_right_huge
.L_left_null_huge:
    mov x19, #0
    str x19, [x15, #8]
.L_right_huge:
    add x16, x10, x10
    add x16, x16, #2
    cmp x16, x11
    bhs .L_right_null_huge
    lsl x17, x16, #4
    lsl x18, x16, #3
    add x17, x17, x18
    add x17, x8, x17
    str x17, [x15, #16]
    b .L_inc_huge
.L_right_null_huge:
    mov x19, #0
    str x19, [x15, #16]
.L_inc_huge:
    add x10, x10, #1
    b .L_init_huge_loop
.L_init_huge_done:
    mov x0, x8
    b .L_build_huge_done

.L_alloc_fail_huge:
    /* print error */
    adrp x0, fmt_error_alloc@PAGE
    add x0, x0, fmt_error_alloc@PAGEOFF
    /* size in x1 (was x6) */
    mov x1, x6
    bl printf
    mov x0, #0
    b .L_build_huge_done

.L_depth0_huge:
    /* depth 0 -> no nodes */
    adrp x4, g_node_count@PAGE
    add x4, x4, g_node_count@PAGEOFF
    mov x1, #0
    str x1, [x4]
    mov x0, #0

.L_build_huge_done:
    ldp x29, x30, [sp], #16
    ret

/*
 * compute_sum_preorder_iter(base)
 * Iterative preorder using a stack (array of pointers allocated via malloc)
 * Input: x0 = base pointer (or 0)
 * Returns: x0 = sum (64-bit)
 * Side-effects: stores sum in g_sum and first encountered node value in g_sample
 */
.type compute_sum_preorder_iter, %function
compute_sum_preorder_iter:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbz x0, .L_sum_zero
    mov x1, x0    /* base */

    /* load node_count */
    adrp x2, g_node_count@PAGE
    ldr x2, [x2, g_node_count@PAGEOFF]
    cbz x2, .L_sum_zero

    /* allocate stack array of pointers of size node_count (8 bytes each) */
    lsl x3, x2, #3    /* bytes = node_count * 8 */
    mov x0, x3
    bl malloc
    cbz x0, .L_sum_zero
    mov x4, x0    /* stack_base */

    /* stack_top index in x5 = 0 */
    mov x5, #0
    /* push root pointer */
    str x1, [x4, x5, lsl #3]
    add x5, x5, #1

    mov x6, #0    /* sum */
    mov x7, #-1   /* sample flag: -1 means unset */

.L_sum_loop:
    cmp x5, #0
    beq .L_sum_done
    /* pop: decrement x5, load pointer */
    sub x5, x5, #1
    ldr x8, [x4, x5, lsl #3]
    cbz x8, .L_sum_loop
    /* load node->val */
    ldr x9, [x8]
    /* add to sum */
    add x6, x6, x9
    /* set sample if unset */
    cmp x7, #-1
    bne .L_sample_set
    mov x7, x9
.L_sample_set:
    /* push right then left (so left processed first) */
    ldr x10, [x8, #16]   /* right ptr */
    cbz x10, .L_skip_push_right
    str x10, [x4, x5, lsl #3]
    add x5, x5, #1
.L_skip_push_right:
    ldr x10, [x8, #8]    /* left ptr */
    cbz x10, .L_skip_push_left
    str x10, [x4, x5, lsl #3]
    add x5, x5, #1
.L_skip_push_left:
    b .L_sum_loop

.L_sum_done:
    /* store sum and sample in globals */
    adrp x11, g_sum@PAGE
    add x11, x11, g_sum@PAGEOFF
    str x6, [x11]
    adrp x12, g_sample@PAGE
    add x12, x12, g_sample@PAGEOFF
    str x7, [x12]
    /* free stack array */
    mov x0, x4
    bl free
    mov x0, x6
    b .L_sum_return

.L_sum_zero:
    mov x0, #0
    b .L_sum_return
.L_sum_return:
    ldp x29, x30, [sp], #16
    ret

/*
 * compute_levels_bfs(base)
 * BFS using a queue to count levels
 * Input: x0 = base pointer
 * Return: x0 = levels (64-bit)
 * Stores levels in g_levels
 */
.type compute_levels_bfs, %function
compute_levels_bfs:
    stp x29, x30, [sp, #-16]!
    mov x29, sp
    cbz x0, .L_levels_zero
    mov x1, x0    /* base */

    adrp x2, g_node_count@PAGE
    ldr x2, [x2, g_node_count@PAGEOFF]
    cbz x2, .L_levels_zero

    /* allocate queue array of pointers, size node_count */
    lsl x3, x2, #3
    mov x0, x3
    bl malloc
    cbz x0, .L_levels_zero
    mov x4, x0    /* queue_base */

    /* enqueue root: head idx x5=0, tail idx x6=0 */
    mov x5, #0
    mov x6, #0
    str x1, [x4, x6, lsl #3]
    add x6, x6, #1

    mov x7, #0    /* levels */

.L_levels_outer:
    /* if head==tail break */
    cmp x5, x6
    beq .L_levels_done
    /* level_size = tail - head */
    sub x8, x6, x5
    add x7, x7, #1    /* one more level */
    /* process level_size nodes */
.L_levels_proc_loop:
    cmp x8, #0
    beq .L_levels_outer_continue
    /* dequeue */
    ldr x9, [x4, x5, lsl #3]
    add x5, x5, #1
    /* enqueue children if present */
    ldr x10, [x9, #8]
    cbz x10, .L_levels_skip_left
    str x10, [x4, x6, lsl #3]
    add x6, x6, #1
.L_levels_skip_left:
    ldr x10, [x9, #16]
    cbz x10, .L_levels_skip_right
    str x10, [x4, x6, lsl #3]
    add x6, x6, #1
.L_levels_skip_right:
    sub x8, x8, #1
    b .L_levels_proc_loop
.L_levels_outer_continue:
    b .L_levels_outer

.L_levels_done:
    /* store levels */
    adrp x11, g_levels@PAGE
    add x11, x11, g_levels@PAGEOFF
    str x7, [x11]
    /* free queue */
    mov x0, x4
    bl free
    mov x0, x7
    b .L_levels_ret

.L_levels_zero:
    mov x0, #0
.L_levels_ret:
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
