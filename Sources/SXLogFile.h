#ifndef SX_LOG_FILE_H
#define SX_LOG_FILE_H

// File operations shared by the iOS logger and the portable regression test.
// Open every time so other processes can remove or rotate the path safely.
#include <errno.h>
#include <stdio.h>
#include <fcntl.h>
#include <stddef.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// Ghi cả dòng trong MỘT descriptor với O_APPEND. `write` trên tệp thường có
// thể trả về ngắn (hoặc EINTR khi có signal — SpringBoard nhận khá nhiều), nên
// phải lặp tới khi ghi hết; trước đây một lần ghi ngắn là cả dòng log mất,
// đúng lúc log cần nhất (lỗi, exception).
static inline int SXLogFileAppend(const char *path, const char *bytes, size_t length) {
	if (!path || !bytes) return -1;
	int fd = open(path, O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC, 0644);
	if (fd < 0) return -1;
	size_t total = 0;
	int result = 0;
	while (total < length) {
		ssize_t written = write(fd, bytes + total, length - total);
		if (written < 0) {
			if (errno == EINTR) continue;
			result = -1;
			break;
		}
		if (written == 0) { result = -1; break; }
		total += (size_t)written;
	}
	if (close(fd) != 0 && result == 0) result = -1;
	return result;
}

/// Kích thước tệp (byte) hoặc -1 nếu không đọc được.
static inline off_t SXLogFileSize(const char *path) {
	struct stat st;
	if (!path || stat(path, &st) != 0) return -1;
	return st.st_size;
}

/// Xoay vòng khi tệp vượt `limit`: SiriX.log → SiriX.log.old (bản cũ bị xoá).
/// Trả về 1 nếu đã xoay, 0 nếu không cần, -1 nếu lỗi. Không bao giờ làm mất
/// tệp hiện tại khi bước đổi tên thất bại: khi đó chỉ cắt bớt bằng cách bỏ qua
/// và để lần gọi sau thử lại.
static inline int SXLogFileRotateIfLargerThan(const char *path, const char *oldPath, off_t limit) {
	off_t size = SXLogFileSize(path);
	if (size < 0) return 0;
	if (size <= limit) return 0;
	if (oldPath) (void)unlink(oldPath);
	if (rename(path, oldPath ? oldPath : path) != 0) return -1;
	return 1;
}

static inline int SXLogFileClear(const char *path) {
	int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
	if (fd < 0) return -1;
	return close(fd);
}

// Đọc phần CUỐI của file log (tail) — màn hình xem log không bao giờ phải nạp
// cả file vào bộ nhớ/UITextView, vốn là nguyên nhân làm Preferences treo cứng.
//
// buffer phải có sức chứa `capacity + 1` byte (hàm tự đặt '\0' ở cuối).
// Chỉ đọc tối đa `capacity` byte tính từ cuối file; khi phải cắt bớt, dòng đầu
// tiên (có thể bị cụt giữa UTF-8) được bỏ để văn bản bắt đầu ở ranh giới dòng.
//
// Trả về số byte đã ghi vào buffer (>= 0) hoặc -1 nếu không mở/đọc được.
// *outSize      = kích thước thật của file (0 nếu không đọc được).
// *outTruncated = 1 khi phần đầu file đã bị bỏ.
static inline ssize_t SXLogFileReadTail(const char *path, char *buffer, size_t capacity,
										off_t *outSize, int *outTruncated) {
	if (outSize) *outSize = 0;
	if (outTruncated) *outTruncated = 0;
	if (!buffer || capacity == 0) return -1;
	buffer[0] = '\0';

	int fd = open(path, O_RDONLY | O_CLOEXEC);
	if (fd < 0) return -1;

	struct stat st;
	if (fstat(fd, &st) != 0) {
		close(fd);
		return -1;
	}
	off_t size = st.st_size;
	if (outSize) *outSize = size > 0 ? size : 0;
	if (size <= 0) {
		close(fd);
		return 0;
	}

	off_t start = (off_t)capacity < size ? size - (off_t)capacity : 0;
	size_t total = 0;
	while (start + (off_t)total < size) {
		ssize_t got = pread(fd, buffer + total, (size_t)(size - start - (off_t)total),
							start + (off_t)total);
		if (got < 0) {
			if (errno == EINTR) continue;
			close(fd);
			buffer[0] = '\0';
			return -1;
		}
		if (got == 0) break;
		total += (size_t)got;
	}
	close(fd);
	buffer[total] = '\0';

	if (start > 0) {
		if (outTruncated) *outTruncated = 1;
		char *newline = memchr(buffer, '\n', total);
		if (newline) {
			size_t drop = (size_t)(newline - buffer) + 1;
			memmove(buffer, buffer + drop, total - drop);
			total -= drop;
			buffer[total] = '\0';
		} else {
			// Một dòng dài hơn cả cửa sổ đọc: bỏ hết để không hiển thị rác cụt.
			buffer[0] = '\0';
			total = 0;
		}
	}
	return (ssize_t)total;
}

#endif
