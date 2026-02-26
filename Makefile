# Makefile — openchad project task runner
#
# Targets:
#   install    — run install.sh in --yes mode
#   test       — run full npm test suite
#   update     — pull latest and re-run setup
#   clean      — remove generated artifacts and temp files
#   uninstall  — remove symlinks and shell profile blocks

.PHONY: install test verify update clean uninstall

install:
	bash install.sh --yes

test: verify

verify:
	npm test

update:
	bash -c 'openchad update || bin/openchad update'

clean:
	find . -name '*.bak' -o -name '*.orig' -o -name '*.tmp' | xargs rm -f 2>/dev/null || true

uninstall:
	bash -c 'openchad uninstall --yes || bin/openchad uninstall --yes'
