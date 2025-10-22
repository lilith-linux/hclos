ZIG = zig
PREFIX ?= /usr

.PHONY: all install fmt


all:
	zig build -Doptimize=ReleaseFast


install:
	install -Dm755 ./zig-out/bin/hclos "$(PREFIX)/bin/hclos"
	if [ -d "$(PREFIX)/etc" ]; then \
		install -Dm755 ./src/templates/repos_template.toml "$(PREFIX)/etc/hclos/repos.toml" \
	fi
	ln -s "$(PREFIX)/bin/hclos" "$(PREFIX)/bin/huis-boot"

fmt:
	find src -type f -name '*.zig' -exec zig fmt {} +
