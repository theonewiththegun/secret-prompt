PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
SWIFTC ?= swiftc
# Universal by default; ARCHS=arm64 builds for one, which nix and quick local builds want.
ARCHS ?= arm64 x86_64
# Nix's wrapped swiftc pins its own target, so the nix build sets TARGET empty.
TARGET ?= -target $(1)-apple-macos12

SOURCES := $(wildcard Sources/*.swift)
SCRIPTS := bin/asudo bin/with-secret

build/secret-prompt: $(foreach arch,$(ARCHS),build/secret-prompt-$(arch))
	$(if $(word 2,$^),lipo -create $^ -output $@,cp $^ $@)

build/secret-prompt-%: $(SOURCES)
	@mkdir -p build
	$(SWIFTC) -O $(call TARGET,$*) -framework AppKit -o $@ $(SOURCES)

.PHONY: install uninstall test lint clean
install: build/secret-prompt
	install -d $(DESTDIR)$(BINDIR)
	install -m 755 build/secret-prompt $(SCRIPTS) $(DESTDIR)$(BINDIR)

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/secret-prompt $(DESTDIR)$(BINDIR)/asudo $(DESTDIR)$(BINDIR)/with-secret

test: build/secret-prompt
	tests/run.sh build/secret-prompt

lint:
	shellcheck $(SCRIPTS) tests/*.sh scripts/*.sh

clean:
	rm -rf build
