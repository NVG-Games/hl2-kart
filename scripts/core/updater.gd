class_name Updater
extends Node
## Asks GitHub once for the latest release and reports it when it is newer than
## this build (version.json). Silent when offline or when there is no release.

signal update_available(version: String, url: String)

const API := "https://api.github.com/repos/%s/releases/latest"

var _http: HTTPRequest


func check() -> void:
	if not Game.settings.get("check_updates", true) or Game.version == "":
		return
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	add_child(_http)
	_http.request_completed.connect(_on_done)
	var headers := ["User-Agent: HL2Kart/" + Game.version, "Accept: application/vnd.github+json"]
	if _http.request(API % Game.repo, headers) != OK:
		_http.queue_free()


func _on_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not d is Dictionary or d.get("draft", false) or d.get("prerelease", false):
		return
	var tag := str(d.get("tag_name", "")).trim_prefix("v")
	if newer(tag, Game.version):
		update_available.emit(tag, str(d.get("html_url", "https://github.com/%s/releases" % Game.repo)))


## True when version a (like "0.2.1") is later than b.
static func newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return x > y
	return false
