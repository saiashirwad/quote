.PHONY: build install dev uninstall

IDENTITY ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $$2; exit}'),-)
BIN := $(HOME)/.local/bin/quote
PLIST := $(HOME)/Library/LaunchAgents/com.texoport.quote.plist
LOG := $(HOME)/Library/Logs/quote.log
AGENT := gui/$$(id -u)/com.texoport.quote

build:
	mkdir -p .build
	echo '{"CFBundleIdentifier":"com.texoport.quote","CFBundleName":"Quote","CFBundleExecutable":"quote","LSUIElement":true,"NSMicrophoneUsageDescription":"Used by macOS Dictation."}' | plutil -convert xml1 -o .build/Info.plist -
	swiftc -O -swift-version 6 main.swift -o .build/quote -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker .build/Info.plist

install: build
	mkdir -p $(HOME)/.local/bin $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	cp .build/quote $(BIN)
	codesign --force --sign "$(IDENTITY)" --identifier com.texoport.quote $(BIN)
	echo '{"Label":"com.texoport.quote","ProgramArguments":["$(BIN)"],"RunAtLoad":true,"KeepAlive":true,"StandardOutPath":"$(LOG)","StandardErrorPath":"$(LOG)","LimitLoadToSessionType":"Aqua"}' | plutil -convert xml1 -o $(PLIST) -
	-launchctl bootout $(AGENT) 2>/dev/null
	launchctl bootstrap gui/$$(id -u) $(PLIST)

dev: install
	tail -n 0 -f $(LOG)

uninstall:
	-launchctl bootout $(AGENT) 2>/dev/null
	rm -f $(PLIST) $(BIN)
