#include "CProcess.h"

#include <errno.h>
#include <libproc.h>
#include <limits.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/proc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <unistd.h>

int32_t killer_list_processes(int32_t *buffer, int32_t capacity) {
    if (capacity < 0 || capacity > INT_MAX / (int)sizeof(int32_t)) {
        errno = EINVAL;
        return -1;
    }
    return proc_listallpids(buffer, capacity * (int)sizeof(int32_t));
}

static int read_bsd_info(int32_t pid, struct proc_bsdinfo *info) {
    if (pid <= 0) return ESRCH;
    memset(info, 0, sizeof(*info));
    errno = 0;
    int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, info, sizeof(*info));
    if (size != sizeof(*info)) {
        if (errno != 0) return errno;
        // A missing metadata response alone does not prove a process exited.
        if (kill(pid, 0) < 0 && errno == ESRCH) return ESRCH;
        return EACCES;
    }
    if (info->pbi_status == SZOMB || (info->pbi_flags & PROC_FLAG_INEXIT)) return ESRCH;
    return 0;
}

int32_t killer_read_process(int32_t pid, killer_process_info *result) {
    if (result == NULL) return EINVAL;
    memset(result, 0, sizeof(*result));
    struct proc_bsdinfo info;
    int error = read_bsd_info(pid, &info);
    if (error != 0) return error;

    errno = 0;
    int path_size = proc_pidpath(pid, result->executable_path, sizeof(result->executable_path));
    if (path_size <= 0) return errno != 0 ? errno : EACCES;
    result->executable_path[sizeof(result->executable_path) - 1] = '\0';
    result->pid = (int32_t)info.pbi_pid;
    result->parent_pid = (int32_t)info.pbi_ppid;
    result->owner_uid = info.pbi_uid;
    result->flags = info.pbi_flags;
    result->start_seconds = info.pbi_start_tvsec;
    result->start_microseconds = info.pbi_start_tvusec;
    const char *name = info.pbi_name[0] != '\0' ? info.pbi_name : info.pbi_comm;
    size_t name_capacity = info.pbi_name[0] != '\0' ? sizeof(info.pbi_name) : sizeof(info.pbi_comm);
    size_t length = strnlen(name, name_capacity);
    if (length >= sizeof(result->name)) length = sizeof(result->name) - 1;
    memcpy(result->name, name, length);
    result->name[length] = '\0';
    return 0;
}

int32_t killer_has_exited(int32_t pid, uint64_t start_seconds, uint64_t start_microseconds) {
    if (pid <= 0) return 0;
    struct proc_bsdinfo info;
    memset(&info, 0, sizeof(info));
    int size = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (size == sizeof(info)) {
        if (info.pbi_start_tvsec != start_seconds || info.pbi_start_tvusec != start_microseconds) return 1;
        // Zombies have finished executing even while a parent has yet to reap them.
        return info.pbi_status == SZOMB || (info.pbi_flags & PROC_FLAG_INEXIT) != 0;
    }
    // libproc can return ESRCH for zombies even though kill(pid, 0) succeeds.
    // The process table still exposes their terminal state until they are reaped.
    struct kinfo_proc kernel_info;
    memset(&kernel_info, 0, sizeof(kernel_info));
    int query[] = {CTL_KERN, KERN_PROC, KERN_PROC_PID, pid};
    size_t kernel_info_size = sizeof(kernel_info);
    if (sysctl(query, 4, &kernel_info, &kernel_info_size, NULL, 0) == 0 &&
        kernel_info_size == sizeof(kernel_info) && kernel_info.kp_proc.p_stat == SZOMB) {
        return 1;
    }
    // Unreadable metadata is not evidence of exit. Probe only for definite absence.
    return kill(pid, 0) < 0 && errno == ESRCH;
}

static int is_path_within(const char *path, const char *directory) {
    size_t length = strlen(directory);
    return strncmp(path, directory, length) == 0 &&
           (path[length] == '/' || path[length] == '\0');
}

static const char *path_protection_reason(const char *path) {
    if (path == NULL || path[0] != '/') return "The executable cannot be verified.";
    /* Apple application bundles remain selectable; operating-system services do not. */
    if (is_path_within(path, "/System") && !is_path_within(path, "/System/Applications")) {
        return "This process is part of macOS.";
    }
    const char *protected_directories[] = {
        "/usr/libexec", "/usr/sbin", "/usr/bin", "/usr/lib", "/sbin", "/bin",
        "/Library/Apple", "/private/var/db/oah"
    };
    for (size_t i = 0; i < sizeof(protected_directories) / sizeof(protected_directories[0]); i++) {
        if (is_path_within(path, protected_directories[i])) return "This process is part of macOS.";
    }
    return NULL;
}

const char *killer_protection_reason(int32_t pid, const char *executable_path) {
    if (pid <= 1) return "This is an essential system process.";
    if (pid == getpid()) return "Killer cannot force quit itself.";
    const char *path_reason = path_protection_reason(executable_path);
    if (path_reason != NULL) return path_reason;

    /* Do not terminate the app, terminal, or launch service that is running Killer. */
    int32_t ancestor = getppid();
    for (int depth = 0; ancestor > 1 && depth < 256; depth++) {
        if (pid == ancestor) return "This process is required to keep Killer running.";
        struct proc_bsdinfo info;
        if (read_bsd_info(ancestor, &info) != 0 || (int32_t)info.pbi_ppid == ancestor) break;
        ancestor = (int32_t)info.pbi_ppid;
    }
    struct proc_bsdinfo target;
    if (read_bsd_info(pid, &target) == 0 && (target.pbi_flags & PROC_FLAG_SYSTEM)) {
        return "This is an essential system process.";
    }
    return NULL;
}

int32_t killer_force_kill(int32_t pid, uint64_t start_seconds,
                         uint64_t start_microseconds, uint32_t owner_uid,
                         const char *executable_path, int32_t *error_number) {
    if (error_number != NULL) *error_number = 0;
    const char *protection = killer_protection_reason(pid, executable_path);
    if (protection != NULL) return KILLER_SIGNAL_PROTECTED;

    killer_process_info current;
    int error = killer_read_process(pid, &current);
    if (error != 0) {
        if (error_number != NULL) *error_number = error;
        if (error == ESRCH) return KILLER_SIGNAL_EXITED;
        if (error == EPERM || error == EACCES) return KILLER_SIGNAL_PERMISSION_DENIED;
        return KILLER_SIGNAL_FAILED;
    }
    if (current.start_seconds != start_seconds || current.start_microseconds != start_microseconds ||
        current.owner_uid != owner_uid || strcmp(current.executable_path, executable_path) != 0) {
        return KILLER_SIGNAL_IDENTITY_CHANGED;
    }
    if (current.flags & PROC_FLAG_SYSTEM) return KILLER_SIGNAL_PROTECTED;
    if (path_protection_reason(current.executable_path) != NULL) return KILLER_SIGNAL_PROTECTED;

    if (kill(pid, SIGKILL) == 0) return KILLER_SIGNAL_SENT;
    error = errno;
    if (error_number != NULL) *error_number = error;
    if (error == ESRCH) return KILLER_SIGNAL_EXITED;
    if (error == EPERM || error == EACCES) return KILLER_SIGNAL_PERMISSION_DENIED;
    return KILLER_SIGNAL_FAILED;
}
