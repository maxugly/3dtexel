@tool
extends RefCounted
## Extract explicit public author/format declarations, never infer an author from a publisher.
static func find_author(value: Variant) -> Variant:
	if value is Dictionary:
		for key in ["author","creator"]:
			if value.has(key):return value[key]
		for child in value.values():
			var found: Variant=find_author(child)
			if found!=null:return found
	elif value is Array:
		for child in value:
			var found: Variant=find_author(child)
			if found!=null:return found
	return null
static func from_html(html: String, source_url: String) -> Dictionary:
	var result := {"metadata_source_url":source_url}
	var scripts := RegEx.create_from_string("(?is)<script[^>]*type=[\"']application/ld\\+json[\"'][^>]*>(.*?)</script>")
	for match in scripts.search_all(html):
		var author: Variant=find_author(JSON.parse_string(match.get_string(1)))
		if author is Dictionary and not author.has("name"):continue
		if author!=null:result.author=author;break
	var text := RegEx.create_from_string("(?is)<(script|style)[^>]*>.*?</\\1>").sub(html," ",true)
	text=RegEx.create_from_string("<[^>]*>").sub(text," ",true).xml_unescape()
	text=RegEx.create_from_string("\\s+").sub(text," ",true)
	if not result.has("author"):
		var author_match := RegEx.create_from_string("(?i)\\bAuthor\\s+(.{1,120}?)\\s+(?:Resolution|Downloads|Style|Textures|Available Formats)\\b").search(text)
		if author_match:result.author=author_match.get_string(1).strip_edges()
	var formats := RegEx.create_from_string("(?i)Available Formats\\s+(.{1,300}?)(?:Login|Register|CC0|About this asset|Download|$)").search(text)
	if formats:result.formats=[formats.get_string(1)]
	return result
