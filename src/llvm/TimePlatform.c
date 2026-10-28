/* TimePlatform.c - the part of TimePlatform.Mod written in C (design
   section 11).

   The clocks differ between Linux, NetBSD, OpenBSD and FreeBSD in ways an
   Oberon declaration cannot follow: the layout of struct timespec, and on
   NetBSD the names of clock_gettime, clock_getres and nanosleep, which its
   headers rename to versioned symbols such as __clock_gettime50. The
   system's own headers know that, so these wrappers are compiled by clang
   for the target, as Peaseblossom's Platform.c is.

   The local zone is the C library's: localtime_r, with the BSD and glibc
   fields tm_gmtoff and tm_zone. _TIME_BITS gives 32-bit glibc a 64-bit
   time_t; it needs _FILE_OFFSET_BITS with it.

   The interface is in fixed-width types only, so that it means the same
   under both of poc's size models. The names contain "-", so that no
   Oberon name can be the same. */

#define _FILE_OFFSET_BITS 64
#define _TIME_BITS 64

#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

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

/* s into to, cut to fit length bytes with its 0 */
static void Copy(char *to, int32_t length, const char *s)
{
  int32_t i = 0;
  if (length <= 0) return;
  while (s[i] != 0 && i < length - 1) { to[i] = s[i]; i++; }
  to[i] = 0;
}

/* Called once, before the first LocalOffset: localtime_r need not read TZ
   itself, as localtime does. */
int32_t TimePlatformSystemLocal(void) NAME("system-local");
int32_t TimePlatformSystemLocal(void)
{
  tzset();
  return 1;
}

/* The local offset in seconds east, whether it is daylight saving time,
   and the abbreviation, at POSIX time seconds; 0 if time_t cannot hold
   seconds or localtime_r fails. */
int32_t TimePlatformLocalOffset(int64_t seconds, int32_t *offset, int32_t *isDst,
                                char *abbreviation, int32_t length) NAME("local-offset");
int32_t TimePlatformLocalOffset(int64_t seconds, int32_t *offset, int32_t *isDst,
                                char *abbreviation, int32_t length)
{
  time_t t = (time_t)seconds;
  struct tm tm;
  if ((int64_t)t != seconds || localtime_r(&t, &tm) == NULL) return 0;
  *offset = (int32_t)tm.tm_gmtoff;
  *isDst = tm.tm_isdst > 0;
  Copy(abbreviation, length, tm.tm_zone != NULL ? tm.tm_zone : "");
  return 1;
}

/* TZ without a leading ":", "UTC" for a TZ that is set but empty, as the
   C library reads it; else what /etc/localtime links to, after its last
   "zoneinfo/"; else "localtime". */
void TimePlatformLocalZoneName(char *name, int32_t length) NAME("local-zone-name");
void TimePlatformLocalZoneName(char *name, int32_t length)
{
  char target[1024];
  const char *tz = getenv("TZ"), *p, *after;
  ssize_t n;
  if (tz != NULL) {
    if (*tz == ':') tz++;
    Copy(name, length, *tz != 0 ? tz : "UTC");
    return;
  }
  n = readlink("/etc/localtime", target, sizeof target - 1);
  if (n > 0) {
    target[n] = 0;
    after = NULL;
    for (p = strstr(target, "zoneinfo/"); p != NULL; p = strstr(p + 1, "zoneinfo/"))
      after = p + strlen("zoneinfo/");
    if (after != NULL && *after != 0) { Copy(name, length, after); return; }
  }
  Copy(name, length, "localtime");
}

/* TZDIR, or else /usr/share/zoneinfo */
void TimePlatformZoneInfoDirectory(char *dir, int32_t length) NAME("zone-info-directory");
void TimePlatformZoneInfoDirectory(char *dir, int32_t length)
{
  const char *tzdir = getenv("TZDIR");
  Copy(dir, length, tzdir != NULL && *tzdir != 0 ? tzdir : "/usr/share/zoneinfo");
}
