# Part of Jord Dev. Copyright (C) 2026 Mikka Luster
# SPDX-License-Identifier: GPL-3.0-or-later

.PHONY: ios debug install

# Jord Dev, built and put on the iPhone connected by USB or on the same
# network (paired, with Developer Mode on), then launched. Installing over
# the app keeps its store. DEVICE= picks one by name or UDID when more than
# one is connected.
#
#   make ios     Release
#   make debug   Debug, as Xcode's Run builds it
#
# BUNDLE_ID= is the bundle identifier set in the project, to launch the app by.

BUNDLE_ID ?= com.example.jorddev

ios:
	@$(MAKE) --no-print-directory install CONFIGURATION=Release

debug:
	@$(MAKE) --no-print-directory install CONFIGURATION=Debug

install:
	xcodebuild -project JordDev.xcodeproj -target JordDev -configuration $(CONFIGURATION) -sdk iphoneos -quiet \
		-allowProvisioningUpdates SYMROOT="$(PWD)/.build" OBJROOT="$(PWD)/.build/Intermediates" build
	@device="$(DEVICE)"; \
	if [ -z "$$device" ]; then \
		xcrun devicectl list devices --json-output /tmp/jord-dev-devices.json >/dev/null 2>&1; \
		device=$$(python3 -c 'import json; d=json.load(open("/tmp/jord-dev-devices.json"))["result"]["devices"]; \
			p=[x for x in d if x["hardwareProperties"].get("reality")=="physical" and x["hardwareProperties"].get("deviceType")=="iPhone" \
			and x["connectionProperties"].get("tunnelState")!="unavailable"]; print(p[0]["identifier"] if p else "")'); \
	fi; \
	if [ -z "$$device" ]; then echo "No iPhone connected. Plug it in, unlock it, and trust this Mac."; exit 1; fi; \
	xcrun devicectl device install app --device "$$device" .build/$(CONFIGURATION)-iphoneos/JordDev.app >/dev/null && \
	echo "Installed Jord Dev ($(CONFIGURATION))." && \
	{ xcrun devicectl device process launch --device "$$device" $(BUNDLE_ID) >/dev/null 2>&1 \
		&& echo "Launched." || echo "Not launched: the phone is probably locked. Open Jord Dev on it."; }
