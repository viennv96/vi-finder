.PHONY: app universal package run install clean

app:
	@scripts/build-app.sh release native

universal:
	@scripts/build-app.sh release universal

package: universal
	@scripts/package.sh

run: app
	@open build/ViFinder.app

install: app
	@rm -rf /Applications/ViFinder.app
	@cp -R build/ViFinder.app /Applications/
	@echo "✓ Installed to /Applications/ViFinder.app"

clean:
	@rm -rf .build build
