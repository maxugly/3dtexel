@tool
extends RefCounted
## Decode, resize and cache images on a worker; upload textures on the UI thread.
static func load_for(client: Node,url: String) -> Texture2D:
	var generation: int=client.transport_generation
	var path: String=client.cache.thumbnail_path(url)
	if FileAccess.file_exists(path):
		var global_path := ProjectSettings.globalize_path(path)
		var stored := await image_task(client,func():return Image.load_from_file(global_path))
		if generation!=client.transport_generation:return null
		if stored:return ImageTexture.create_from_image(stored)
	if not client.allowed_thumbnails.has(url) and not client.network_allowed:return null
	var result: Dictionary=await client.get_bytes(url,"",8*1024*1024)
	if result.has("error"):return null
	var bytes: PackedByteArray=result.get("bytes",PackedByteArray())
	var global_save := ProjectSettings.globalize_path(path)
	var image := await image_task(client,func():return decode(bytes,global_save))
	if not image or generation!=client.transport_generation:return null
	client.allowed_thumbnails.erase(url)
	return ImageTexture.create_from_image(image)

static func image_task(client: Node,work: Callable) -> Image:
	var holder := {"image":null}
	var task := WorkerThreadPool.add_task(func():holder.image=work.call())
	var tasks: Array=client.get_meta("thumbnail_tasks",[])
	tasks.append(task);client.set_meta("thumbnail_tasks",tasks)
	while task in tasks and not WorkerThreadPool.is_task_completed(task):await client.get_tree().process_frame
	if task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
		tasks.erase(task)
	return holder.image

static func decode(bytes: PackedByteArray,global_path: String) -> Image:
	var image := Image.new();var error := ERR_FILE_UNRECOGNIZED
	if bytes.size()>=4 and bytes[0]==137 and bytes[1]==80:error=image.load_png_from_buffer(bytes)
	elif bytes.size()>=2 and bytes[0]==255 and bytes[1]==216:error=image.load_jpg_from_buffer(bytes)
	elif bytes.size()>=12 and bytes.slice(0,4).get_string_from_ascii()=="RIFF":error=image.load_webp_from_buffer(bytes)
	if error!=OK or image.is_empty():return null
	image.resize(192,192,Image.INTERPOLATE_BILINEAR)
	image.save_png(global_path)
	return image

static func finish_tasks(client: Node) -> void:
	var tasks: Array=client.get_meta("thumbnail_tasks",[])
	for task in tasks:WorkerThreadPool.wait_for_task_completion(int(task))
	tasks.clear()
