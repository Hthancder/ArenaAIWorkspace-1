# common-scheme.mk — chọn package scheme cho SiriBridge
#
# Chỉ hỗ trợ 2 scheme: rootless (mặc định) và roothide.
# Rootful bị CHẶN cứng để không bao giờ build nhầm.
#
#   make package                              -> rootless
#   make package SCHEME=roothide              -> roothide
#   make package THEOS_PACKAGE_SCHEME=roothide -> roothide (tương thích)
#
# Lưu ý: roothide ép package arch = iphoneos-arm64e (quy ước của roothide),
# nhưng binary bên trong vẫn là arm64 thuần — ARCHS luôn = arm64, không arm64e.

SB_SCHEME := $(if $(SCHEME),$(SCHEME),$(if $(THEOS_PACKAGE_SCHEME),$(THEOS_PACKAGE_SCHEME),rootless))

ifeq ($(strip $(SB_SCHEME)),)
SB_SCHEME := rootless
endif

ifeq ($(filter $(SB_SCHEME),rootless roothide),)
$(error SCHEME='$(SB_SCHEME)' không được hỗ trợ. Chỉ có: rootless hoặc roothide (KHÔNG hỗ trợ rootful))
endif

export THEOS_PACKAGE_SCHEME = $(SB_SCHEME)
export SB_SCHEME

# Chỉ arm64 — không bao giờ arm64e
export ARCHS = arm64

ifeq ($(SB_SCHEME),roothide)
export SB_ARCH_LABEL = roothide
else
export SB_ARCH_LABEL = rootless
endif
