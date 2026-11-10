/* C smoke test: recursive fibonacci exercises calls, stack, and ALU.
 * fib(12) = 144; _start publishes main's return value to the magic address. */
int fib(int n)
{
	return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

int main(void)
{
	return fib(12); /* expect: 144 */
}
