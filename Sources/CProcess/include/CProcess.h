#ifndef KILLER_CPROCESS_H
#define KILLER_CPROCESS_H

#include <stdint.h>

#define KILLER_PROCESS_PATH_CAPACITY 4096
#define KILLER_PROCESS_NAME_CAPACITY 64

typedef struct {
    int32_t pid;
    int32_t parent_pid;
    uint32_t owner_uid;
    uint32_t flags;
    uint64_t start_seconds;
    uint64_t start_microseconds;
    char name[KILLER_PROCESS_NAME_CAPACITY];
    char executable_path[KILLER_PROCESS_PATH_CAPACITY];
} killer_process_info;

enum killer_signal_result {
    KILLER_SIGNAL_SENT = 0,
    KILLER_SIGNAL_EXITED = 1,
    KILLER_SIGNAL_IDENTITY_CHANGED = 2,
    KILLER_SIGNAL_PERMISSION_DENIED = 3,
    KILLER_SIGNAL_PROTECTED = 4,
    KILLER_SIGNAL_FAILED = 5
};

/* Returns the process count, or -1 on error. A NULL buffer estimates capacity. */
int32_t killer_list_processes(int32_t *buffer, int32_t capacity);
/* Returns zero, or an errno value. Exited/zombie processes return ESRCH. */
int32_t killer_read_process(int32_t pid, killer_process_info *result);
/* True only when the original identity has exited, become a zombie, or been replaced. */
int32_t killer_has_exited(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds);
/* Returns a stable reason string for a protected target; NULL otherwise. */
const char *killer_protection_reason(int32_t pid, const char *executable_path);
/* Revalidates the process's birth time, owner, and path immediately before signaling. */
int32_t killer_force_kill(int32_t pid, uint64_t start_seconds,
                         uint64_t start_microseconds, uint32_t owner_uid,
                         const char *executable_path, int32_t *error_number);

#endif
