@tool
extends RefCounted
## Pure HTML and metadata parser for OpenGameArt.org. Offline-testable with no network access.

const BASE_URL := "https://opengameart.org"

static func clean_text(text: String) -> String:
	if text.is_empty():
		return ""
	var stripped := RegEx.create_from_string("(?is)<(script|style)[^>]*>.*?</\\1>").sub(text, " ", true)
	stripped = RegEx.create_from_string("<[^>]*>").sub(stripped, " ", true)
	stripped = stripped.xml_unescape()
	stripped = stripped.replace("&nbsp;", " ")
	stripped = stripped.replace("&#039;", "'")
	stripped = stripped.replace("&quot;", "\"")
	stripped = stripped.replace("&amp;", "&")
	return RegEx.create_from_string("\\s+").sub(stripped, " ", true).strip_edges()

static func clean_url(url: String, base := BASE_URL) -> String:
	var trimmed := url.strip_edges()
	if trimmed.is_empty():
		return ""
	if trimmed.begins_with("//"):
		return "https:" + trimmed
	if trimmed.begins_with("http://"):
		return "https://" + trimmed.substr(7)
	if trimmed.begins_with("https://"):
		return trimmed
	if trimmed.begins_with("/"):
		return base + trimmed
	return base + "/" + trimmed

static func extract_slug(href: String) -> String:
	var clean := href.get_slice("?", 0).get_slice("#", 0).strip_edges().trim_suffix("/")
	if clean.contains("/content/"):
		var part := clean.substr(clean.find("/content/") + 9)
		if not part.is_empty():
			return part
	if clean.contains("/node/"):
		var part := clean.substr(clean.find("/node/") + 6)
		if not part.is_empty():
			return part
	var file_name := clean.get_file()
	return file_name if not file_name.is_empty() else "asset"

static func map_art_type(type_str: String) -> String:
	var lower := type_str.to_lower()
	if "3d" in lower or "model" in lower:
		return "model"
	if "texture" in lower or "material" in lower:
		return "material"
	if "sound" in lower or "music" in lower or "audio" in lower or "sfx" in lower:
		return "audio"
	if "2d" in lower or "concept" in lower or "image" in lower or "sprite" in lower:
		return "image"
	return "image"

static func normalize_license(name: String, url := "") -> Dictionary:
	var clean_name := clean_text(name)
	var lower := clean_name.to_lower()
	var canonical_name := clean_name
	var canonical_url := url
	var attribution_required := true

	if "cc0" in lower or "public domain" in lower:
		canonical_name = "CC0"
		canonical_url = "https://creativecommons.org/publicdomain/zero/1.0/"
		attribution_required = false
	elif "oga-by" in lower or "oga by" in lower:
		if "3.0" in lower:
			canonical_name = "OGA-BY 3.0"
			canonical_url = "https://static.opengameart.org/OGA-BY-3.0.txt"
		else:
			canonical_name = "OGA-BY"
			canonical_url = "https://static.opengameart.org/OGA-BY-3.0.txt"
	elif "cc-by-sa" in lower or "by-sa" in lower:
		if "4.0" in lower:
			canonical_name = "CC-BY-SA 4.0"
			canonical_url = "https://creativecommons.org/licenses/by-sa/4.0/"
		elif "3.0" in lower:
			canonical_name = "CC-BY-SA 3.0"
			canonical_url = "https://creativecommons.org/licenses/by-sa/3.0/"
		else:
			canonical_name = "CC-BY-SA"
			canonical_url = "https://creativecommons.org/licenses/by-sa/4.0/"
	elif "cc-by" in lower or "by" in lower:
		if "4.0" in lower:
			canonical_name = "CC-BY 4.0"
			canonical_url = "https://creativecommons.org/licenses/by/4.0/"
		elif "3.0" in lower:
			canonical_name = "CC-BY 3.0"
			canonical_url = "https://creativecommons.org/licenses/by/3.0/"
		else:
			canonical_name = "CC-BY 3.0"
			canonical_url = "https://creativecommons.org/licenses/by/3.0/"
	elif "gpl" in lower:
		if "3.0" in lower or "v3" in lower:
			canonical_name = "GPL 3.0"
			canonical_url = "https://www.gnu.org/licenses/gpl-3.0.html"
		elif "2.0" in lower or "v2" in lower:
			canonical_name = "GPL 2.0"
			canonical_url = "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"
		else:
			canonical_name = "GPL"
			canonical_url = "https://www.gnu.org/licenses/gpl-3.0.html"

	if canonical_url.is_empty() and not url.is_empty():
		canonical_url = clean_url(url)

	return {
		"name": canonical_name,
		"url": canonical_url,
		"attribution_required": attribution_required
	}

static func select_preferred_license(licenses: Array) -> Dictionary:
	if licenses.is_empty():
		return {"name": "Unknown", "url": "", "attribution_required": null}
	# Priority 1: CC0
	for lic: Dictionary in licenses:
		if lic.get("name") == "CC0" or lic.get("attribution_required") == false:
			return lic
	# Priority 2: CC-BY 4.0 / 3.0 or OGA-BY
	for lic: Dictionary in licenses:
		var name: String = str(lic.get("name", ""))
		if name.begins_with("CC-BY") and not name.contains("SA") and not name.contains("NC"):
			return lic
		if name.begins_with("OGA-BY"):
			return lic
	# Fallback to first
	return licenses[0]

static func parse_search_page(html: String, query_url := "") -> Dictionary:
	var items: Array[Dictionary] = []
	var next_cursor := ""

	# Check for views-row elements
	var row_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-row[^\"]*\"[^>]*>(.*?)(?=<div class=\"[^\"]*views-row[^\"]*\"|<div class=\"[^\"]*item-list[^\"]*\"|<ul class=\"[^\"]*pager[^\"]*\"|<nav class=\"pager[^\"]*\"|<!-- /\\.?view|$)")
	var matches := row_regex.search_all(html)

	for m in matches:
		var row_html := m.get_string(1)

		# Title & link
		var title_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-title[^\"]*\"[^>]*>.*?<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		var tm := title_regex.search(row_html)
		if not tm:
			var fallback_title := RegEx.create_from_string("(?is)<a [^>]*href=\"([^\"]*(?:/content/|/node/)[^\"]+)\"[^>]*>(.*?)</a>")
			tm = fallback_title.search(row_html)
		if not tm:
			continue

		var href := clean_url(tm.get_string(1))
		var raw_title := tm.get_string(2)
		var title := clean_text(raw_title)
		var slug := extract_slug(tm.get_string(1))

		# Thumbnail preview
		var thumb_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-field-art-preview[^\"]*\"[^>]*>.*?<img [^>]*src=\"([^\"]+)\"")
		var thumb_match := thumb_regex.search(row_html)
		var thumbnail := ""
		if thumb_match:
			thumbnail = clean_url(thumb_match.get_string(1))
		else:
			var img_fallback := RegEx.create_from_string("(?is)<img [^>]*src=\"([^\"]+)\"")
			var im := img_fallback.search(row_html)
			if im:
				thumbnail = clean_url(im.get_string(1))

		# Art type
		var type_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-field-art-type[^\"]*\"[^>]*>.*?<span class=\"field-content\"[^>]*>(.*?)</span>")
		var type_match := type_regex.search(row_html)
		var type_str := clean_text(type_match.get_string(1)) if type_match else ""
		var type := map_art_type(type_str)

		# Licenses
		var lic_div_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-field-art-licenses[^\"]*\"[^>]*>(.*?)</div>")
		var lic_div_match := lic_div_regex.search(row_html)
		var licenses := []
		if lic_div_match:
			var lic_link_regex := RegEx.create_from_string("(?is)<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
			var lic_matches := lic_link_regex.search_all(lic_div_match.get_string(1))
			for lm in lic_matches:
				licenses.append(normalize_license(lm.get_string(2), lm.get_string(1)))
			if licenses.is_empty():
				var plain := clean_text(lic_div_match.get_string(1))
				if not plain.is_empty():
					for part in plain.split(","):
						if not part.strip_edges().is_empty():
							licenses.append(normalize_license(part))

		var primary_lic := select_preferred_license(licenses)

		# Author / Submitter
		var name_regex := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-name[^\"]*\"[^>]*>.*?<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		var nm := name_regex.search(row_html)
		var authors := []
		if nm:
			authors.append({"name": clean_text(nm.get_string(2)), "url": clean_url(nm.get_string(1))})
		else:
			var plain_name := RegEx.create_from_string("(?is)<div class=\"[^\"]*views-field-name[^\"]*\"[^>]*>.*?<span class=\"field-content\"[^>]*>(.*?)</span>")
			var pnm := plain_name.search(row_html)
			if pnm:
				var an := clean_text(pnm.get_string(1))
				if not an.is_empty():
					authors.append({"name": an, "url": ""})

		var asset := {
			"provider_id": "opengameart",
			"provider": "OpenGameArt",
			"id": slug,
			"title": title,
			"type": type,
			"url": href,
			"thumbnail": thumbnail,
			"description": "",
			"tags": [],
			"price": {"free": true, "credits": 0},
			"authors": authors,
			"author": authors[0].name if not authors.is_empty() else "",
			"license": primary_lic,
			"licenses": licenses,
			"selected_license": primary_lic,
			"attribution_text": "",
			"metadata_source_url": href,
			"source_metadata": {
				"submitter": authors[0] if not authors.is_empty() else {},
				"art_type": type_str,
				"licenses": licenses
			},
			"retrieved_utc": Time.get_datetime_string_from_system(true),
			"variants": []
		}
		items.append(asset)

	# Next cursor pagination check
	var pager_next_regex := RegEx.create_from_string("(?is)<li class=\"[^\"]*pager-next[^\"]*\"[^>]*>.*?<a [^>]*href=\"([^\"]+)\"")
	var pnm := pager_next_regex.search(html)
	if pnm:
		var href := pnm.get_string(1).replace("&amp;", "&")
		var page_num_regex := RegEx.create_from_string("[?&]page=([0-9]+)")
		var pmatch := page_num_regex.search(href)
		if pmatch:
			next_cursor = pmatch.get_string(1)

	return {
		"items": items,
		"next_cursor": next_cursor,
		"total": -1
	}

static func parse_asset_page(html: String, asset_url := "") -> Dictionary:
	var result := {
		"metadata_source_url": asset_url
	}

	# Title
	var title_regex := RegEx.create_from_string("(?is)<h1 [^>]*id=\"page-title\"[^>]*>(.*?)</h1>")
	var tm := title_regex.search(html)
	if not tm:
		var fallback_title := RegEx.create_from_string("(?is)<h1 [^>]*class=\"[^\"]*title[^\"]*\"[^>]*>(.*?)</h1>")
		tm = fallback_title.search(html)
	if not tm:
		var h1_any := RegEx.create_from_string("(?is)<h1[^>]*>(.*?)</h1>")
		tm = h1_any.search(html)
	if tm:
		result.title = clean_text(tm.get_string(1))

	# Description / Body
	var body_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-body|art-description)[^\"]*\"[^>]*>")
	var bsm := body_start.search(html)
	if bsm:
		var start := bsm.get_end()
		var next_section := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-|art-author|art-license|art-downloads)[^\"]*\"")
		var nsm := next_section.search(html, start)
		var body_html := html.substr(start, (nsm.get_start() - start) if nsm else -1)
		result.description = clean_text(body_html)

	# Authors: Check declared author first (field-name-field-art-author)
	var declared_authors := []
	var author_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-field-art-author|art-author-info)[^\"]*\"[^>]*>")
	var asm := author_start.search(html)
	if asm:
		var astart := asm.get_end()
		var anext := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-|art-license|art-downloads)[^\"]*\"")
		var anm := anext.search(html, astart)
		var author_html := html.substr(astart, (anm.get_start() - astart) if anm else 500)
		var link_regex := RegEx.create_from_string("(?is)<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		var link_matches := link_regex.search_all(author_html)
		for lm in link_matches:
			declared_authors.append({
				"name": clean_text(lm.get_string(2)),
				"url": clean_url(lm.get_string(1))
			})
		if declared_authors.is_empty():
			var author_plain := clean_text(author_html).trim_prefix("Author").strip_edges()
			if not author_plain.is_empty():
				for name in author_plain.split(","):
					var clean_name := name.strip_edges()
					if not clean_name.is_empty():
						declared_authors.append({"name": clean_name, "url": ""})

	# Submitter
	var submitter := {}
	var sub_regex := RegEx.create_from_string("(?is)Submitted by.*?<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
	var subm := sub_regex.search(html)
	if not subm:
		var post_regex := RegEx.create_from_string("(?is)Posted by.*?<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		subm = post_regex.search(html)
	if subm:
		submitter = {
			"name": clean_text(subm.get_string(2)),
			"url": clean_url(subm.get_string(1))
		}

	if not declared_authors.is_empty():
		result.authors = declared_authors
		result.author = declared_authors[0].name
	elif not submitter.is_empty():
		result.authors = [submitter]
		result.author = submitter.name
	else:
		result.authors = []
		result.author = ""

	result.submitter = submitter
	result.declared_authors = declared_authors

	# Attribution / Copyright notice
	var attr_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-field-art-attribution|art-attribution-notice)[^\"]*\"[^>]*>")
	var attr_match := attr_start.search(html)
	if attr_match:
		var start := attr_match.get_end()
		var anext := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-|art-license|art-downloads)[^\"]*\"")
		var anm := anext.search(html, start)
		var attr_html := html.substr(start, (anm.get_start() - start) if anm else 500)
		result.attribution_text = clean_text(attr_html).trim_prefix("Copyright/Attribution Notice:").strip_edges()

	# Licenses
	var licenses: Array[Dictionary] = []
	var lic_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-field-art-licenses|art-license-info)[^\"]*\"[^>]*>")
	var lsm := lic_start.search(html)
	if lsm:
		var start := lsm.get_end()
		var lnext := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-|art-downloads)[^\"]*\"")
		var lnm := lnext.search(html, start)
		var lic_html := html.substr(start, (lnm.get_start() - start) if lnm else 1000)
		var lic_link_regex := RegEx.create_from_string("(?is)<a [^>]*href=\"([^\"]+)\"[^>]*>(.*?)</a>")
		var lmatches := lic_link_regex.search_all(lic_html)
		for lm in lmatches:
			licenses.append(normalize_license(lm.get_string(2), lm.get_string(1)))
		if licenses.is_empty():
			var plain := clean_text(lic_html).trim_prefix("License(s):").trim_prefix("Licenses").strip_edges()
			for part in plain.split(","):
				var token := part.strip_edges()
				if not token.is_empty():
					licenses.append(normalize_license(token))

	result.licenses = licenses
	result.selected_license = select_preferred_license(licenses)
	result.license = result.selected_license

	# Downloadable files
	var files: Array[Dictionary] = []
	var files_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-field-art-files|art-downloads)[^\"]*\"[^>]*>")
	var fsm := files_start.search(html)
	var files_html := ""
	if fsm:
		var start_idx := fsm.get_end()
		var next_field := RegEx.create_from_string("(?is)<div class=\"[^\"]*field-name-(?!field-art-files)[^\"]*\"")
		var nfm := next_field.search(html, start_idx)
		files_html = html.substr(start_idx, (nfm.get_start() - start_idx) if nfm else -1)
	else:
		files_html = html

	var file_entry_regex := RegEx.create_from_string("(?is)<a [^>]*href=\"([^\"]*(?:/sites/default/files/|/files/)[^\"]+)\"[^>]*>(.*?)</a>(?:\\s*<span class=\"[^\"]*file-size[^\"]*\"[^>]*>\\(([^)]+)\\)</span>|\\s*\\(([^)]+)\\))?")
	var fe_matches := file_entry_regex.search_all(files_html)
	var seen := {}
	for fe in fe_matches:
		var file_url := clean_url(fe.get_string(1))
		var link_text := clean_text(fe.get_string(2))
		var file_name := link_text.get_file()
		if file_name.is_empty():
			file_name = file_url.get_file().get_slice("?", 0)
		var size := clean_text(fe.get_string(3))
		if size.is_empty():
			size = clean_text(fe.get_string(4))
		if not seen.has(file_name.to_lower()):
			seen[file_name.to_lower()] = true
			files.append({
				"filename": file_name,
				"url": file_url,
				"size": size
			})

	result.files = files

	# Tags
	var tags: Array[String] = []
	var tags_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*(?:field-name-field-art-tags|field-name-tags)[^\"]*\"[^>]*>")
	var tsm := tags_start.search(html)
	if tsm:
		var start := tsm.get_end()
		var tnext := RegEx.create_from_string("(?is)<div class=\"[^\"]*field-name-[^\"]*\"")
		var tnm := tnext.search(html, start)
		var tags_html := html.substr(start, (tnm.get_start() - start) if tnm else 500)
		var tag_link_regex := RegEx.create_from_string("(?is)<a [^>]*>(.*?)</a>")
		for tag_match in tag_link_regex.search_all(tags_html):
			var tag := clean_text(tag_match.get_string(1))
			if not tag.is_empty() and tag not in tags:
				tags.append(tag)
	result.tags = tags

	# Previews
	var previews: Array[String] = []
	var prev_start := RegEx.create_from_string("(?is)<div class=\"[^\"]*field-name-field-art-preview[^\"]*\"[^>]*>")
	var psm := prev_start.search(html)
	if psm:
		var start := psm.get_end()
		var pnext := RegEx.create_from_string("(?is)<div class=\"[^\"]*field-name-[^\"]*\"")
		var pnm := pnext.search(html, start)
		var prev_html := html.substr(start, (pnm.get_start() - start) if pnm else 1000)
		var img_regex := RegEx.create_from_string("(?is)<img [^>]*src=\"([^\"]+)\"")
		for im in img_regex.search_all(prev_html):
			previews.append(clean_url(im.get_string(1)))
	result.preview_images = previews
	if not previews.is_empty():
		result.thumbnail = previews[0]

	return result
