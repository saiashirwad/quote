.PHONY: all app dev install uninstall test

IDENTITY ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $$2; exit}'),-)
CURDIR := $(abspath .)
APP := $(CURDIR)/.build/Quote.app
PLIST_DST := $(HOME)/Library/LaunchAgents/com.texoport.quote.plist

all: app

app:
	swift build -c release
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS
	cp $(CURDIR)/.build/release/quote $(APP)/Contents/MacOS/quote
	cp $(CURDIR)/Resources/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(IDENTITY)" $(APP)

dev: app
	pkill -x quote || true
	: > $(CURDIR)/.build/dev.log
	bash -c 'open -n --stdout $(CURDIR)/.build/dev.log --stderr $(CURDIR)/.build/dev.log $(APP); trap "pkill -x quote" EXIT; tail -f $(CURDIR)/.build/dev.log'

install: app
	mkdir -p $(HOME)/Applications $(HOME)/Library/LaunchAgents $(HOME)/Library/Logs
	rm -rf $(HOME)/Applications/Quote.app
	ditto $(APP) $(HOME)/Applications/Quote.app
	sed -e 's|__EXE__|$(HOME)/Applications/Quote.app/Contents/MacOS/quote|g' -e 's|__LOG__|$(HOME)/Library/Logs/quote.log|g' $(CURDIR)/Resources/launchd.plist > $(PLIST_DST)
	-launchctl bootout gui/$$(id -u)/com.texoport.quote 2>/dev/null || true
	launchctl bootstrap gui/$$(id -u) $(PLIST_DST)

uninstall:
	-launchctl bootout gui/$$(id -u)/com.texoport.quote 2>/dev/null || true
	rm -f $(PLIST_DST)
	rm -rf $(HOME)/Applications/Quote.app

test:
	swift test
