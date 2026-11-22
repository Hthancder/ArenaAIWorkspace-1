#ifndef SX_NET_POLICY_H
#define SX_NET_POLICY_H

// Chính sách mạng dùng chung — C thuần để test được trên Linux (giống
// SXLogFile.h) và để cả tầng HTTP lẫn tầng công cụ dùng đúng một luật.
//
// Vì sao cần: `web_fetch` cho model tự đặt URL, và model có thể bị lừa bởi nội
// dung trang web. Chặn "host nội bộ" phải xét cả những dạng viết tắt mà
// `inet_pton` không nhận:
//     127.0.0.1   127.1       2130706433   0x7f000001   017700000001
//     ::1         [::1]       ::ffff:127.0.0.1            fc00::/7  fe80::/10
// Thiếu một dạng là một lỗ hổng đọc mạng nội bộ (router, NAS, máy chủ dev…).

#include <arpa/inet.h>
#include <ctype.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define SX_NET_HOST_MAX 512

/// Bỏ "[", "]" và dấu "." cuối — dạng hợp lệ khi viết tên miền tuyệt đối.
static inline void SXNetNormalizeHost(const char *host, char out[SX_NET_HOST_MAX]) {
	out[0] = '\0';
	if (!host) return;
	while (*host && isspace((unsigned char)*host)) host++;
	size_t length = strlen(host);
	while (length && isspace((unsigned char)host[length - 1])) length--;
	if (length >= 2 && host[0] == '[' && host[length - 1] == ']') {
		host++;
		length -= 2;
	}
	while (length && host[length - 1] == '.') length--;
	if (length >= SX_NET_HOST_MAX) length = SX_NET_HOST_MAX - 1;
	for (size_t i = 0; i < length; i++) out[i] = (char)tolower((unsigned char)host[i]);
	out[length] = '\0';
}

static inline bool SXNetHostEndsWith(const char *host, const char *suffix) {
	size_t hostLength = strlen(host);
	size_t suffixLength = strlen(suffix);
	return hostLength >= suffixLength && strcmp(host + hostLength - suffixLength, suffix) == 0;
}

/// Địa chỉ IPv4 (đã ở dạng số 32 bit, thứ tự host) có thuộc mạng riêng?
static inline bool SXNetIPv4IsPrivate(unsigned long value) {
	unsigned int a = (unsigned int)((value >> 24) & 0xFFu);
	unsigned int b = (unsigned int)((value >> 16) & 0xFFu);
	if (a == 0 || a == 10 || a == 127) return true;                 // 0/8, 10/8, loopback
	if (a == 169 && b == 254) return true;                          // link-local
	if (a == 172 && b >= 16 && b <= 31) return true;                // 172.16/12
	if (a == 192 && b == 168) return true;                          // 192.168/16
	if (a == 100 && b >= 64 && b <= 127) return true;               // CGNAT 100.64/10
	if (a == 192 && b == 0) return true;                            // 192.0.0.0/24, 192.0.2.0/24
	if (a == 198 && (b == 18 || b == 19)) return true;              // benchmark 198.18/15
	if (a >= 224) return true;                                      // multicast + reserved + broadcast
	return false;
}

/// Đọc một "phần" của IPv4 theo đúng quy ước inet_aton: hệ 10, 0x…, 0… (bát
/// phân). Trả về false nếu có ký tự lạ.
static inline bool SXNetParseIPv4Part(const char **cursor, unsigned long *outValue) {
	const char *p = *cursor;
	unsigned long value = 0;
	int base = 10;
	int digits = 0;
	if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) {
		base = 16;
		p += 2;
	} else if (p[0] == '0' && p[1] >= '0' && p[1] <= '7') {
		base = 8;
	}
	while (*p) {
		int digit;
		if (*p >= '0' && *p <= '9') digit = *p - '0';
		else if (base == 16 && *p >= 'a' && *p <= 'f') digit = *p - 'a' + 10;
		else if (base == 16 && *p >= 'A' && *p <= 'F') digit = *p - 'A' + 10;
		else break;
		if (digit >= base) return false;
		value = value * (unsigned long)base + (unsigned long)digit;
		if (value > 0xFFFFFFFFul) return false;
		digits++;
		p++;
	}
	if (!digits) return false;
	*cursor = p;
	if (outValue) *outValue = value;
	return true;
}

/// Toàn bộ chuỗi là số IPv4 (dạng bất kỳ mà inet_aton chấp nhận)?
static inline bool SXNetParseIPv4(const char *host, unsigned long *outValue) {
	const char *p = host;
	unsigned long parts[4] = {0, 0, 0, 0};
	int count = 0;
	while (count < 4) {
		unsigned long value = 0;
		if (!SXNetParseIPv4Part(&p, &value)) return false;
		parts[count++] = value;
		if (*p == '.') {
			p++;
			continue;
		}
		break;
	}
	if (*p != '\0') return false;   // ký tự lạ ⇒ không phải IP dạng số

	unsigned long result;
	switch (count) {
		case 1: result = parts[0]; break;
		case 2: result = (parts[0] << 24) | (parts[1] & 0xFFFFFFul); break;
		case 3: result = (parts[0] << 24) | ((parts[1] & 0xFFul) << 16) | (parts[2] & 0xFFFFul); break;
		default: result = (parts[0] << 24) | ((parts[1] & 0xFFul) << 16) |
						 ((parts[2] & 0xFFul) << 8) | (parts[3] & 0xFFul); break;
	}
	if (outValue) *outValue = result;
	return true;
}

/// IPv6 (kể cả dạng IPv4-mapped) có thuộc mạng riêng/loopback/link-local?
static inline bool SXNetIPv6IsPrivate(const unsigned char address[16]) {
	static const unsigned char loopback[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1};
	static const unsigned char unspec[16] = {0};
	if (memcmp(address, loopback, 16) == 0) return true;
	if (memcmp(address, unspec, 16) == 0) return true;
	if ((address[0] & 0xFE) == 0xFC) return true;                       // fc00::/7 unique-local
	if (address[0] == 0xFE && (address[1] & 0xC0) == 0x80) return true; // fe80::/10 link-local
	if (address[0] == 0xFF) return true;                                // multicast
	// ::ffff:a.b.c.d — IPv4-mapped: xét theo luật IPv4 để không lách qua được.
	static const unsigned char mapped[12] = {0,0,0,0,0,0,0,0,0,0,0xFF,0xFF};
	if (memcmp(address, mapped, 12) == 0) {
		unsigned long v4 = ((unsigned long)address[12] << 24) | ((unsigned long)address[13] << 16) |
						   ((unsigned long)address[14] << 8) | (unsigned long)address[15];
		return SXNetIPv4IsPrivate(v4);
	}
	return false;
}

/// Host có phải "nội bộ" (không được cho công cụ đọc)?
/// Bảo thủ theo hướng AN TOÀN: tên lạ không phân giải được thành IP công khai
/// vẫn được coi là công khai (DNS sẽ tự thất bại), nhưng mọi dạng số/địa chỉ
/// nội bộ đều bị chặn.
static inline bool SXNetHostIsPrivate(const char *host) {
	char normalized[SX_NET_HOST_MAX];
	SXNetNormalizeHost(host, normalized);
	if (!normalized[0]) return true;

	if (strcmp(normalized, "localhost") == 0 || SXNetHostEndsWith(normalized, ".localhost") ||
		SXNetHostEndsWith(normalized, ".local") || SXNetHostEndsWith(normalized, ".internal") ||
		SXNetHostEndsWith(normalized, ".lan") || SXNetHostEndsWith(normalized, ".home") ||
		SXNetHostEndsWith(normalized, ".localdomain") || strcmp(normalized, "ip6-localhost") == 0 ||
		strcmp(normalized, "ip6-loopback") == 0) {
		return true;
	}

	// Có ':' ⇒ IPv6 (hoặc host:port lọt vào). Chỉ nhận khi inet_pton hiểu.
	if (strchr(normalized, ':')) {
		unsigned char address[16];
		if (inet_pton(AF_INET6, normalized, address) == 1) return SXNetIPv6IsPrivate(address);
		return true;   // dạng lạ: coi như nội bộ (an toàn)
	}

	unsigned long v4 = 0;
	if (SXNetParseIPv4(normalized, &v4)) return SXNetIPv4IsPrivate(v4);

	// Chuỗi chỉ gồm số và dấu chấm mà không phân tích được: chặn cho chắc.
	bool onlyDigitsAndDots = true;
	for (const char *p = normalized; *p; p++) {
		if (!isdigit((unsigned char)*p) && *p != '.') { onlyDigitsAndDots = false; break; }
	}
	if (onlyDigitsAndDots) return true;
	return false;
}

/// Host có phải loopback (dùng cho thông điệp lỗi cụ thể hơn)?
static inline bool SXNetHostIsLoopback(const char *host) {
	char normalized[SX_NET_HOST_MAX];
	SXNetNormalizeHost(host, normalized);
	if (strcmp(normalized, "localhost") == 0 || SXNetHostEndsWith(normalized, ".localhost")) return true;
	unsigned long v4 = 0;
	if (SXNetParseIPv4(normalized, &v4)) return ((v4 >> 24) & 0xFFul) == 127;
	if (strchr(normalized, ':')) {
		unsigned char address[16];
		if (inet_pton(AF_INET6, normalized, address) == 1) {
			static const unsigned char loopback[16] = {0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1};
			return memcmp(address, loopback, 16) == 0;
		}
	}
	return false;
}

/// Chuyển hướng có được phép đi tiếp không? (chỉ http(s), chỉ tới host công khai)
static inline bool SXNetRedirectAllowed(const char *fromScheme, const char *toScheme, const char *toHost) {
	if (!toScheme || !toHost) return false;
	if (strcasecmp(toScheme, "https") != 0 && strcasecmp(toScheme, "http") != 0) return false;
	if (fromScheme && strcasecmp(fromScheme, "https") == 0 && strcasecmp(toScheme, "http") == 0) {
		return false;   // hạ cấp bảo mật: không đi
	}
	return !SXNetHostIsPrivate(toHost);
}

#endif
