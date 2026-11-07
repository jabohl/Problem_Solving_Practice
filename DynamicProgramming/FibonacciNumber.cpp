/**
 * LeetCode Problem: Fibonacci Number (LeetCode 509)
 *
 * Problem Description:
 * The Fibonacci numbers, commonly denoted F(n), form a sequence such that
 * each number is the sum of the two preceding ones, starting from 0 and 1.
 * Time Complexity: O(2^n) - exponential due to recursive calls
 * Space Complexity: O(n) - recursion stack depth
 */

class Solution {
public:
    /**
     * Args:
     *     position: The position in sequence
     *
     * Returns:
     *     The Fibonacci number at the given position
     */
    int fib(int position) {
        if (position < 2) {
            return position;
        }
        return fib(position - 1) + fib(position - 2);
    }
};
