#ifndef SX_LOG_FILE_H
#define SX_LOG_FILE_H

// File operations shared by the iOS logger and the portable regression test.
// Open every time so other processes can remove or rotate the path safely.
#include <fcntl.h>
#include <stddef.h>
#include <unistd.h>

static inline int SXLogFileAppend(const char *path, const char *bytes, size_t length) {
	int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
	if (fd < 0) return -1;
	ssize_t written = write(fd, bytes, length);
	int result = (written >= 0 && (size_t)written == length) ? 0 : -1;
	close(fd);
	return result;
}

static inline int SXLogFileClear(const char *path) {
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) return -1;
	return close(fd);
}

#endif
