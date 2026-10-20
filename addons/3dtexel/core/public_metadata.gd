@tool
extends RefCounted
static func sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			if str(key).to_lower() not in ["authorization","api_key","token","signed_url","download_url","owned","password","secret","access_token","refresh_token","session_key","apikey","api-key"]:result[key]=sanitize(value[key])
		return result
	if value is Array:
		var result := []
		for item in value:result.append(sanitize(item))
		return result
	if value is String and value.begins_with("https://") and RegEx.create_from_string("(?i)[?&](signature|token|key|authorization|expires|hmac|sig|x-amz-signature|x-amz-credential|x-goog-signature|googleaccessid|policy)=").search(value):return ""
	return value
