@tool
extends RefCounted
## Small helpers for providers whose source is an HTML listing.
## Every helper works on a single response body and never runs a request.

## Splits a document on a marker and returns the text after each occurrence.
static func blocks(html: String, marker: String) -> Array[String]:
	var result: Array[String] = []
	var index := html.find(marker)
	while index != -1:
		var start := index + marker.length()
		var next := html.find(marker, start)
		result.append(html.substr(start, (next if next != -1 else html.length()) - start))
		index = next
	return result

## First capture group of a regular expression, or an empty string.
static func match(text: String, pattern: String) -> String:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return ""
	var found := regex.search(text)
	if found == null:
		return ""
	return found.get_string(1) if found.get_strings().size() > 1 else found.get_string(0)

## Every capture group of a regular expression, in document order.
static func matches(text: String, pattern: String) -> Array[String]:
	var regex := RegEx.new()
	if regex.compile(pattern) != OK:
		return []
	var result: Array[String] = []
	for found in regex.search_all(text):
		result.append(found.get_string(1) if found.get_strings().size() > 1 else found.get_string(0))
	return result

## Removes tags and collapses whitespace so titles compare cleanly.
static func text(html: String) -> String:
	var regex := RegEx.new()
	regex.compile("(?s)<script.*?</script>|<style.*?</style>")
	var stripped := regex.sub(html, " ", true)
	regex.compile("<[^>]*>")
	stripped = regex.sub(stripped, " ", true)
	stripped = stripped.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")
	stripped = stripped.replace("&quot;", "\"").replace("&#039;", "'").replace("&nbsp;", " ")
	regex.compile("\\s+")
	stripped = regex.sub(stripped, " ", true)
	return stripped.strip_edges()

## Turns a relative link into an absolute one against the given base.
static func absolute(url: String, base: String) -> String:
	if url.is_empty():
		return ""
	if url.begins_with("https://") or url.begins_with("http://"):
		return url
	if url.begins_with("//"):
		return "https:" + url
	if url.begins_with("/"):
		return base + url
	return base + "/" + url
