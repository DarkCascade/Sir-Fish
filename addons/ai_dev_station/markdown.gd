@tool
extends RefCounted

## Minimal Markdown -> BBCode converter for the transcript.
##
## Only covers what Claude actually emits in chat: fenced code, inline code,
## bold/italic, headings, bullets, numbered lists, blockquotes and links.
## Anything unrecognised falls through as literal text.

const CODE_BG := "#00000040"

static var _bold_re: RegEx
static var _italic_re: RegEx
static var _link_re: RegEx


static func _ensure_regex() -> void:
	if _bold_re != null:
		return
	_bold_re = RegEx.create_from_string("\\*\\*(.+?)\\*\\*")
	_italic_re = RegEx.create_from_string("(?<![\\*\\w])\\*([^\\*\\n]+?)\\*(?!\\*)")
	# Runs against already-escaped text, where a literal "[" has become "[lb]".
	_link_re = RegEx.create_from_string("\\[lb\\]([^\\]\\n]+)\\]\\(([^\\)\\s]+)\\)")


## Escape BBCode control characters so model output is never interpreted as markup.
static func escape(text: String) -> String:
	return text.replace("[", "[lb]")


static func to_bbcode(md: String) -> String:
	_ensure_regex()
	var out := ""
	# Odd-numbered segments are the insides of ``` fences.
	var segments := md.split("```")
	for i in segments.size():
		var seg: String = segments[i]
		if i % 2 == 1:
			out += _render_code_block(seg)
		else:
			out += _render_prose(seg)
	return out


static func _render_code_block(seg: String) -> String:
	var body := seg
	var nl := seg.find("\n")
	if nl != -1 and _is_language_tag(seg.substr(0, nl).strip_edges()):
		body = seg.substr(nl + 1)
	body = body.strip_edges(false, true)
	return "\n[bgcolor=%s][code]%s[/code][/bgcolor]\n" % [CODE_BG, escape(body)]


## True for the short token on an opening fence (```gdscript), false for a real
## first line of code that happens to contain no spaces (x=1).
static func _is_language_tag(first: String) -> bool:
	if first.is_empty() or first.length() > 20:
		return false
	for c: String in first:
		if not (c.is_valid_identifier() or c.is_valid_int() or c in ["+", "-", "#"]):
			return false
	return true


static func _render_prose(seg: String) -> String:
	var lines := seg.split("\n")
	var rendered := PackedStringArray()
	for line: String in lines:
		rendered.append(_render_line(line))
	return "\n".join(rendered)


static func _render_line(line: String) -> String:
	var stripped := line.strip_edges(true, false)
	var indent := line.length() - stripped.length()
	var pad := " ".repeat(indent)

	# Headings.
	if stripped.begins_with("#"):
		var level := 0
		while level < stripped.length() and stripped[level] == "#":
			level += 1
		if level <= 6 and level < stripped.length() and stripped[level] == " ":
			var bump := maxi(1, 5 - level)
			return "[font_size=+%d][b]%s[/b][/font_size]" % [bump, _inline(stripped.substr(level + 1))]

	# Horizontal rule.
	if stripped == "---" or stripped == "***":
		return "[color=#7f7f7f]--------------------[/color]"

	# Blockquote.
	if stripped.begins_with("> "):
		return "%s[color=#9aa0a6]| %s[/color]" % [pad, _inline(stripped.substr(2))]

	# Bullets.
	if stripped.begins_with("- ") or stripped.begins_with("* ") or stripped.begins_with("+ "):
		return "%s  [color=#7aa2f7]-[/color] %s" % [pad, _inline(stripped.substr(2))]

	# Numbered list: keep the author's numbering.
	var dot := stripped.find(". ")
	if dot > 0 and dot <= 3 and stripped.substr(0, dot).is_valid_int():
		return "%s  [color=#7aa2f7]%s.[/color] %s" % [pad, stripped.substr(0, dot), _inline(stripped.substr(dot + 2))]

	return pad + _inline(stripped)


## Inline formatting. Escapes first so no model text can inject BBCode.
static func _inline(text: String) -> String:
	_ensure_regex()
	var out := ""
	# Odd-numbered segments sit between single backticks.
	var parts := text.split("`")
	for i in parts.size():
		var seg: String = parts[i]
		if i % 2 == 1:
			out += "[bgcolor=%s][code]%s[/code][/bgcolor]" % [CODE_BG, escape(seg)]
		else:
			var s := escape(seg)
			s = _link_re.sub(s, "[url=$2]$1[/url]", true)
			s = _bold_re.sub(s, "[b]$1[/b]", true)
			s = _italic_re.sub(s, "[i]$1[/i]", true)
			out += s
	return out
