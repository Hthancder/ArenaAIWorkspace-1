#include <cassert>
#include <cstdio>
#include "core/wifi/web_navigation.h"
int main() {
  WebNavCommand nav{};
  assert(parseWebNav("nav nextpage", nav) && nav.button == WebNavButton::NextPage && nav.durationMs == 1);
  assert(parseWebNav("nav prevpage", nav) && nav.button == WebNavButton::PreviousPage);
  assert(parseWebNav("nav next", nav) && nav.button == WebNavButton::Next);
  assert(parseWebNav("nav sel 500", nav) && nav.button == WebNavButton::Select && nav.durationMs == 500);
  assert(!parseWebNav("nav nextpagex", nav));
  assert(!parseWebNav("nav menu", nav));
  assert(!parseWebNav("nav sel -1", nav));
  assert(!parseWebNav("nav sel 2001", nav));
  assert(!parseWebNav("nav sel 1 foo", nav));
  assert(!parseWebNav("nav", nav));
  std::puts("navigation parser regression tests passed");
}
