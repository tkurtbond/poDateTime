/* TimePlatform.c - the part of TimePlatform.Mod written in C (design
   section 11).

   The clocks differ between Linux, NetBSD, OpenBSD and FreeBSD in ways an
   Oberon declaration cannot follow: the layout of struct timespec, and on
   NetBSD the names of clock_gettime, clock_getres and nanosleep, which its
   headers rename to versioned symbols such as __clock_gettime50. The
   system's own headers know that, so these wrappers are compiled by clang
   for the target, as Peaseblossom's Platform.c is.

   The interface is in fixed-width types only, so that it means the same
   under both of poc's size models. The names contain "-", so that no
   Oberon name can be the same. */

#include <errno.h>
#include <stdint.h>
#include <time.h>

#define NAME(n) __asm__("TimePlatform.-" n)

/* A clock's reading in nanoseconds since its start; 0 if it cannot be
   read. */
static int64_t Read(clockid_t clock)
{
  struct timespec ts;
  if (clock_gettime(clock, &ts) < 0) return 0;
  return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

/* A clock's resolution in nanoseconds; 0 if it cannot be read. */
static int64_t Resolution(clockid_t clock)
{
  struct timespec ts;
  if (clock_getres(clock, &ts) < 0) return 0;
  return (int64_t)ts.tv_sec * 1000000000 + ts.tv_nsec;
}

/* The wall clock as POSIX seconds and a nanosecond, kept apart: as one
   count of nanoseconds it would wrap in 2262. Both 0 if it cannot be
   read. */
void TimePlatformWallClock(int64_t *seconds, int64_t *nanosecond) NAME("wall-clock");
void TimePlatformWallClock(int64_t *seconds, int64_t *nanosecond)
{
  struct timespec ts;
  if (clock_gettime(CLOCK_REALTIME, &ts) < 0) { *seconds = 0; *nanosecond = 0; return; }
  *seconds = (int64_t)ts.tv_sec;
  *nanosecond = (int64_t)ts.tv_nsec;
}

int64_t TimePlatformMonotonic(void) NAME("monotonic");
int64_t TimePlatformMonotonic(void) { return Read(CLOCK_MONOTONIC); }

int64_t TimePlatformProcess(void) NAME("process");
int64_t TimePlatformProcess(void) { return Read(CLOCK_PROCESS_CPUTIME_ID); }

int64_t TimePlatformWallResolution(void) NAME("wall-resolution");
int64_t TimePlatformWallResolution(void) { return Resolution(CLOCK_REALTIME); }

int64_t TimePlatformMonotonicResolution(void) NAME("monotonic-resolution");
int64_t TimePlatformMonotonicResolution(void) { return Resolution(CLOCK_MONOTONIC); }

/* Sleeps for nanoseconds, the whole time even when a signal interrupts
   it, as Platform.Delay does. */
void TimePlatformSleep(int64_t nanoseconds) NAME("sleep");
void TimePlatformSleep(int64_t nanoseconds)
{
  struct timespec request, remaining;
  if (nanoseconds <= 0) return;
  request.tv_sec = (time_t)(nanoseconds / 1000000000);
  request.tv_nsec = (long)(nanoseconds % 1000000000);
  while (nanosleep(&request, &remaining) < 0 && errno == EINTR) request = remaining;
}
