@tool
extends RefCounted
const PAGE_SIZES := [12,24,48,96,192,512,1024]
const API_PAGE_SIZE := 50
const API_MAX_PAGES := 50
const API_MAX_RESULTS := API_PAGE_SIZE * API_MAX_PAGES
static func request_plan(page: int, count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var first := maxi(0,page-1)*count
	var last := mini(first+count,API_MAX_RESULTS)
	while first<last:
		var api_page := floori(float(first)/API_PAGE_SIZE)+1
		var skip := first % API_PAGE_SIZE
		var take := mini(API_PAGE_SIZE-skip,last-first)
		result.append({"page":api_page,"skip":skip,"take":take})
		first+=take
	return result
