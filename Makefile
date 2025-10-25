ZIG = zig
PREFIX ?= /usr

.PHONY: all install fmt


all:
	zig build -Doptimize=ReleaseSmall

clean:
	rm -rf ./external/minisign/zig-out 
	rm -rf ./external/minisign/.zig-cache
	rm -rf ./src/external-bin
	rm -rf ./zig-out
	rm -rf ./.zig-cache

install:
	install -Dm755 ./zig-out/bin/hclos "$(PREFIX)/bin/hclos"
	if [ -d "$(PREFIX)/etc" ]; then \
		install -Dm755 ./src/templates/repos_template.toml "$(PREFIX)/etc/hclos/repos.toml" \
	fi

fmt:
	find src -type f -name '*.zig' -exec zig fmt {} +
