extends SceneTree
## Writes build/art_sheet.svg: the art of every card on one sheet, to look at.
## Usage: godot --headless --path . --script res://tools/art_sheet.gd


func _process(_d: float) -> bool:
	var ids := CardDb.all_ids()
	ids.sort()
	var cols := 14
	var cw := 120.0
	var ch := 100.0
	var svg := PackedStringArray(['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" style="background:#1b140f;font:9px sans-serif">' % [cols * cw, ceili(ids.size() / float(cols)) * ch]])
	for i in ids.size():
		var origin := Vector2((i % cols) * cw + 10, (i / cols) * ch + 6)
		for s in Art.shapes(ids[i], Rect2(origin, Vector2(100, 70))):
			match s[0]:
				"rect":
					svg.append('<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="#%s"/>' % [s[1].position.x, s[1].position.y, s[1].size.x, s[1].size.y, s[2].to_html()])
				"circle":
					svg.append('<circle cx="%.1f" cy="%.1f" r="%.1f" fill="#%s"/>' % [s[1].x, s[1].y, s[2], s[3].to_html()])
				"poly":
					var pts := PackedStringArray()
					for p in s[1]:
						pts.append("%.1f,%.1f" % [p.x, p.y])
					svg.append('<polygon points="%s" fill="#%s"/>' % [" ".join(pts), s[2].to_html()])
				"line":
					svg.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="#%s" stroke-width="%.1f" stroke-linecap="round"/>' % [s[1].x, s[1].y, s[2].x, s[2].y, s[3].to_html(), s[4]])
		svg.append('<text x="%.1f" y="%.1f" fill="#ddd">%s</text>' % [origin.x, origin.y + 84, CardText.name(ids[i]).xml_escape().left(22)])
	svg.append("</svg>")
	DirAccess.make_dir_recursive_absolute("res://build")
	var f := FileAccess.open("res://build/art_sheet.svg", FileAccess.WRITE)
	f.store_string("\n".join(svg))
	f.close()
	print("cards: ", ids.size())
	quit()
	return true
