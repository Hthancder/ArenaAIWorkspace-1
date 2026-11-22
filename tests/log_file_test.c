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

// Đọc đuôi file: màn hình log chỉ nạp phần cuối, phần đầu (có thể cụt) bị bỏ.
static void expect_tail(const char *path, size_t capacity, const char *expected, int wantTruncated) {
	char *buf = malloc(capacity + 1);
	assert(buf);
	off_t size = -1;
	int truncated = -1;
	ssize_t got = SXLogFileReadTail(path, buf, capacity, &size, &truncated);
	assert(got >= 0);
	assert((size_t)got == strlen(expected));
	assert(strcmp(buf, expected) == 0);
	assert((truncated != 0) == (wantTruncated != 0));
	assert(size == (off_t)strlen(expected) || wantTruncated);
	free(buf);
}

static void test_read_tail(void) {
	char dir[] = "/tmp/sirix-log-tail-XXXXXX";
	assert(mkdtemp(dir));
	char path[256];
	snprintf(path, sizeof(path), "%s/SiriX.log", dir);

	// 1) File nhỏ hơn cửa sổ đọc → trả nguyên văn, không cắt.
	append(path, "line-1\nline-2\nline-3\n");
	expect_tail(path, 1024, "line-1\nline-2\nline-3\n", 0);

	// 2) Cửa sổ nhỏ → chỉ lấy đuôi và bỏ dòng đầu bị cụt (bắt đầu ở "line-3").
	expect_tail(path, 10, "line-3\n", 1);
	assert(strlen("line-1\nline-2\nline-3\n") == 21);

	// 3) File rỗng → 0 byte, không phải lỗi.
	assert(SXLogFileClear(path) == 0);
	expect_tail(path, 64, "", 0);

	// 4) File không tồn tại → -1 để UI hiện thông báo thay vì treo.
	char missing[256];
	snprintf(missing, sizeof(missing), "%s/khong-co.log", dir);
	char buf[8];
	off_t size = -1;
	int truncated = -1;
	assert(SXLogFileReadTail(missing, buf, sizeof(buf) - 1, &size, &truncated) == -1);
	assert(size == 0 && truncated == 0);

	// 5) Một dòng dài hơn cả cửa sổ → trả rỗng thay vì hiển thị nửa dòng.
	assert(SXLogFileClear(path) == 0);
	append(path, "0123456789012345678901234567890");
	expect_tail(path, 8, "", 1);

	assert(unlink(path) == 0 && rmdir(dir) == 0);
}

// Ghi một dòng dài hơn một lần write() của kernel và kiểm tra không mất byte.
// (SpringBoard hay nhận signal; một write ngắn làm cả dòng log biến mất.)
static void test_partial_writes(void) {
	char dir[] = "/tmp/sirix-log-partial-XXXXXX";
	assert(mkdtemp(dir));
	char path[256];
	snprintf(path, sizeof(path), "%s/SiriX.log", dir);
	size_t length = 200000;
	char *payload = malloc(length);
	assert(payload);
	for (size_t i = 0; i < length; i++) payload[i] = (char)('a' + (i % 26));
	assert(SXLogFileAppend(path, payload, length) == 0);
	assert(SXLogFileSize(path) == (off_t)length);
	FILE *f = fopen(path, "rb");
	assert(f);
	char *readback = malloc(length);
	assert(readback);
	assert(fread(readback, 1, length, f) == length);
	fclose(f);
	assert(memcmp(readback, payload, length) == 0);
	free(readback);
	free(payload);
	assert(unlink(path) == 0 && rmdir(dir) == 0);
}

static void test_rotate(void) {
	char dir[] = "/tmp/sirix-log-rotate-XXXXXX";
	assert(mkdtemp(dir));
	char path[256], old[256];
	snprintf(path, sizeof(path), "%s/SiriX.log", dir);
	snprintf(old, sizeof(old), "%s/SiriX.log.old", dir);

	// Tệp nhỏ: không xoay, tệp giữ nguyên.
	append(path, "small\n");
	assert(SXLogFileRotateIfLargerThan(path, old, 1024) == 0);
	expect(path, "small\n");

	// Vượt trần: chuyển sang .old, tệp mới bắt đầu rỗng; bản .old cũ bị thay.
	assert(SXLogFileRotateIfLargerThan(path, old, 1) == 1);
	// Sau khi xoay, tệp hiện tại chưa tồn tại cho tới lần ghi kế tiếp.
	assert(SXLogFileSize(path) == -1);
	expect(old, "small\n");
	append(path, "fresh\n");
	assert(SXLogFileRotateIfLargerThan(path, old, 1) == 1);
	expect(old, "fresh\n");

	// Tệp không tồn tại: không phải lỗi, cũng không xoay.
	assert(SXLogFileRotateIfLargerThan("/tmp/sirix-khong-co.log", old, 1) == 0);
	// `path` không tồn tại sau lần xoay ở trên — chỉ dọn những gì còn lại.
	assert(unlink(old) == 0);
	if (SXLogFileSize(path) >= 0) assert(unlink(path) == 0);
	assert(rmdir(dir) == 0);
}

int main(void) {
	test_read_tail();
	test_partial_writes();
	test_rotate();
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
