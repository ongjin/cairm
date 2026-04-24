# Opening paths in Cairn from outside the app

Cairn listens on three entry points:

## 1. URL scheme (`cairn://`)

```text
cairn://open?path=/Users/you/work
cairn://remote?host=prod&path=/var/log
```

Register happens automatically on first launch. Any macOS app that can open a URL can launch Cairn.

## 2. `cairn` CLI

Install once:

```sh
make install-cli      # writes /usr/local/bin/cairn
```

Then:

```sh
cairn ~/work                 # shorthand: open local
cairn open /tmp              # explicit form
cairn remote prod /var/log   # open SSH alias from ~/.ssh/config
```

## 3. Finder > Services > "Open in Cairn"

The service is registered on first launch. If it doesn't appear in Finder's right-click Services submenu:

```sh
/System/Library/CoreServices/pbs -update
killall Finder
```
