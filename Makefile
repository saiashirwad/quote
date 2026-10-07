.PHONY: all app dev install uninstall

IDENTITY ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $$2; exit}'),-)
CURDIR := $(abspath .)
APP := $(CURDIR)/.build/Quote.app
PLIST_DST := $(HOME)/Library/LaunchAgents/com.texoport.quote.plist

all: app

app:
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	swiftc -O -swift-version 6 main.swift -o $(APP)/Contents/MacOS/quote
	echo '{"CFBundleIdentifier":"com.texoport.quote","CFBundleName":"Quote","CFBundleExecutable":"quote","CFBundlePackageType":"APPL","LSUIElement":true,"NSMicrophoneUsageDescription":"Used by macOS Dictation."}' | plutil -convert xml1 -o $(APP)/Contents/Info.plist -
	codesign --force --sign "$(IDENTITY)" $(APP)

dev: app
	pkill -x quote || true
	: > $(CURDIR)/.build/dev.log
	bash -c 'open -n --stdout $(CURDIR)/.build/dev.log --stderr $(CURDIR)/.build/dev.log $(APP); trap "pkill -x quote" EXIT; tail -f $(CURDIR)/.build/dev.log'

install: app
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	rm -rf $(HOME)/Applications/Quote.app
	ditto $(APP) $(HOME)/Applications/Quote.app
	echo '{"Label":"com.texoport.quote","ProgramArguments":["$(HOME)/Applications/Quote.app/Contents/MacOS/quote"],"RunAtLoad":true,"KeepAlive":true,"StandardOutPath":"$(HOME)/Library/Logs/quote.log","StandardErrorPath":"$(HOME)/Library/Logs/quote.log","LimitLoadToSessionType":"Aqua"}' | plutil -convert xml1 -o $(PLIST_DST) -
	-launchctl bootout gui/$$(id -u)/com.texoport.quote 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(PLIST_DST)

uninstall:
	-launchctl bootout gui/$$(id -u)/com.texoport.quote 2>/dev/null || true
	rm -f $(PLIST_DST)
	rm -rf $(HOME)/Applications/Quote.app
