#define _GNU_SOURCE
#include "SXLogFile.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>

static void append(const char *path, const char *line) {
	assert(SXLogFileAppend(path, line, strlen(line)) == 0);
}
static void expect(const char *path, const char *expected) {
	char buf[256] = {0};
	FILE *f = fopen(path, "r");
	assert(f);
	size_t n = fread(buf, 1, sizeof(buf) - 1, f);
	assert(!ferror(f));
	fclose(f);
	buf[n] = '\0';
	assert(strcmp(buf, expected) == 0);
}

int main(void) {
	char dir[] = "/tmp/sirix-log-test-XXXXXX";
	assert(mkdtemp(dir));
	char path[256], old[256];
	snprintf(path, sizeof(path), "%s/SiriX.log", dir);
	snprintf(old, sizeof(old), "%s/SiriX.log.old", dir);
	append(path, "before\n");
	// A writer keeps running while another process clears the file.
	int signalPipe[2];
	assert(pipe(signalPipe) == 0);
	pid_t child = fork();
	assert(child >= 0);
	if (!child) {
		close(signalPipe[1]);
		char signal;
		assert(read(signalPipe[0], &signal, 1) == 1);
		append(path, "after-clear\n");
		close(signalPipe[0]);
		_exit(0);
	}
	close(signalPipe[0]);
	assert(SXLogFileClear(path) == 0);
	assert(write(signalPipe[1], "x", 1) == 1);
	close(signalPipe[1]);
	int status;
	assert(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0);
	expect(path, "after-clear\n");
	// External removal and rotation must not strand future writes on an old inode.
	assert(unlink(path) == 0);
	append(path, "after-unlink\n");
	expect(path, "after-unlink\n");
	assert(rename(path, old) == 0);
	append(path, "after-rotation\n");
	expect(path, "after-rotation\n");
	expect(old, "after-unlink\n");
	assert(unlink(old) == 0 && unlink(path) == 0 && rmdir(dir) == 0);
	puts("log file regression tests: OK");
	return 0;
}
