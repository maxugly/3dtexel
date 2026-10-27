@tool
extends RefCounted
## Four workflow states, not four legal licenses. Preserve original terms separately.
enum Status { PERMISSIVE, UNKNOWN, ATTRIBUTION, BLOCKED }
const LABELS := ["Permissive / no credit required","Unknown / review","Commercial with attribution","Blocked for this project"]
static func evaluate(asset: Dictionary) -> Dictionary:
	var value: Variant=asset.get("selected_license",asset.get("license",{}))
	var name: String=str(value.get("id",value.get("name",""))) if value is Dictionary else str(value)
	var normalized := name.strip_edges().to_lower().replace(" ","-")
	var price: Dictionary=asset.get("price",{})
	if (price.has("free") and not price.free) or float(price.get("credits",0))>0:return {"status":Status.BLOCKED,"reason":"Paid asset; entitlement not verified. Paid downloads are not supported."}
	if not price.has("free"):return {"status":Status.UNKNOWN,"reason":"Price/entitlement metadata is missing; review before distribution."}
	if normalized in ["cc0","cc0-1.0","cc0-1.0-universal","cc0-1.0","creative-commons-zero-(cc0)","public-domain"]:return {"status":Status.PERMISSIVE,"reason":"Declared CC0/public domain; retain source and creator metadata."}
	if normalized in ["cc-by-3.0","cc-by-4.0","oga-by-3.0","oga-by-4.0"]:return {"status":Status.ATTRIBUTION,"reason":"Commercial use with attribution and the selected license's additional terms."}
	if "-nd" in normalized or "noderivatives" in normalized or "-nc" in normalized or "noncommercial" in normalized or "all-rights-reserved" in normalized:return {"status":Status.BLOCKED,"reason":"Declared terms conflict with commercial distribution."}
	return {"status":Status.UNKNOWN,"reason":"Terms need review; share-alike/GPL are not automatically prohibited or attribution-only."}
