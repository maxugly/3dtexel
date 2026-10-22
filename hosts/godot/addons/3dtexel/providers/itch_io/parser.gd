@tool
extends RefCounted
## Pure XML parser for itch.io RSS feeds into normalized asset dictionaries.

static func parse_feed(xml_text: String) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var parser := XMLParser.new()
	var err := parser.open_buffer(xml_text.to_utf8_buffer())
	if err != OK:
		return items

	var in_item := false
	var current_item := {}
	var current_tag := ""

	while parser.read() == OK:
		var node_type := parser.get_node_type()

		if node_type == XMLParser.NODE_ELEMENT:
			var tag_name := parser.get_node_name().to_lower()
			current_tag = tag_name

			if tag_name == "item":
				in_item = true
				current_item = {
					"title": "",
					"link": "",
					"guid": "",
					"creator": "",
					"description": "",
					"thumbnail": "",
					"download_url": "",
					"pub_date": ""
				}
			elif in_item:
				if tag_name == "media:thumbnail" or tag_name == "thumbnail":
					for i in range(parser.get_attribute_count()):
						if parser.get_attribute_name(i).to_lower() == "url":
							current_item["thumbnail"] = parser.get_attribute_value(i)
				elif tag_name == "enclosure":
					for i in range(parser.get_attribute_count()):
						if parser.get_attribute_name(i).to_lower() == "url":
							current_item["download_url"] = parser.get_attribute_value(i)

		elif node_type == XMLParser.NODE_TEXT and in_item:
			var text := parser.get_node_data().strip_edges()
			if not text.is_empty():
				match current_tag:
					"title": current_item["title"] = text
					"link": current_item["link"] = text
					"guid": current_item["guid"] = text
					"dc:creator", "creator", "author": current_item["creator"] = text
					"description": current_item["description"] = text
					"pubdate": current_item["pub_date"] = text

		elif node_type == XMLParser.NODE_ELEMENT_END:
			var end_tag := parser.get_node_name().to_lower()
			if end_tag == "item" and in_item:
				in_item = false
				if not str(current_item.get("link", "")).is_empty():
					items.append(current_item)
				current_item = {}
			current_tag = ""

	return items
