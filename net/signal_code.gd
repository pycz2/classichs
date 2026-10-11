class_name SignalCode
extends RefCounted
## Invite and answer codes: the WebRTC offer/answer with all ICE candidates,
## deflated and base64-encoded. A 4-byte checksum rejects damaged codes before
## decompression.

const VERSION := 1
static var _b64 := RegEx.create_from_string("^[A-Za-z0-9+/]+={0,2}$")


static func _sum(data: PackedByteArray) -> PackedByteArray:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(data)
	return h.finish().slice(0, 4)


static func pack(type: String, sdp: String, ice: Array) -> String:
	var z := JSON.stringify({"v": VERSION, "type": type, "sdp": sdp, "ice": ice}).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE)
	return Marshalls.raw_to_base64(_sum(z) + z)


## {"type", "sdp", "ice", "error"}. expect_type ("offer"/"answer") guards against pasting the wrong code.
static func unpack(code: String, expect_type := "") -> Dictionary:
	var bad := {"error": TranslationServer.translate("This is not a valid connection code")}
	code = code.strip_edges().replace("\n", "").replace(" ", "")
	if code.length() < 12 or code.length() % 4 != 0 or _b64.search(code) == null:
		return bad
	var raw := Marshalls.base64_to_raw(code)
	if raw.size() < 6 or raw.slice(0, 4) != _sum(raw.slice(4)):
		return bad
	var j := JSON.new()
	if j.parse(raw.slice(4).decompress_dynamic(1 << 20, FileAccess.COMPRESSION_DEFLATE).get_string_from_utf8()) != OK:
		return bad
	var d = j.data
	if not d is Dictionary or d.get("v") != float(VERSION) or not d.get("sdp") is String or not d.get("ice") is Array \
			or not d.get("type") in ["offer", "answer"]:
		return bad
	if expect_type != "" and d.type != expect_type:
		return {"error": TranslationServer.translate("This code is an invite, not an answer") if d.type == "offer"
			else TranslationServer.translate("This code is an answer, not an invite")}
	var ice: Array = []
	for c in d.ice:
		if not c is Array or c.size() != 3:
			return bad
		ice.append([str(c[0]), int(c[1]), str(c[2])])
	return {"type": d.type, "sdp": d.sdp, "ice": ice, "error": ""}
