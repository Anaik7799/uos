/* Bounded Linux x86_64 exec facade; no libc, interpreter, daemon or policy.
 * Gleam supplies reviewed, pinned paths and selects the closed profile.
 * argv: linux-x86_64 native-storage-v1 GUARDIAN WORKER CONFIG REMAINING_MS.
 * Replace this PID with the existing guardian; stdin/stdout framing is opaque.
 * All extra descriptors close BEFORE exec. Any refusal/exec failure exits127,
 * which is NOT the guardian's confirmed-cleanup witness. No fallback.
 * Same-UID path races and trusted BEAM startup remain external premises.
 */
#if !defined(__linux__) || !defined(__x86_64__)
#error "finite_environment_launch supports Linux x86_64 only"
#endif
typedef unsigned long word;
static long call3(long number, long a, long b, long c) {
  long result;
  __asm__ volatile("syscall" : "=a"(result)
    : "a"(number), "D"(a), "S"(b), "d"(c) : "rcx", "r11", "memory");
  return result;
}
static __attribute__((noreturn)) void refuse(void) {
  call3(60, 127, 0, 0); __builtin_unreachable();
}
static int equal(const char *a, const char *b) {
  for (word i=0; i<64; i++) { if(a[i]!=b[i])return 0; if(!a[i])return 1; }
  return 0;
}
static int path(const char *p) {
  if(p[0]!='/')return 0;
  word start=1;
  for(word i=1;i<=4096;i++) {
    char c=p[i];
    if(!c || c=='/') {
      word n=i-start;
      if(!n || (n==1&&p[start]=='.') ||
          (n==2&&p[start]=='.'&&p[start+1]=='.'))return 0;
      if(!c)return 1;
      start=i+1;
    }
  }
  return 0;
}
static int milliseconds(const char *p) {
  unsigned n=0;
  if(p[0]<'1'||p[0]>'9')return 0;
  for(word i=0;i<5;i++) {
    if(!p[i])return n<=5000;
    if(p[i]<'0'||p[i]>'9')return 0;
    n=n*10+(unsigned)(p[i]-'0');
    if(n>5000)return 0;
  }
  return 0;
}
static char *environment[]={"PATH=/nonexistent", "LANG=C", "LC_ALL=C", "TZ=UTC", 0};
static __attribute__((used,noreturn)) void launch(word *stack) {
  char **argv=(char **)(stack+1);
  if(stack[0]!=7 || !equal(argv[1],"linux-x86_64") ||
      !equal(argv[2],"native-storage-v1") || !path(argv[3]) ||
      !path(argv[4]) || !path(argv[5]) || !milliseconds(argv[6]))refuse();
  /* Linux >=5.9 close_range; unsupported/refused is HOLD, never a loop/fallback.
   * Kernel FD-table work and scheduling are not a universal latency proof. */
  if(call3(436,3,0xffffffffUL,0)!=0)refuse();
  char *child[]={argv[3],argv[4],argv[5],argv[6],0};
  call3(59,(long)argv[3],(long)child,(long)environment);
  refuse();
}
__asm__(".global _start\n.type _start,@function\n_start:\n"
        "mov %rsp,%rdi\nand $-16,%rsp\ncall launch\nud2\n");
