// Regression cho SXNetPolicy.h — luật "địa chỉ nội bộ" của web_fetch.
//
// Vì sao có test này: bản trước chỉ so sánh chuỗi + inet_pton(AF_INET), nên
// các dạng viết tắt dưới đây đọc được mạng nội bộ (router, NAS, 127.0.0.1…)
// dù đã "chặn". Test chạy trên Linux/macOS, không cần iOS SDK.
#define _GNU_SOURCE
#include "SXNetPolicy.h"
#include <assert.h>
#include <stdio.h>

static void expect_private(const char *host) {
	if (!SXNetHostIsPrivate(host)) {
		fprintf(stderr, "✗ '%s' phải bị coi là nội bộ nhưng lại được cho qua\n", host);
		assert(0 && "host nội bộ lọt lưới");
	}
}

static void expect_public(const char *host) {
	if (SXNetHostIsPrivate(host)) {
		fprintf(stderr, "✗ '%s' là host công khai nhưng bị chặn\n", host);
		assert(0 && "host công khai bị chặn oan");
	}
}

static void test_short_forms(void) {
	// Mọi dạng dưới đây đều là 127.0.0.1 với inet_aton nhưng inet_pton từ chối.
	expect_private("127.0.0.1");
	expect_private("127.1");
	expect_private("127.0.1");
	expect_private("2130706433");
	expect_private("0x7f000001");
	expect_private("0x7F.0.0.1");
	expect_private("017700000001");
	expect_private(" 127.0.0.1 ");
}

static void test_ipv4_ranges(void) {
	const char *privateHosts[] = {
		"0.0.0.0", "10.0.0.1", "10.255.255.254", "169.254.169.254", "172.16.0.1",
		"172.31.255.255", "192.168.1.1", "192.168.0.1.", "100.64.0.1", "100.127.255.1",
		"192.0.2.10", "198.18.0.1", "224.0.0.1", "255.255.255.255", "1.1.1.1.1",
	};
	for (size_t i = 0; i < sizeof(privateHosts) / sizeof(privateHosts[0]); i++) {
		expect_private(privateHosts[i]);
	}
	const char *publicHosts[] = {
		"8.8.8.8", "1.1.1.1", "172.32.0.1", "172.15.255.255", "100.63.255.255",
		"100.128.0.1", "192.169.0.1", "11.0.0.1", "203.0.113.9",
	};
	for (size_t i = 0; i < sizeof(publicHosts) / sizeof(publicHosts[0]); i++) {
		expect_public(publicHosts[i]);
	}
}

static void test_names_and_ipv6(void) {
	const char *privateHosts[] = {
		"localhost", "LOCALHOST", "app.localhost", "printer.local", "nas.internal",
		"router.lan", "device.home", "box.localdomain", "ip6-localhost",
		"::1", "[::1]", "::", "fe80::1", "fc00::1", "fd12:3456::1", "ff02::1",
		"::ffff:127.0.0.1", "::ffff:192.168.1.1", "0000:0000:0000:0000:0000:0000:0000:0001",
		"[::ffff:7f00:1]",
	};
	for (size_t i = 0; i < sizeof(privateHosts) / sizeof(privateHosts[0]); i++) {
		expect_private(privateHosts[i]);
	}
	const char *publicHosts[] = {
		"example.com", "api.openai.com", "www.google.com.vn", "2001:4860:4860::8888",
		"::ffff:8.8.8.8", "[2606:4700:4700::1111]",
	};
	for (size_t i = 0; i < sizeof(publicHosts) / sizeof(publicHosts[0]); i++) {
		expect_public(publicHosts[i]);
	}
}

static void test_normalize(void) {
	char out[SX_NET_HOST_MAX];
	SXNetNormalizeHost("  [Example.COM.]  ", out);
	assert(strcmp(out, "example.com") == 0);
	SXNetNormalizeHost("", out);
	assert(out[0] == '\0');
	SXNetNormalizeHost(NULL, out);
	assert(out[0] == '\0');
}

static void test_loopback(void) {
	assert(SXNetHostIsLoopback("127.0.0.1"));
	assert(SXNetHostIsLoopback("127.9.9.9"));
	assert(SXNetHostIsLoopback("localhost"));
	assert(SXNetHostIsLoopback("::1"));
	assert(!SXNetHostIsLoopback("192.168.1.1"));
	assert(!SXNetHostIsLoopback("example.com"));
}

static void test_redirect(void) {
	// https → http bị chặn (hạ cấp), còn lại chỉ tới host công khai.
	assert(SXNetRedirectAllowed("https", "https", "example.com"));
	assert(SXNetRedirectAllowed("http", "https", "example.com"));
	assert(!SXNetRedirectAllowed("https", "http", "example.com"));
	assert(!SXNetRedirectAllowed("https", "https", "127.0.0.1"));
	assert(!SXNetRedirectAllowed("https", "https", "metadata.internal"));
	assert(!SXNetRedirectAllowed("https", "file", "example.com"));
	assert(!SXNetRedirectAllowed("https", "https", NULL));
	assert(!SXNetRedirectAllowed("https", NULL, "example.com"));
}

int main(void) {
	test_short_forms();
	test_ipv4_ranges();
	test_names_and_ipv6();
	test_normalize();
	test_loopback();
	test_redirect();
	printf("net policy regression: OK\n");
	return 0;
}
