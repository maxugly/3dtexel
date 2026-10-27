@tool
extends RefCounted
const BLOCKED_KEYS := {
	"authorization": true, "api_key": true, "token": true, "signed_url": true,
	"download_url": true, "owned": true, "password": true, "secret": true,
	"access_token": true, "refresh_token": true, "session_key": true,
	"apikey": true, "api-key": true
}
static var _signed_url_regex: RegEx
static func _regex() -> RegEx:
	if _signed_url_regex == null:
		_signed_url_regex = RegEx.create_from_string("(?i)[?&](signature|token|key|authorization|expires|hmac|sig|x-amz-signature|x-amz-credential|x-goog-signature|googleaccessid|policy)=")
	return _signed_url_regex
static func sanitize(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value:
			var k := str(key)
			if not BLOCKED_KEYS.has(k.to_lower()):
				result[key] = sanitize(value[key])
		return result
	if value is Array:
		var result := []
		result.resize(value.size())
		for i in value.size():
			result[i] = sanitize(value[i])
		return result
	if value is String and value.begins_with("https://") and ("?" in value or "&" in value):
		if _regex().search(value):
			return ""
	return value
