include theos/makefiles/common.mk

TWEAK_NAME = ProclivityReload
ProclivityReload_FILES = Tweak.xm
ProclivityReload_PRIVATE_FRAMEWORKS = AppSupport
SHARED_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
