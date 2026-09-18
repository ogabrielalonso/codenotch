# dmgbuild settings for the disk image `make dmg-ci` builds. dmgbuild runs this
# file with `defines` set from its -D flags:
#
#   app     the Codenotch.app to ship
#   art     the folder Scripts/dmg-background.swift wrote into
#
# Where the icons go comes from that folder's layout.json, written by the same
# script that draws the arrow between them.
import json
import os.path

app = defines["app"]
art = defines["art"]
with open(os.path.join(art, "layout.json")) as f:
    layout = json.load(f)

format = "UDZO"
files = [app]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app, "Contents", "Resources", "AppIcon.icns")

# 1x and 2x in one file, so a Retina display gets the sharp one.
background = os.path.join(art, "background.tiff")
# Finder's window frame: the content area plus its 32pt title bar (measured on
# macOS 26 with the toolbar hidden).
window_rect = ((200, 120), (layout["width"], layout["height"] + 32))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
# Someone who has the path and status bars on in every Finder window still
# gets them here; the background keeps its bottom clear for that.
show_status_bar = False
show_pathbar = False
show_tab_view = False
show_icon_preview = False
arrange_by = None
icon_size = layout["icon_size"]
text_size = 13
label_pos = "bottom"
icon_locations = {
    os.path.basename(app): tuple(layout["app"]),
    "Applications": tuple(layout["applications"]),
}
