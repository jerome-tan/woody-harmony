"""Headless Finder layout used by dmgbuild (coordinates are logical points)."""
from pathlib import Path

resources = Path(defines["resources"]).resolve()
application = str(Path(defines["app"]).resolve())
files = [(application, "Woody.app")]
symlinks = {"Applications": "/Applications"}
# Do not set FinderInfo on the signed .app (including hide_extensions):
# codesign --verify --strict rejects that metadata. Finder already presents apps by name.
icon = str(resources / "icon.icns")
background = str(resources / "dmg/background.png")
format = "UDZO"
filesystem = "HFS+"
# Finder's outer height includes the 32-point title bar; keep 400 points of artwork visible.
window_rect = ((160, 180), (640, 432))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_tab_view = False
show_pathbar = False
arrange_by = None
icon_size = 96
text_size = 14
label_pos = "bottom"
icon_locations = {"Woody.app": (174, 202), "Applications": (466, 202)}
